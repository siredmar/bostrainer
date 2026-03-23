.PHONY: build run clean docker-build docker-up docker-down docker-logs \
       lint vet fmt tidy test help

BINARY     := bostrainer
SERVER_DIR := server
BUILD_DIR  := $(SERVER_DIR)
LDFLAGS    := -s -w

# Environment defaults (override via env or .env)
export PORT       ?= 8080
export PROMPTS_DIR ?= ../prompts
export CLIENT_DIR  ?= ../client
export CERT_DIR    ?= ../.certs

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ── Local build & run ──────────────────────────────────────────────

build: ## Build the server binary
	cd $(SERVER_DIR) && go build -ldflags="$(LDFLAGS)" -o ../$(BINARY) ./cmd/server

run: build ## Build and run the server locally
	./$(BINARY)

clean: ## Remove build artifacts and certs
	rm -f $(BINARY)
	rm -rf .certs/

# ── Code quality ───────────────────────────────────────────────────

fmt: ## Format Go source code
	cd $(SERVER_DIR) && go fmt ./...

vet: ## Run go vet
	cd $(SERVER_DIR) && go vet ./...

lint: fmt vet ## Format and vet (add golangci-lint if installed)
	@which golangci-lint >/dev/null 2>&1 && \
		(cd $(SERVER_DIR) && golangci-lint run ./...) || \
		echo "golangci-lint not installed, skipping"

test: ## Run Go tests
	cd $(SERVER_DIR) && go test -v ./...

tidy: ## Tidy go.mod
	cd $(SERVER_DIR) && go mod tidy

# ── Docker ─────────────────────────────────────────────────────────

docker-build: ## Build Docker image
	docker build -f $(SERVER_DIR)/Dockerfile -t bostrainer .

docker-up: ## Start via docker-compose (foreground)
	docker-compose up --build

docker-up-d: ## Start via docker-compose (detached)
	docker-compose up --build -d

docker-down: ## Stop docker-compose services
	docker-compose down

docker-logs: ## Tail docker-compose logs
	docker-compose logs -f

docker-clean: docker-down ## Stop and remove volumes
	docker-compose down -v
	docker rmi bostrainer 2>/dev/null || true
