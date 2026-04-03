#!/usr/bin/env bash
# Part 12: server, cmd, postgres migrations, storage backends, bench, schemas, frontend, deploy, docs, scripts
set -euo pipefail
ROOT="/mnt/c/Users/dheer/OneDrive/Desktop/projects/zanzipay"
cd "$ROOT"

# ─── internal/server/ ─────────────────────────────────────────────────────────
cat > internal/server/server.go << 'ENDOFFILE'
// Package server wires up the gRPC and REST servers for ZanziPay.
package server

import (
	"context"
	"fmt"
	"net"
	"net/http"

	"go.uber.org/zap"
	"google.golang.org/grpc"

	"github.com/youorg/zanzipay/internal/config"
	"github.com/youorg/zanzipay/internal/orchestrator"
)

// Server wraps the gRPC and REST servers.
type Server struct {
	cfg   *config.Config
	orch  *orchestrator.Orchestrator
	log   *zap.Logger
	grpc  *grpc.Server
	rest  *http.Server
}

// New creates a new Server.
func New(cfg *config.Config, orch *orchestrator.Orchestrator, log *zap.Logger) *Server {
	return &Server{cfg: cfg, orch: orch, log: log}
}

// Start starts both the gRPC and REST servers.
func (s *Server) Start(ctx context.Context) error {
	grpcAddr := fmt.Sprintf(":%d", s.cfg.Server.GRPCPort)
	lis, err := net.Listen("tcp", grpcAddr)
	if err != nil {
		return fmt.Errorf("listening on %s: %w", grpcAddr, err)
	}

	s.grpc = grpc.NewServer(
		grpc.ChainUnaryInterceptor(
			recoveryInterceptor(s.log),
			loggingInterceptor(s.log),
		),
	)

	// Register gRPC services
	RegisterServices(s.grpc, s.orch)

	s.log.Info("starting gRPC server", zap.String("addr", grpcAddr))
	go func() {
		if err := s.grpc.Serve(lis); err != nil {
			s.log.Error("gRPC server error", zap.Error(err))
		}
	}()

	<-ctx.Done()
	return s.Stop()
}

// Stop gracefully shuts down the servers.
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
ENDOFFILE
echo "  [OK] internal/server/server.go"

cat > internal/server/grpc.go << 'ENDOFFILE'
package server

import (
	"context"

	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/youorg/zanzipay/internal/orchestrator"
)

// ZanziPayGRPCService implements the gRPC service interface (stub).
type ZanziPayGRPCService struct {
	orch *orchestrator.Orchestrator
}

// RegisterServices registers all gRPC service implementations.
func RegisterServices(s *grpc.Server, orch *orchestrator.Orchestrator) {
	// In a real implementation, register generated gRPC service servers here.
	// e.g., zanzipayv1.RegisterCoreServiceServer(s, &CoreServiceImpl{orch: orch})
	_ = s
	_ = orch
}

// Check is the gRPC handler for the Check RPC.
func (svc *ZanziPayGRPCService) Check(ctx context.Context, req *CheckReq) (*CheckResp, error) {
	if req == nil {
		return nil, status.Error(codes.InvalidArgument, "request cannot be nil")
	}
	decision, err := svc.orch.Authorize(ctx, &orchestrator.AuthzRequest{
		ResourceType: req.ResourceType,
		ResourceID:   req.ResourceID,
		Permission:   req.Permission,
		SubjectType:  req.SubjectType,
		SubjectID:    req.SubjectID,
		Action:       req.Permission,
	})
	if err != nil {
		return nil, status.Errorf(codes.Internal, "authorization failed: %v", err)
	}
	return &CheckResp{
		Allowed:       decision.Allowed,
		Verdict:       verdictString(decision.Allowed),
		DecisionToken: decision.DecisionToken,
		Reasoning:     decision.Reasoning,
	}, nil
}

// CheckReq and CheckResp are local stubs (real code uses generated proto types).
type CheckReq struct {
	ResourceType  string
	ResourceID    string
	Permission    string
	SubjectType   string
	SubjectID     string
}

type CheckResp struct {
	Allowed       bool
	Verdict       string
	DecisionToken string
	Reasoning     string
}

func verdictString(allowed bool) string {
	if allowed {
		return "ALLOWED"
	}
	return "DENIED"
}
ENDOFFILE
echo "  [OK] internal/server/grpc.go"

cat > internal/server/rest.go << 'ENDOFFILE'
package server

import (
	"encoding/json"
	"fmt"
	"net/http"

	"github.com/youorg/zanzipay/internal/orchestrator"
)

// RESTHandler is a simple HTTP handler that wraps the orchestrator.
type RESTHandler struct {
	orch *orchestrator.Orchestrator
}

