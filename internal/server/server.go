// Package server wires up the gRPC and REST servers.
package server

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"time"

	"go.uber.org/zap"
	"google.golang.org/grpc"

	"io"

	"github.com/Jdepp007004/Zanzipay/internal/audit"
	"github.com/Jdepp007004/Zanzipay/internal/config"
	"github.com/Jdepp007004/Zanzipay/internal/orchestrator"
	"github.com/Jdepp007004/Zanzipay/internal/policy"
	"github.com/Jdepp007004/Zanzipay/internal/rebac"
	"github.com/Jdepp007004/Zanzipay/internal/server/interceptors"
	"github.com/Jdepp007004/Zanzipay/internal/server/middleware"
	"github.com/Jdepp007004/Zanzipay/pkg/types"
)

// Server wraps gRPC and REST servers.
type Server struct {
	cfg        *config.Config
	orch       *orchestrator.Orchestrator
	rebac      *rebac.Engine
	policy     *policy.Engine
	audit      *audit.Logger
	log        *zap.Logger
	grpc *grpc.Server
	rest *http.Server
}

// New creates a new Server.
func New(cfg *config.Config, orch *orchestrator.Orchestrator, rebacEngine *rebac.Engine, policyEngine *policy.Engine, auditLogger *audit.Logger, log *zap.Logger) *Server {
	return &Server{cfg: cfg, orch: orch, rebac: rebacEngine, policy: policyEngine, audit: auditLogger, log: log}
}

// Start starts both servers and blocks until ctx is cancelled.
func (s *Server) Start(ctx context.Context, authMid *middleware.AuthMiddleware, rateLimitMid *middleware.RateLimiter, metricsMid *middleware.MetricsMiddleware) error {
	grpcAddr := fmt.Sprintf(":%d", s.cfg.Server.GRPCPort)
	lis, err := net.Listen("tcp", grpcAddr)
	if err != nil {
		return fmt.Errorf("listening on %s: %w", grpcAddr, err)
	}

	s.grpc = grpc.NewServer(
		grpc.ChainUnaryInterceptor(interceptors.RecoveryInterceptor(s.log), interceptors.AuditInterceptor(s.log)),
	)
	s.log.Info("starting gRPC server", zap.String("addr", grpcAddr))
	go func() {
		if err := s.grpc.Serve(lis); err != nil {
			s.log.Error("gRPC server error", zap.Error(err))
		}
	}()

	restAddr := fmt.Sprintf(":%d", s.cfg.Server.RESTPort)
	mux := http.NewServeMux()
	mux.HandleFunc("/v1/check", s.handleCheck)
	mux.HandleFunc("/v1/health", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintln(w, `{"status":"ok"}`)
	})
	mux.HandleFunc("/v1/tuples", s.handleWriteTuples)
	mux.HandleFunc("/v1/tuples/delete", s.handleDeleteTuples)
	mux.HandleFunc("/v1/schema", func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPost {
			s.handleWriteSchema(w, r)
		} else if r.Method == http.MethodGet {
			s.handleReadSchema(w, r)
		} else {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		}
	})
	mux.HandleFunc("/v1/lookup", s.handleLookupResources)
	mux.HandleFunc("/v1/policies", s.handleDeployPolicies)

	var h http.Handler = mux
	if authMid != nil {
		h = authMid.Wrap(h)
	}
	if rateLimitMid != nil {
		h = rateLimitMid.Wrap(h)
	}
	if metricsMid != nil {
		h = metricsMid.Wrap(h)
	}

	s.rest = &http.Server{Addr: restAddr, Handler: h, ReadTimeout: 10 * time.Second, WriteTimeout: 10 * time.Second}
	go func() {
		s.log.Info("starting REST server", zap.String("addr", restAddr))
		if err := s.rest.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			s.log.Error("REST server error", zap.Error(err))
		}
	}()

	<-ctx.Done()
	return s.Stop()
}

func (s *Server) handleCheck(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var req struct {
		ResourceType string `json:"resource_type"`
		ResourceID   string `json:"resource_id"`
		Permission   string `json:"permission"`
		SubjectType  string `json:"subject_type"`
		SubjectID    string `json:"subject_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid body", http.StatusBadRequest)
		return
	}
	decision, err := s.orch.Authorize(r.Context(), &orchestrator.AuthzRequest{
		ResourceType: req.ResourceType, ResourceID: req.ResourceID,
		Permission: req.Permission, SubjectType: req.SubjectType,
		SubjectID: req.SubjectID, Action: req.Permission,
	})
	if err != nil {
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"allowed":        decision.Allowed,
		"verdict":        verdictStr(decision.Allowed),
		"decision_token": decision.DecisionToken,
		"reasoning":      decision.Reasoning,
	})
}

func (s *Server) handleWriteTuples(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var tuples []types.Tuple
	if err := json.NewDecoder(r.Body).Decode(&tuples); err != nil {
		http.Error(w, "invalid body", http.StatusBadRequest)
		return
	}
	zookie, err := s.rebac.WriteTuples(r.Context(), tuples)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	json.NewEncoder(w).Encode(map[string]string{"zookie": zookie})
}

func (s *Server) handleDeleteTuples(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var filter types.TupleFilter
	if err := json.NewDecoder(r.Body).Decode(&filter); err != nil {
		http.Error(w, "invalid body", http.StatusBadRequest)
		return
	}
	zookie, err := s.rebac.DeleteTuples(r.Context(), filter)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	json.NewEncoder(w).Encode(map[string]string{"zookie": zookie})
}

func (s *Server) handleWriteSchema(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(r.Body)
	if err := s.rebac.WriteSchema(r.Context(), string(body)); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

func (s *Server) handleReadSchema(w http.ResponseWriter, r *http.Request) {
	schemaInfo, err := s.rebac.ReadSchema(r.Context())
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	json.NewEncoder(w).Encode(map[string]string{"schema": schemaInfo})
}

func (s *Server) handleLookupResources(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var filter types.TupleFilter
	if err := json.NewDecoder(r.Body).Decode(&filter); err != nil {
		http.Error(w, "invalid body", http.StatusBadRequest)
		return
	}
	iter, err := s.rebac.ReadTuples(r.Context(), filter)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	defer iter.Close()
	var tuples []types.Tuple
	for {
		t, err := iter.Next()
		if err != nil || t == nil {
			break
		}
		tuples = append(tuples, *t)
	}
	json.NewEncoder(w).Encode(map[string]interface{}{"tuples": tuples})
}

func (s *Server) handleDeployPolicies(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	body, _ := io.ReadAll(r.Body)
	version, _, err := s.policy.DeployPolicies(r.Context(), string(body))
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	json.NewEncoder(w).Encode(map[string]string{"version": version})
}

// Stop gracefully shuts down.
func (s *Server) Stop() error {
	if s.grpc != nil {
		s.grpc.GracefulStop()
	}
	if s.rest != nil {
		s.rest.Shutdown(context.Background())
	}
	s.log.Info("server stopped")
	return nil
}

func verdictStr(allowed bool) string {
	if allowed {
		return "ALLOWED"
	}
	return "DENIED"
}
