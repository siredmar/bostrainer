# Build stage
FROM golang:1.22-alpine AS builder

WORKDIR /build

# Install build dependencies
RUN apk add --no-cache git

# Copy go mod files
COPY server/go.mod server/go.sum ./server/
WORKDIR /build/server
RUN go mod download

# Copy source code
WORKDIR /build
COPY server/ ./server/

# Build the server
WORKDIR /build/server
RUN CGO_ENABLED=0 GOOS=linux go build -o /server ./cmd/server

# Runtime stage
FROM alpine:3.19

# Install CA certificates for HTTPS
RUN apk add --no-cache ca-certificates

WORKDIR /app

# Copy binary from builder
COPY --from=builder /server /app/server

# Copy client files
COPY client/ /app/client/

# Copy prompts
COPY prompts/ /app/prompts/

# Environment variables
ENV PORT=8080
ENV CLIENT_DIR=/app/client
ENV PROMPTS_DIR=/app/prompts

EXPOSE 8080

CMD ["/app/server"]
