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

	"finance-companion/backend/internal/api"
	"finance-companion/backend/internal/catalogue"
	"finance-companion/backend/internal/fx"
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
	quotes := jobs.NewQuoteCache()
	if key := os.Getenv("TWELVEDATA_API_KEY"); key != "" {
		market := provider.NewTwelveData(key)
		// One budget for every job: they share the provider's credits. The
		// default daily share leaves room for manual calls (ADR-004).
		budget := jobs.NewBudget(envInt("PROVIDER_CREDITS_PER_MINUTE", 8), envInt("PROVIDER_CREDITS_PER_DAY", 700))
		syncer := &jobs.Syncer{
			Store: db, Provider: market, Budget: budget, DataFloor: floor,
			Now: time.Now, Log: log, Rates: fx.NewFrankfurter(),
		}
		refresher := &jobs.QuoteRefresher{
			Store: db, Provider: market, Budget: budget, Cache: quotes, Now: time.Now, Log: log,
		}
		go syncer.RunDaily(ctx)
		go refresher.Run(ctx)
	} else {
		log.Warn("TWELVEDATA_API_KEY not set: market data is not synced")
	}

	server := &api.Server{
		Store: db, Quotes: quotes, Now: time.Now,
		RequestsPerMinute: envInt("API_REQUESTS_PER_MINUTE", 120),
	}
	srv := &http.Server{
		Addr:              ":" + env("PORT", "8080"),
		Handler:           server.Handler(),
		ReadHeaderTimeout: 10 * time.Second,
	}
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