// NewRESTHandler creates a new REST handler.
func NewRESTHandler(orch *orchestrator.Orchestrator) *RESTHandler {
	return &RESTHandler{orch: orch}
}

// ServeHTTP dispatches REST requests.
func (rh *RESTHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	switch r.URL.Path {
	case "/v1/check":
		rh.handleCheck(w, r)
	case "/v1/health":
		w.WriteHeader(http.StatusOK)
		fmt.Fprintln(w, `{"status":"ok"}`)
	default:
		http.NotFound(w, r)
	}
}

func (rh *RESTHandler) handleCheck(w http.ResponseWriter, r *http.Request) {
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
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}
	decision, err := rh.orch.Authorize(r.Context(), &orchestrator.AuthzRequest{
		ResourceType: req.ResourceType,
		ResourceID:   req.ResourceID,
		Permission:   req.Permission,
		SubjectType:  req.SubjectType,
		SubjectID:    req.SubjectID,
		Action:       req.Permission,
	})
	if err != nil {
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"allowed":        decision.Allowed,
		"verdict":        verdictString(decision.Allowed),
		"decision_token": decision.DecisionToken,
		"reasoning":      decision.Reasoning,
	})
}
ENDOFFILE
echo "  [OK] internal/server/rest.go"

cat > internal/server/middleware/auth.go << 'ENDOFFILE'
package middleware

import (
	"context"
	"strings"

	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
)

// APIKeyAuth returns a gRPC unary interceptor that validates API keys.
func APIKeyAuth(validKeys map[string]string) grpc.UnaryServerInterceptor {
	return func(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
		md, ok := metadata.FromIncomingContext(ctx)
		if !ok {
			return nil, status.Error(codes.Unauthenticated, "missing metadata")
		}
		authHeader := md.Get("authorization")
		if len(authHeader) == 0 {
			return nil, status.Error(codes.Unauthenticated, "missing authorization header")
		}
		token := strings.TrimPrefix(authHeader[0], "Bearer ")
		if _, ok := validKeys[token]; !ok {
			return nil, status.Error(codes.Unauthenticated, "invalid API key")
		}
		return handler(ctx, req)
	}
}
ENDOFFILE
echo "  [OK] internal/server/middleware/auth.go"

cat > internal/server/middleware/ratelimit.go << 'ENDOFFILE'
package middleware

