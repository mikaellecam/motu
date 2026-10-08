// Package api serves market data to the app over HTTP (BRIEF §8.3): JSON,
// read-only, conditional requests, an error envelope, and a per-client rate
// limit answered with 429 and Retry-After.
package api

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"math"
	"net"
	"net/http"
	"strconv"
	"sync"
	"time"

	"finance-companion/backend/internal/jobs"
	"finance-companion/backend/internal/store"
)

type Server struct {
	Store  *store.Store
	Quotes *jobs.QuoteCache
	// RequestsPerMinute per client IP; 0 disables the limit.
	RequestsPerMinute int
	Now               func() time.Time

	mu      sync.Mutex
	clients map[string][]time.Time
}

// Handler routes every endpoint behind the rate limit.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { w.Write([]byte("ok")) })
	mux.HandleFunc("GET /v1/assets", s.handle(s.assets))
	mux.HandleFunc("GET /v1/assets/{id}/history", s.handle(s.history))
	mux.HandleFunc("GET /v1/quotes", s.handle(s.quotes))
	mux.HandleFunc("GET /v1/fx", s.handle(s.fx))
	mux.HandleFunc("GET /v1/livret/rates", s.handle(s.livret))
	mux.HandleFunc("/", func(w http.ResponseWriter, _ *http.Request) {
		writeError(w, apiError{http.StatusNotFound, "not_found", "no such endpoint"})
	})
	return s.limit(mux)
}

// apiError is written as {"error": {"code": …, "message": …}}.
type apiError struct {
	status  int
	code    string
	message string
}

func (e apiError) Error() string { return e.message }

func badRequest(message string) apiError {
	return apiError{http.StatusBadRequest, "bad_request", message}
}

func writeError(w http.ResponseWriter, e apiError) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(e.status)
	json.NewEncoder(w).Encode(map[string]any{"error": map[string]string{"code": e.code, "message": e.message}})
}

// response is what an endpoint returns: a body, and when its data last
// changed (zero when unknown).
type response struct {
	body         any
	lastModified time.Time
}

// handle turns an endpoint into a handler with conditional requests: an ETag
// over the body, Last-Modified when known, 304 when the client is current.
func (s *Server) handle(endpoint func(*http.Request) (response, error)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		res, err := endpoint(r)
		var e apiError
		if errors.As(err, &e) {
			writeError(w, e)
			return
		}
		if err != nil {
			writeError(w, apiError{http.StatusInternalServerError, "internal", "something went wrong"})
			return
		}
		body, err := json.Marshal(res.body)
		if err != nil {
			writeError(w, apiError{http.StatusInternalServerError, "internal", "something went wrong"})
			return
		}
		sum := sha256.Sum256(body)
		etag := `"` + base64.RawURLEncoding.EncodeToString(sum[:16]) + `"`
		h := w.Header()
		h.Set("ETag", etag)
		h.Set("Cache-Control", "no-cache") // revalidate, which is cheap with the ETag
		if !res.lastModified.IsZero() {
			h.Set("Last-Modified", res.lastModified.UTC().Format(http.TimeFormat))
		}
		if match := r.Header.Get("If-None-Match"); match != "" {
			if match == etag || match == "*" {
				w.WriteHeader(http.StatusNotModified)
				return
			}
		} else if since, err := http.ParseTime(r.Header.Get("If-Modified-Since")); err == nil &&
			!res.lastModified.IsZero() && !res.lastModified.Truncate(time.Second).After(since) {
			w.WriteHeader(http.StatusNotModified)
			return
		}
		h.Set("Content-Type", "application/json")
		w.Write(body)
	}
}

// limit answers 429 with Retry-After once a client IP has made
// RequestsPerMinute requests in the last minute.
func (s *Server) limit(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if s.RequestsPerMinute > 0 {
			if wait := s.admit(clientIP(r)); wait > 0 {
				w.Header().Set("Retry-After", strconv.Itoa(int(math.Ceil(wait.Seconds()))))
				writeError(w, apiError{http.StatusTooManyRequests, "rate_limited", "too many requests, retry later"})
				return
			}
		}
		next.ServeHTTP(w, r)
	})
}

// admit records a request, or returns how long until one is allowed.
func (s *Server) admit(client string) time.Duration {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.clients == nil {
		s.clients = map[string][]time.Time{}
	}
	now := s.Now()
	recent := s.clients[client]
	for len(recent) > 0 && now.Sub(recent[0]) >= time.Minute {
		recent = recent[1:]
	}
	if len(recent) >= s.RequestsPerMinute {
		s.clients[client] = recent
		return recent[0].Add(time.Minute).Sub(now)
	}
	s.clients[client] = append(recent, now)
	return 0
}

// clientIP is the connection's address. Behind a reverse proxy every
// request shares it: configure the limit at the proxy instead.
func clientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}
