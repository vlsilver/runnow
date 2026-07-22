package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/vlsilver/runnow/backend/internal/backend"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	config, err := backend.LoadConfig()
	if err != nil {
		slog.Error("invalid configuration", "error", err)
		os.Exit(1)
	}
	deps, err := backend.NewDependencies(ctx, config)
	if err != nil {
		slog.Error("initialize dependencies", "error", err)
		os.Exit(1)
	}
	defer deps.Close()
	server := &http.Server{Addr: fmt.Sprintf(":%d", config.Port), Handler: backend.NewWorkerServer(config, deps), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 30 * time.Second, WriteTimeout: 60 * time.Second, IdleTimeout: 90 * time.Second}
	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		_ = server.Shutdown(shutdownCtx)
	}()
	slog.Info("worker listening", "address", server.Addr)
	if err = server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		slog.Error("worker stopped", "error", err)
		os.Exit(1)
	}
}
