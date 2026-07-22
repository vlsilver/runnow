FROM golang:1.26-bookworm AS build
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY cmd ./cmd
COPY internal ./internal
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/api ./cmd/api && \
    CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/worker ./cmd/worker

FROM gcr.io/distroless/static-debian12:nonroot AS runtime
COPY --from=build /out/api /api
COPY --from=build /out/worker /worker
USER nonroot:nonroot
ENTRYPOINT ["/api"]
