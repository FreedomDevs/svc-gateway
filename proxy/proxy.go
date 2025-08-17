package proxy

import (
	"net/http"
	"net/http/httputil"
	"net/url"
	"time"
)

type Service struct {
	Name       string
	TargetURL  string
	HealthPath string
	proxy      *httputil.ReverseProxy
}

func NewService(name, targetURL, healthPath string) *Service {
	url, _ := url.Parse(targetURL)
	rp := httputil.NewSingleHostReverseProxy(url)
	rp.FlushInterval = time.Millisecond * 100

	return &Service{
		Name:       name,
		TargetURL:  targetURL,
		HealthPath: healthPath,
		proxy:      rp,
	}
}

func (s *Service) Handler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		s.proxy.ServeHTTP(w, r)
	})
}
