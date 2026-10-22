# Télémarché — images de l'application fil rouge.
#
#   docker build --target api --build-arg VERSION=1.0 -t telemachlearning/telemarche-api:1.0 .
#   docker build --target web --build-arg VERSION=1.0 -t telemachlearning/telemarche-web:1.0 .
#
# Image finale distroless « static » : ni shell, ni gestionnaire de paquets,
# utilisateur non-root numérique (65532), presque rien à scanner. Le port 8080
# n'exige aucun privilège, quel que soit le runtime (docker ou containerd).
FROM golang:1.27.3-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY cmd ./cmd
ARG VERSION=dev
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" -o /out/api ./cmd/api \
 && CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" -o /out/web ./cmd/web

FROM gcr.io/distroless/static-debian13:nonroot AS api
# Même binaire sous deux noms : /app/migrate crée le schéma (Job), /app/api sert.
COPY --from=build /out/api /app/api
COPY --from=build /out/api /app/migrate
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/app/api"]

FROM gcr.io/distroless/static-debian13:nonroot AS web
COPY --from=build /out/web /app/web
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/app/web"]
