// Command api serves the shared EAGLE STUDY / learning dashboard REST API.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
	_ "time/tzdata" // IANA zones available even on minimal container images

	"github.com/eagle-engineering/ecosystem/api/internal/auth"
	"github.com/eagle-engineering/ecosystem/api/internal/config"
	"github.com/eagle-engineering/ecosystem/api/internal/httpapi"
	"github.com/eagle-engineering/ecosystem/api/internal/store"
)

func main() {
	if err := run(); err != nil {
		slog.Error("api exited", "err", err)
		os.Exit(1)
	}
}

func run() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	level := slog.LevelInfo
	_ = level.UnmarshalText([]byte(cfg.LogLevel))
	log := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: level}))
	slog.SetDefault(log)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	if cfg.MigrateOnStart {
		if err := store.Migrate(cfg.DatabaseURL); err != nil {
			return err
		}
		log.Info("migrations applied")
	}

	st, err := store.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer st.Close()

	verifier, err := auth.NewJWKSVerifier(ctx, cfg.Auth.JWKSURL, cfg.Auth.Issuer, cfg.Auth.Audience)
	if err != nil {
		return err
	}

	srv := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           httpapi.New(st, verifier, log, httpapi.Options{CORSOrigins: cfg.CORSOrigins}),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       90 * time.Second,
	}

	errCh := make(chan error, 1)
	go func() {
		log.Info("listening", "addr", cfg.HTTPAddr, "jwks", cfg.Auth.JWKSURL)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- err
		}
		close(errCh)
	}()

	select {
	case err := <-errCh:
		return err
	case <-ctx.Done():
	}
	log.Info("shutting down")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), cfg.ShutdownTimeout)
	defer cancel()
	return srv.Shutdown(shutdownCtx)
}
