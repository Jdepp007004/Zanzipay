package middleware

import (
	"context"
	"net/http"
	"sync"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/peer"
	"google.golang.org/grpc/status"
)

// bucketTTL is how long a bucket can be idle before it is evicted.
const bucketTTL = 10 * time.Minute

// cleanupInterval is how often the eviction sweep runs.
const cleanupInterval = 5 * time.Minute

type bucket struct {
	tokens     float64
	lastRefill time.Time
}

// RateLimiter is a token-bucket rate limiter keyed by client ID.
// FIX: a background goroutine periodically evicts stale buckets so the
// map does not grow without bound when many unique IPs send requests.
type RateLimiter struct {
	mu      sync.Mutex
	buckets map[string]*bucket
	rate    float64
	burst   int
	stopCh  chan struct{}
}

// NewRateLimiter creates a rate limiter and starts the background cleanup goroutine.
// Call Stop() when the limiter is no longer needed (e.g. on server shutdown).
func NewRateLimiter(ratePerSecond float64, burst int) *RateLimiter {
	rl := &RateLimiter{
		buckets: make(map[string]*bucket),
		rate:    ratePerSecond,
		burst:   burst,
		stopCh:  make(chan struct{}),
	}
	go rl.cleanupLoop()
	return rl
}

// Stop halts the background cleanup goroutine.
func (rl *RateLimiter) Stop() {
	close(rl.stopCh)
}

// cleanupLoop sweeps the bucket map on a fixed interval and removes
// buckets that have not been accessed within bucketTTL.
func (rl *RateLimiter) cleanupLoop() {
	ticker := time.NewTicker(cleanupInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ticker.C:
			rl.evictStale()
		case <-rl.stopCh:
			return
		}
	}
}

func (rl *RateLimiter) evictStale() {
	cutoff := time.Now().Add(-bucketTTL)
	rl.mu.Lock()
	defer rl.mu.Unlock()
	for id, b := range rl.buckets {
		if b.lastRefill.Before(cutoff) {
			delete(rl.buckets, id)
		}
	}
}

// Allow returns true if the client identified by clientID is within its rate limit.
func (rl *RateLimiter) Allow(clientID string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := time.Now()
	b, exists := rl.buckets[clientID]
	if !exists {
		rl.buckets[clientID] = &bucket{
			tokens:     float64(rl.burst) - 1.0,
			lastRefill: now,
		}
		return true
	}

	elapsed := now.Sub(b.lastRefill).Seconds()
	b.tokens += elapsed * rl.rate
	if b.tokens > float64(rl.burst) {
		b.tokens = float64(rl.burst)
	}
	b.lastRefill = now

	if b.tokens >= 1.0 {
		b.tokens -= 1.0
		return true
	}
	return false
}

// Wrap returns an HTTP middleware that rate-limits by RemoteAddr.
func (rl *RateLimiter) Wrap(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		clientID := r.RemoteAddr
		if !rl.Allow(clientID) {
			http.Error(w, "Too Many Requests", http.StatusTooManyRequests)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// GRPCInterceptor returns a unary server interceptor that rate-limits by peer address.
func (rl *RateLimiter) GRPCInterceptor() grpc.UnaryServerInterceptor {
	return func(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
		var clientID string
		p, ok := peer.FromContext(ctx)
		if ok {
			clientID = p.Addr.String()
		} else {
			clientID = "unknown"
		}
		if !rl.Allow(clientID) {
			return nil, status.Error(codes.ResourceExhausted, "rate limit exceeded")
		}
		return handler(ctx, req)
	}
}
