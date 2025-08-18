package main

import (
	"os"

	"gopkg.in/yaml.v3"
)

type ServiceConfig struct {
	Name              string   `yaml:"name"`
	URL               string   `yaml:"url"`
	HealthCheck       string   `yaml:"health_check"`
	InternalPrefix    string   `yaml:"internal_prefix"`
	InternalWhitelist []string `yaml:"internal_whitelist"`
}

type Config struct {
	Services []ServiceConfig `yaml:"services"`
}

func LoadConfig(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, err
	}

	return &cfg, nil
}

