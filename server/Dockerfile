# Build stage
FROM golang:1.24-alpine AS builder

WORKDIR /build

# Copy go mod files first for layer caching
COPY server/go.mod server/go.sum ./server/
WORKDIR /build/server
RUN go mod download

# Copy source code
WORKDIR /build
COPY server/ ./server/

# Build static binary
WORKDIR /build/server
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /server ./cmd/server

# Runtime stage - minimal Alpine
FROM alpine:3.21

# CA certs for outbound HTTPS (Gemini API, Google TTS)
RUN apk add --no-cache ca-certificates

WORKDIR /app

# Copy binary
COPY --from=builder /server /app/server

# Copy client and prompts
COPY client/ /app/client/
COPY prompts/ /app/prompts/

# TLS certs will be auto-generated here
VOLUME /app/.certs

ENV PORT=8080
ENV CLIENT_DIR=/app/client
ENV PROMPTS_DIR=/app/prompts
ENV CERT_DIR=/app/.certs

EXPOSE 8080

CMD ["/app/server"]
