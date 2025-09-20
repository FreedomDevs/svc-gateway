package main

import (
	"fmt"
	"log"
	"net/http"
	"time"

	"svc-gateway/middleware"
	"svc-gateway/proxy"
)

const (
	ColorReset  = "\033[0m"
	ColorGreen  = "\033[32m"
	ColorCyan   = "\033[36m"
	ColorYellow = "\033[33m"
)

func PrintServiceStatus(path, url string) {
	fmt.Printf("%s[ADD]%s %s\n", ColorGreen, ColorReset, path)
	fmt.Printf("%s[URL]%s %s\n", ColorCyan, ColorReset, url)
}

func main() {
	mux := http.NewServeMux()
	rl := middleware.NewRateLimiter(100, time.Second)

	cfg, err := LoadConfig("config.yml")
	if err != nil {
		log.Fatal("failed to load config:", err)
	}

	for _, service := range cfg.Services {
		fmt.Printf("Service: %s\n", service.Name)
		fmt.Printf("  URL: %s\n", service.URL)
		fmt.Printf("  HealthCheck: %s\n", service.HealthCheck)
		fmt.Printf("  InternalPrefix: %s\n", service.InternalPrefix)
		fmt.Printf("  InternalWhitelist: %v\n", service.InternalWhitelist)
	}

	for _, svcCfg := range cfg.Services {
		svc := proxy.NewService(svcCfg.Name, svcCfg.URL, svcCfg.HealthCheck)

		var handler http.Handler = svc.Handler()
		handler = middleware.StatsMiddleware(svcCfg.Name, handler)
		handler = middleware.InternalCheck(svcCfg.InternalPrefix, svcCfg.InternalWhitelist, handler)
		handler = rl.Limit(handler)
		handler = middleware.LoggingMiddleware(handler)

		path := "/" + svcCfg.Name + "/" // путь сервиса с завершающим слэшем
		mux.Handle(path, handler)       // без StripPrefix

		// редирект с /users -> /users/
		mux.Handle("/"+svcCfg.Name, http.RedirectHandler(path, http.StatusMovedPermanently))

		PrintServiceStatus(path, svcCfg.URL)
	}

	mux.HandleFunc("/__stats", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(middleware.StatsHandler()))
	})

	fmt.Printf("%s%s%s\n", ColorYellow, "API Gateway running on :8080", ColorReset)
	http.ListenAndServe(":9000", mux)
}
