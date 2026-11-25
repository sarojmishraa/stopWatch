// Package config loads API configuration from the environment.
package config

import (
	"errors"
	"fmt"
	"net/url"
	"os"
	"strings"
	"time"
)

type Config struct {
	HTTPAddr        string
	DatabaseURL     string
	MigrateOnStart  bool
	ShutdownTimeout time.Duration
	CORSOrigins     []string
	LogLevel        string
	Auth            AuthConfig
}

// AuthConfig describes how bearer tokens are verified. With Neon Auth, set
// NEON_AUTH_BASE_URL and the rest is derived: JWKS at
// <base>/.well-known/jwks.json, and iss = aud = the base URL's origin.
type AuthConfig struct {
	JWKSURL  string
	Issuer   string
	Audience string
}

func Load() (Config, error) {
	cfg := Config{
		HTTPAddr:        env("HTTP_ADDR", ":8080"),
		DatabaseURL:     os.Getenv("DATABASE_URL"),
		MigrateOnStart:  env("MIGRATE_ON_START", "true") == "true",
		ShutdownTimeout: 20 * time.Second,
		CORSOrigins:     splitList(os.Getenv("CORS_ALLOWED_ORIGINS")), // empty = CORS off
		LogLevel:        env("LOG_LEVEL", "info"),
	}

	auth, err := loadAuth()
	if err != nil {
		return Config{}, err
	}
	cfg.Auth = auth

	var problems []error
	if cfg.DatabaseURL == "" {
		problems = append(problems, errors.New("DATABASE_URL is required"))
	}
	for _, origin := range cfg.CORSOrigins {
		if origin == "*" {
			problems = append(problems, errors.New("CORS_ALLOWED_ORIGINS must list explicit origins, not *"))
		}
	}
	return cfg, errors.Join(problems...)
}

func loadAuth() (AuthConfig, error) {
	auth := AuthConfig{
		JWKSURL:  os.Getenv("AUTH_JWKS_URL"),
		Issuer:   os.Getenv("AUTH_ISSUER"),
		Audience: os.Getenv("AUTH_AUDIENCE"),
	}
	if base := strings.TrimRight(os.Getenv("NEON_AUTH_BASE_URL"), "/"); base != "" {
		u, err := url.Parse(base)
		if err != nil || u.Scheme == "" || u.Host == "" {
			return AuthConfig{}, fmt.Errorf("NEON_AUTH_BASE_URL is not a valid URL: %q", base)
		}
		origin := u.Scheme + "://" + u.Host
		if auth.JWKSURL == "" {
			auth.JWKSURL = base + "/.well-known/jwks.json"
		}
		if auth.Issuer == "" {
			auth.Issuer = origin
		}
		if auth.Audience == "" {
			auth.Audience = origin
		}
	}
	if auth.JWKSURL == "" || auth.Issuer == "" || auth.Audience == "" {
		return AuthConfig{}, errors.New(
			"auth is not configured: set NEON_AUTH_BASE_URL, or AUTH_JWKS_URL + AUTH_ISSUER + AUTH_AUDIENCE")
	}
	return auth, nil
}

func env(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return fallback
}

func splitList(raw string) []string {
	var out []string
	for _, part := range strings.Split(raw, ",") {
		if p := strings.TrimSpace(part); p != "" {
			out = append(out, p)
		}
	}
	return out
}
