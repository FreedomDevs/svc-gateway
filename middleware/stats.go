package middleware

import (
	"fmt"
	"net/http"
	"sync"
)

var (
	statsMutex sync.Mutex
	stats      = make(map[string]int)
	totalReq   int
)

func StatsMiddleware(service string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		statsMutex.Lock()
		stats[service]++
		totalReq++
		statsMutex.Unlock()
		next.ServeHTTP(w, r)
	})
}

func StatsHandler() string {
	statsMutex.Lock()
	defer statsMutex.Unlock()

	res := fmt.Sprintf("Total requests: %d\n", totalReq)
	for svc, cnt := range stats {
		res += fmt.Sprintf("%s: %d\n", svc, cnt)
	}
	return res
}