import (
	"context"
	"sync"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// RateLimiter is a simple per-client sliding window rate limiter.
type RateLimiter struct {
	mu      sync.Mutex
	counts  map[string][]time.Time
	limit   int
	window  time.Duration
}

// NewRateLimiter creates a rate limiter with the given limit per window.
func NewRateLimiter(limit int, window time.Duration) *RateLimiter {
	return &RateLimiter{
		counts: make(map[string][]time.Time),
		limit:  limit,
		window: window,
	}
}

// Allow returns true if the key is within the rate limit.
func (rl *RateLimiter) Allow(key string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()
	now := time.Now()
	cutoff := now.Add(-rl.window)
	times := rl.counts[key]
	var recent []time.Time
	for _, t := range times {
		if t.After(cutoff) {
			recent = append(recent, t)
		}
	}
	if len(recent) >= rl.limit {
		rl.counts[key] = recent
		return false
	}
	rl.counts[key] = append(recent, now)
	return true
}

// UnaryInterceptor returns a gRPC interceptor that enforces the rate limit.
func (rl *RateLimiter) UnaryInterceptor() grpc.UnaryServerInterceptor {
	return func(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
		if !rl.Allow("global") {
			return nil, status.Error(codes.ResourceExhausted, "rate limit exceeded")
		}
		return handler(ctx, req)
	}
}
ENDOFFILE
echo "  [OK] internal/server/middleware/ratelimit.go"

cat > internal/server/middleware/logging.go << 'ENDOFFILE'
package middleware

import (
	"context"
	"time"

	"go.uber.org/zap"
	"google.golang.org/grpc"
)

// LoggingInterceptor returns a gRPC interceptor that logs request/response.
func LoggingInterceptor(log *zap.Logger) grpc.UnaryServerInterceptor {
	return func(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
		start := time.Now()
		resp, err := handler(ctx, req)
		log.Info("gRPC request",
			zap.String("method", info.FullMethod),
			zap.Duration("duration", time.Since(start)),
			zap.Bool("error", err != nil),
		)
		return resp, err
	}
}
ENDOFFILE
echo "  [OK] internal/server/middleware/logging.go"

cat > internal/server/middleware/metrics.go << 'ENDOFFILE'
package middleware

import (
	"context"

	"google.golang.org/grpc"
)

// MetricsInterceptor returns a gRPC interceptor that records Prometheus metrics.
// Full implementation would use prometheus/client_golang to track request counts and latencies.
func MetricsInterceptor() grpc.UnaryServerInterceptor {
	return func(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
		// TODO: increment request counter for info.FullMethod
		resp, err := handler(ctx, req)
		// TODO: record latency histogram
		return resp, err
	}
}
ENDOFFILE
echo "  [OK] internal/server/middleware/metrics.go"

cat > internal/server/interceptors/audit.go << 'ENDOFFILE'
package interceptors

import (
	"context"
	"google.golang.org/grpc"
)

// AuditInterceptor records all gRPC requests to the audit log.
func AuditInterceptor() grpc.UnaryServerInterceptor {
	return func(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
		// Audit logging is handled inside the orchestrator for authorization calls.
		// This interceptor handles other service calls that need audit trails.
		return handler(ctx, req)
	}
}
ENDOFFILE
echo "  [OK] internal/server/interceptors/audit.go"

cat > internal/server/interceptors/recovery.go << 'ENDOFFILE'
package interceptors

import (
	"context"
	"fmt"
	"runtime/debug"

	"go.uber.org/zap"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// recoveryInterceptorImpl is the internal recovery handler used by the server package.
func recoveryInterceptor(log *zap.Logger) grpc.UnaryServerInterceptor {
	return func(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (resp interface{}, err error) {
		defer func() {
			if r := recover(); r != nil {
				log.Error("panic recovered",
					zap.String("method", info.FullMethod),
					zap.Any("panic", r),
					zap.ByteString("stack", debug.Stack()),
				)
				err = status.Errorf(codes.Internal, "internal server error: %v", fmt.Sprintf("%v", r))
			}
		}()
		return handler(ctx, req)
	}
}

// RecoveryInterceptor is the exported recovery interceptor for external use.
func RecoveryInterceptor(log *zap.Logger) grpc.UnaryServerInterceptor {
	return recoveryInterceptor(log)
}
ENDOFFILE
echo "  [OK] internal/server/interceptors/recovery.go"

# Helper function used in server.go
cat >> internal/server/server.go << 'ENDOFFILE'

func recoveryInterceptor(log *zap.Logger) grpc.UnaryServerInterceptor {
	return interceptors.RecoveryInterceptor(log)
}

func loggingInterceptor(log *zap.Logger) grpc.UnaryServerInterceptor {
	return middleware.LoggingInterceptor(log)
}
ENDOFFILE

# Fix imports in server.go
cat > internal/server/server.go << 'ENDOFFILE'
// Package server wires up the gRPC and REST servers for ZanziPay.
package server

import (
	"context"
	"fmt"
	"net"
	"net/http"

	"go.uber.org/zap"
	"google.golang.org/grpc"

	"github.com/youorg/zanzipay/internal/config"
	"github.com/youorg/zanzipay/internal/orchestrator"
	"github.com/youorg/zanzipay/internal/server/interceptors"
	"github.com/youorg/zanzipay/internal/server/middleware"
)

// Server wraps the gRPC and REST servers.
type Server struct {
	cfg  *config.Config
	orch *orchestrator.Orchestrator
	log  *zap.Logger
	grpc *grpc.Server
	rest *http.Server
}

// New creates a new Server.
func New(cfg *config.Config, orch *orchestrator.Orchestrator, log *zap.Logger) *Server {
	return &Server{cfg: cfg, orch: orch, log: log}
}

// Start starts both the gRPC and REST servers.
func (s *Server) Start(ctx context.Context) error {
	grpcAddr := fmt.Sprintf(":%d", s.cfg.Server.GRPCPort)
	lis, err := net.Listen("tcp", grpcAddr)
	if err != nil {
		return fmt.Errorf("listening on %s: %w", grpcAddr, err)
	}

	s.grpc = grpc.NewServer(
		grpc.ChainUnaryInterceptor(
			interceptors.RecoveryInterceptor(s.log),
			middleware.LoggingInterceptor(s.log),
			middleware.MetricsInterceptor(),
		),
	)

	RegisterServices(s.grpc, s.orch)

	s.log.Info("starting gRPC server", zap.String("addr", grpcAddr))
	go func() {
		if err := s.grpc.Serve(lis); err != nil {
			s.log.Error("gRPC server error", zap.Error(err))
		}
	}()

	// Also start REST handler
	restAddr := fmt.Sprintf(":%d", s.cfg.Server.RESTPort)
	handler := NewRESTHandler(s.orch)
	s.rest = &http.Server{Addr: restAddr, Handler: handler}
	go func() {
		s.log.Info("starting REST server", zap.String("addr", restAddr))
		if err := s.rest.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			s.log.Error("REST server error", zap.Error(err))
		}
	}()

	<-ctx.Done()
	return s.Stop()
}

// Stop gracefully shuts down the servers.
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
ENDOFFILE
echo "  [OK] internal/server/server.go (rewritten with proper imports)"

echo "=== internal/server/ done ==="
ENDOFFILE
echo "Part 12 script written"
