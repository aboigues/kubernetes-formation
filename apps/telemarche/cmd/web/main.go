// Télémarché — la vitrine web, fil rouge des TP.
//
// Elle sert une page statique et relaie tout ce qui commence par /api/ vers
// l'API (variable API_URL, défaut http://api). Le nom « api » est résolu par
// le DNS du cluster à CHAQUE requête : la vitrine démarre même si l'API
// n'existe pas encore, et suit ses changements d'adresse.
//
// Les connexions vers l'API ne sont pas réutilisées (keep-alive désactivé) :
// chaque requête peut ainsi atteindre un pod différent derrière le Service, ce
// qui rend la répartition de charge visible sur la page.
//
// Configuration : PORT (8080), API_URL (http://api), LOG_LEVEL (info).
package main

import (
	"embed"
	"encoding/json"
	"fmt"
	"io/fs"
	"log/slog"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strings"
	"time"
)

var version = "dev"

//go:embed static
var static embed.FS

func main() {
	var level slog.Level
	if err := level.UnmarshalText([]byte(env("LOG_LEVEL", "info"))); err != nil {
		fmt.Fprintf(os.Stderr, "configuration invalide : LOG_LEVEL=%q (valeurs acceptées : debug, info, warn, error)\n", os.Getenv("LOG_LEVEL"))
		os.Exit(1)
	}
	log := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: level}))
	hostname, _ := os.Hostname()

	target, err := url.Parse(env("API_URL", "http://api"))
	if err != nil || target.Host == "" {
		log.Error("API_URL invalide", "valeur", os.Getenv("API_URL"))
		os.Exit(1)
	}
	proxy := httputil.NewSingleHostReverseProxy(target)
	proxy.Transport = &http.Transport{DisableKeepAlives: true, ResponseHeaderTimeout: 10 * time.Second}
	proxy.ErrorHandler = func(w http.ResponseWriter, r *http.Request, err error) {
		log.Warn("API injoignable", "url", target.String(), "err", err)
		http.Error(w, "API injoignable : "+err.Error(), http.StatusBadGateway)
	}

	site, _ := fs.Sub(static, "static")
	mux := http.NewServeMux()
	mux.Handle("/api/", proxy)
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { fmt.Fprintln(w, "ok") })
	mux.HandleFunc("GET /ready", func(w http.ResponseWriter, _ *http.Request) { fmt.Fprintln(w, "ready") })
	mux.HandleFunc("GET /version", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		_ = json.NewEncoder(w).Encode(map[string]string{"service": "web", "version": version, "pod": hostname})
	})
	mux.Handle("/", http.FileServerFS(site))

	port := env("PORT", "8080")
	srv := &http.Server{
		Addr:              ":" + port,
		ReadHeaderTimeout: 5 * time.Second,
		Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if !strings.HasPrefix(r.URL.Path, "/api/") {
				w.Header().Set("X-Telemarche-Web", hostname)
			}
			log.Debug("requête", "methode", r.Method, "chemin", r.URL.Path)
			mux.ServeHTTP(w, r)
		}),
	}
	log.Info("démarrage", "version", version, "port", port, "api", target.String())
	if err := srv.ListenAndServe(); err != nil {
		log.Error("serveur HTTP", "err", err)
		os.Exit(1)
	}
}

func env(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}
