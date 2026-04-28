package config

import (
	"os"
	"strconv"
	"time"
)

type Config struct {
	VastAIKey       string
	TailscaleAuthKey string
	NodeName        string
	MaxDPH          float64
	MinComputeCap   int
	SearchLimit     int
	SyncInterval    time.Duration
	DefaultImage    string
	Region          string
}

func Load() *Config {
	cfg := &Config{
		VastAIKey:        getEnv("VASTAI_API_KEY", ""),
		TailscaleAuthKey: getEnv("TS_AUTHKEY", ""),
		NodeName:         getEnv("VK_NODE_NAME", "virtual-vastai"),
		MaxDPH:           getEnvFloat("MAX_DPH", 1.0),
		MinComputeCap:    getEnvInt("MIN_COMPUTE_CAP", 700),
		SearchLimit:      getEnvInt("SEARCH_LIMIT", 10),
		SyncInterval:     getEnvDuration("SYNC_INTERVAL", "30s"),
		DefaultImage:     getEnv("DEFAULT_IMAGE", "nvidia/cuda:12.0-base"),
		Region:           getEnv("REGION", ""),
	}
	return cfg
}

func getEnv(key, defaultValue string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return defaultValue
}

func getEnvFloat(key string, defaultValue float64) float64 {
	if v := os.Getenv(key); v != "" {
		if f, err := strconv.ParseFloat(v, 64); err == nil {
			return f
		}
	}
	return defaultValue
}

func getEnvInt(key string, defaultValue int) int {
	if v := os.Getenv(key); v != "" {
		if i, err := strconv.Atoi(v); err == nil {
			return i
		}
	}
	return defaultValue
}

func getEnvDuration(key, defaultValue string) time.Duration {
	v := getEnv(key, defaultValue)
	if d, err := time.ParseDuration(v); err == nil {
		return d
	}
	return 30 * time.Second
}