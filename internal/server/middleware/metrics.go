package middleware

import (
	"context"
	"net/http"
	"strconv"
	"sync"
	"time"

	"google.golang.org/grpc"
)

type MetricsMiddleware struct {
	mu              sync.Mutex
	requestDuration map[string][]float64
	requestsTotal   map[string]map[string]int
	activeRequests  int
}

func NewMetricsMiddleware() *MetricsMiddleware {
	return &MetricsMiddleware{
		requestDuration: make(map[string][]float64),
		requestsTotal:   make(map[string]map[string]int),
	}
}

func (mm *MetricsMiddleware) Wrap(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mm.mu.Lock()
		mm.activeRequests++
		mm.mu.Unlock()

		defer func() {
			mm.mu.Lock()
			mm.activeRequests--
			mm.mu.Unlock()
		}()

		start := time.Now()

		method := r.Method + " " + r.URL.Path
		cw := &statusWriter{ResponseWriter: w, status: http.StatusOK}

		next.ServeHTTP(cw, r)

		duration := time.Since(start).Seconds()

		mm.mu.Lock()
		defer mm.mu.Unlock()
		mm.requestDuration[method] = append(mm.requestDuration[method], duration)
		if mm.requestsTotal[method] == nil {
			mm.requestsTotal[method] = make(map[string]int)
		}
		statusStr := strconv.Itoa(cw.status)
		mm.requestsTotal[method][statusStr]++
	})
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(status int) {
	w.status = status
	w.ResponseWriter.WriteHeader(status)
}

func (mm *MetricsMiddleware) GRPCInterceptor() grpc.UnaryServerInterceptor {
	return func(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
		mm.mu.Lock()
		mm.activeRequests++
		mm.mu.Unlock()

		defer func() {
			mm.mu.Lock()
			mm.activeRequests--
			mm.mu.Unlock()
		}()

		start := time.Now()

		resp, err := handler(ctx, req)

		duration := time.Since(start).Seconds()
		method := info.FullMethod

		mm.mu.Lock()
		defer mm.mu.Unlock()
		mm.requestDuration[method] = append(mm.requestDuration[method], duration)
		if mm.requestsTotal[method] == nil {
			mm.requestsTotal[method] = make(map[string]int)
		}
		statusStr := "OK"
		if err != nil {
			statusStr = "ERROR"
		}
		mm.requestsTotal[method][statusStr]++

		return resp, err
	}
}
