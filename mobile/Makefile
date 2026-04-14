.PHONY: apk apk-debug install run bridge bridge-up bridge-down clean help

APP_DIR       := app
SERVER_DIR    := server
APK_DIR       := $(APP_DIR)/build/app/outputs/flutter-apk
LDFLAGS       := -s -w

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ── Flutter app ────────────────────────────────────────────────────

apk: ## Build release APK via Docker
	(cd app && flutter pub get && flutter build apk)
	@echo "\n✅ APK: $(APK_DIR)/app-release.apk"

apk-debug: ## Build debug APK via Docker
	(cd app && flutter pub get && flutter build apk --debug)
	@echo "\n✅ APK: $(APK_DIR)/app-debug.apk"

install: apk-debug ## Build debug APK and install on device via adb
	adb install -r $(APK_DIR)/app-debug.apk

run: install ## Build, install and launch app on device
	adb shell am start -n com.example.bostrainer/.MainActivity

# ── Bridge server ──────────────────────────────────────────────────

bridge: ## Build bridge server binary
	cd $(SERVER_DIR) && go build -ldflags="$(LDFLAGS)" -o ../bostrainer-bridge ./cmd/bridge

bridge-run: bridge ## Build and run bridge server locally
	PROMPTS_DIR=../../prompts ./bostrainer-bridge

bridge-up: ## Start bridge server via docker-compose
	docker compose up --build

bridge-up-d: ## Start bridge server via docker-compose (detached)
	docker compose up --build -d

bridge-down: ## Stop bridge server
	docker compose down

# ── Housekeeping ───────────────────────────────────────────────────

clean: ## Remove build artifacts
	rm -f bostrainer-bridge
	rm -rf $(APP_DIR)/build/
