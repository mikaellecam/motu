// Command server serves market data to the app and keeps it up to date
// (BRIEF §8). Configuration comes from the environment (.env.example).
package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"syscall"
	"time"

	"finance-companion/backend/internal/catalogue"
	"finance-companion/backend/internal/jobs"
	"finance-companion/backend/internal/provider"
	"finance-companion/backend/internal/store"
)

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func envInt(key string, fallback int) int {
	if v, err := strconv.Atoi(os.Getenv(key)); err == nil {
		return v
	}
	return fallback
}

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	dbPath := env("DB_PATH", "data/market.db")
	if err := os.MkdirAll(filepath.Dir(dbPath), 0o755); err != nil {
		log.Error("data directory", "err", err)
		os.Exit(1)
	}
	db, err := store.Open(dbPath)
	if err != nil {
		log.Error("open store", "err", err)
		os.Exit(1)
	}
	defer db.Close()
	if err := db.UpsertAssets(ctx, catalogue.Assets); err != nil {
		log.Error("seed catalogue", "err", err)
		os.Exit(1)
	}

	floor, err := time.Parse(time.DateOnly, env("DATA_FLOOR", "2000-01-03"))
	if err != nil {
		log.Error("DATA_FLOOR", "err", err)
		os.Exit(1)
	}
	if key := os.Getenv("TWELVEDATA_API_KEY"); key != "" {
		syncer := &jobs.Syncer{
			Store:    db,
			Provider: provider.NewTwelveData(key),
			// Defaults leave room under the free plan's 8/min and 800/day
			// for quotes and manual calls (ADR-004).
			Budget:    jobs.NewBudget(envInt("PROVIDER_CREDITS_PER_MINUTE", 8), envInt("PROVIDER_CREDITS_PER_DAY", 400)),
			DataFloor: floor,
			Now:       time.Now,
			Log:       log,
		}
		go syncer.RunDaily(ctx)
	} else {
		log.Warn("TWELVEDATA_API_KEY not set: market data is not synced")
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.Write([]byte("ok"))
	})
	srv := &http.Server{Addr: ":" + env("PORT", "8080"), Handler: mux}
	go func() {
		<-ctx.Done()
		shutdown, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		srv.Shutdown(shutdown)
	}()
	log.Info("listening", "addr", srv.Addr)
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Error("server stopped", "err", err)
		os.Exit(1)
	}
}
