package middleware

import (
	"net"
	"net/http"
	"strings"
)

func InternalCheck(prefix string, whitelist []string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.URL.Path, prefix) {
			ip, _, _ := net.SplitHostPort(r.RemoteAddr)
			allowed := false
			for _, wip := range whitelist {
				if ip == wip {
					allowed = true
					break
				}
			}
			if !allowed {
				http.Error(w, "Forbidden", http.StatusForbidden)
				return
			}
		}
		next.ServeHTTP(w, r)
	})
}
