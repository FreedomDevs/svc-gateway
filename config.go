package main

type ServiceConfig struct {
	Name              string
	URL               string
	HealthCheck       string
	InternalPrefix    string
	InternalWhitelist []string
}

var Services = []ServiceConfig{
	{
		Name:              "users",
		URL:               "http://localhost:8001",
		HealthCheck:       "/health",
		InternalPrefix:    "/users/internal",
		InternalWhitelist: []string{"127.0.0.1"},
	},
	{
		Name:              "coins",
		URL:               "http://localhost:8002",
		HealthCheck:       "/health",
		InternalPrefix:    "/coins/internal",
		InternalWhitelist: []string{"127.0.0.1"},
	},
}

