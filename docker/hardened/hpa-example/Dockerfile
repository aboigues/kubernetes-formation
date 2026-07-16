# Remplacement de registry.k8s.io/hpa-example.
#
# Multi-stage : le binaire est compilé ici, pas fourni à côté. Un `docker build`
# depuis un clone du dépôt suffit à reproduire l'image publiée.
FROM golang:1.26.5-alpine AS build
WORKDIR /src
COPY go.mod main.go ./
# CGO_ENABLED=0 : binaire statique, indispensable pour tourner dans scratch
# (aucune libc n'y est présente).
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /server main.go

# Aucune image de base : scratch ne contient aucun paquet OS, donc aucune CVE OS
# n'est possible par construction — et il n'y aura jamais de re-durcissement à faire.
FROM scratch
COPY --from=build /server /server
# 65534 = nobody. Pas de /etc/passwd dans scratch, l'uid numérique est donc requis.
USER 65534
EXPOSE 8080
ENTRYPOINT ["/server"]
