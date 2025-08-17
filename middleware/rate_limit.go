package middleware

import (
	"net/http"
	"sync"
	"time"
)

type RateLimiter struct {
	requests map[string]int
	limit    int
	interval time.Duration
	mutex    sync.Mutex
}

func NewRateLimiter(limit int, interval time.Duration) *RateLimiter {
	rl := &RateLimiter{
		requests: make(map[string]int),
		limit:    limit,
		interval: interval,
	}
	go rl.resetLoop()
	return rl
}

func (rl *RateLimiter) Limit(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ip := r.RemoteAddr
		rl.mutex.Lock()
		rl.requests[ip]++
		count := rl.requests[ip]
		rl.mutex.Unlock()

		if count > rl.limit {
			http.Error(w, "Rate limit exceeded", http.StatusTooManyRequests)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (rl *RateLimiter) resetLoop() {
	for {
		time.Sleep(rl.interval)
		rl.mutex.Lock()
		rl.requests = make(map[string]int)
		rl.mutex.Unlock()
	}
}
