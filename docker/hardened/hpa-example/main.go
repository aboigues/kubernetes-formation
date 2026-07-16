// Remplacement de registry.k8s.io/hpa-example.
//
// L'original tourne sur Debian 8 "jessie", en fin de vie depuis 2020 : ses dépôts
// apt sont archivés, l'image est donc indurcissable (801 CVE OS HIGH/CRITICAL).
//
// Le contrat de cette image tient en deux points : répondre en HTTP, et brûler du
// CPU à chaque requête pour que le HPA ait quelque chose à mesurer. PHP n'y jouait
// aucun rôle. Un binaire statique dans une image scratch n'a aucun paquet OS : il
// ne peut pas avoir de CVE OS, et n'aura jamais besoin d'être re-durci.
//
// La charge est identique à l'originale : la même boucle de sqrt, 1 000 001 tours.
package main

import (
	"fmt"
	"log"
	"math"
	"net/http"
	"os"
	"strconv"
)

// sink empêche le compilateur d'éliminer la boucle comme code mort :
// sans effet observable, le calcul serait supprimé et le HPA n'aurait
// plus rien à mesurer.
var sink float64

// iterations est calibré pour que chaque requête coûte à peu près le même temps
// CPU que l'image d'origine (~300 ms, mesuré contre 279 ms pour l original). Recopier ses 1 000 001 tours donnerait ~2 ms :
// Go est deux ordres de grandeur plus rapide que PHP, le HPA n'aurait rien à mesurer.
var iterations = 20000000

func burn(w http.ResponseWriter, r *http.Request) {
	x := 0.0001
	for i := 0; i <= iterations; i++ {
		x += math.Sqrt(x)
	}
	sink = x
	fmt.Fprint(w, "OK!")
}

func health(w http.ResponseWriter, r *http.Request) {
	fmt.Fprint(w, "ok")
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		// 8080 et non 80 : permet de tourner en non-root sans CAP_NET_BIND_SERVICE.
		port = "8080"
	}
	if v := os.Getenv("BURN_ITERATIONS"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			iterations = n
		}
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", health)
	mux.HandleFunc("/", burn)
	log.Printf("hpa-example à l'écoute sur :%s", port)
	log.Fatal(http.ListenAndServe(":"+port, mux))
}
