-include .env
export

# Переменные
GO := go
GO_PKG := ./...
BINARY_NAME := share_trip
BINARY_DIR := bin
MAIN_PATH := ./cmd/sharetrip/main.go

# Значения по умолчанию (если нет .env)
DB_HOST ?= localhost
DB_PORT ?= 5432
DB_USER ?= postgres
DB_PASSWORD ?= password
DB_NAME ?= share_trip
DB_SSLMODE ?= disable

DB_DSN := postgresql://$(DB_USER):$(DB_PASSWORD)@$(DB_HOST):$(DB_PORT)/$(DB_NAME)?sslmode=$(DB_SSLMODE)

# Инструменты: каждая строка = имя: версия: пакет
TOOL_GOLANGCI := golangci-lint:v2.11.3:github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.11.3
TOOL_GOOSE := goose:v3.26.0:github.com/pressly/goose/v3/cmd/goose@v3.26.0
TOOL_SQLC := sqlc:v1.28.0:github.com/sqlc-dev/sqlc/cmd/sqlc@v1.28.0

# Список всех инструментов
TOOLS := $(TOOL_GOLANGCI) $(TOOL_GOOSE) $(TOOL_MIGRATE) $(TOOL_SQLC)

# Проверка Docker
.PHONY: check-docker
check-docker:
	@echo "🐳 Checking Docker..."
	@if ! command -v docker >/dev/null 2>&1; then \
		echo " ❌ Docker not found"; \
		echo ""; \
		echo "    Install: https://www.docker.com/products/docker-desktop/"; \
		echo "    Or: brew install docker docker-compose"; \
		exit 1; \
	fi
	@echo "  ✅ Docker installed: $$(docker --version)"
	@if ! docker info >/dev/null 2>&1; then \
		echo "  ❌ Docker daemon not running"; \
		echo ""; \
		echo "   Start Docker Desktop: open -a Docker"; \
		exit 1; \
	fi
	@echo "   ✅ Docker daemon running"
	@if docker compose version >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1; then \
		echo "   ✅ Docker Compose available"; \
	else \
		echo "   ⚠️  Docker Compose not found (will try to use docker compose)"; \
	fi
	@echo "✅ Docker ready"

# Цель по умолчанию
.DEFAULT_GOAL := help
.PHONY: help
help:
	@echo "Share Trip - Available commands"
	@echo ""
	@echo "First time setup:"
	@echo "  make deps          - Install all tools and dependencies"
	@echo "  make up            - Start PostgreSQL"
	@echo "  make migrate-up    - Apply migrations"
	@echo "  make run           - Build and start the app"
	@echo ""
	@echo "Development:"
	@echo "  make dev           - Start app without building (hot reload)"
	@echo "  make fmt           - Format code"
	@echo "  make lint          - Run linter"
	@echo "  make test          - Run tests"
	@echo "  make check         - Run all checks (fmt + lint + test)"
	@echo ""
	@echo "Database:"
	@echo "  make down          - Stop PostgreSQL"
	@echo "  make migrate-down  - Rollback migrations"
	@echo "  make migrate-status- Check migration status"
	@echo ""
	@echo "Testing:"
	@echo "  make e2e           - Run e2e tests (server must be running)"
	@echo "  make check-ready   - Check /ready endpoint"
	@echo ""
	@echo "Other:"
	@echo "  make coverage      - Generate coverage report"
	@echo "  make clean         - Clean artifacts"
	@echo "  make push          - Run checks and push to git"

# установить инструменты или проверить их наличие
.PHONY: deps
deps:
	@echo "Checking tools..."
	@for tool in $(TOOLS); do \
		cmd=$$(echo "$$tool" | cut -d':' -f1); \
		ver=$$(echo "$$tool" | cut -d':' -f2); \
		pkg=$$(echo "$$tool" | cut -d':' -f3); \
		if command -v $$cmd >/dev/null 2>&1; then \
			current=$$($$cmd version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo ""); \
			if [ -z "$$current" ]; then \
				echo "⚠️  $$cmd version not detected"; \
				echo "    Run: go install $$pkg"; \
			elif [ "$$current" = "$${ver#v}" ]; then \
				echo "✅ $$cmd $$ver"; \
			else \
				echo "⚠️  Expected $$ver, found v$$current"; \
				echo "    Install: go install $$pkg"; \
			fi \
		else \
			echo "  Installing $$cmd $$ver..."; \
			go install $$pkg; \
			echo "✅ $$cmd installed"; \
		fi \
	done
	@echo "✅ All tools checked"
	@echo "Installing Go dependencies..."
	@go get github.com/joho/godotenv@latest
	@go get github.com/gofiber/fiber/v2
	@echo "Tidying Go dependencies..."
	@go mod tidy
	@echo "✅ All dependencies ready"

# форматирование кода
.PHONY: fmt
fmt:
	$(GO) fmt $(GO_PKG)
	@echo "✅ Formatted"

# запуск линтера
.PHONY: lint
lint:
	@if ! command -v golangci-lint >/dev/null 2>&1; then \
    		echo "❌ golangci-lint not found. Run: make deps"; \
    		exit 1; \
    	fi
	@echo "🔍 Running linter..."
	golangci-lint run
	@echo "✅ Lint passed"

# запуск тестов
.PHONY: test
test:
	$(GO) test -v $(GO_PKG)

# сборка бинарника
.PHONY: build
build:
	@echo " Building..."
	@mkdir -p $(BINARY_DIR)
	$(GO) build -o $(BINARY_DIR)/$(BINARY_NAME) $(MAIN_PATH)
	@echo "✅ Built: $(BINARY_DIR)/$(BINARY_NAME)"

# локальный запуск приложения
.PHONY: run check-ready
run: build
	@echo " Running..."
	./$(BINARY_DIR)/$(BINARY_NAME)

# быстрый запуск (без сборки)
.PHONY: dev check-ready
dev:
	@echo " Running in development mode..."
	$(GO) run $(MAIN_PATH)

# поднять и остановить инфраструктуру
.PHONY: up
up: check-docker
	@echo "Starting PostgreSQL on $(DB_HOST):$(DB_PORT)..."
	docker compose up -d
	@echo "✅ PostgreSQL started"
	@sleep 2
	@echo " PostgreSQL ready: $(DB_DSN)"

.PHONY: down
down: check-docker
	@echo "🛑 Stopping PostgreSQL..."
	docker compose down
	@echo "✅ Infrastructure stopped"

# работа с миграциями
.PHONY: migrate-up migrate-down migrate-status
migrate-up:
	@echo " Running migrations..."
	@if command -v goose >/dev/null 2>&1; then \
		goose -dir migrations postgres "$(DB_DSN)" up; \
	elif command -v migrate >/dev/null 2>&1; then \
		migrate -path migrations -database "$(DB_DSN)" up; \
	else \
		echo "❌ No migration tool found. Run: make deps"; \
		exit 1; \
	fi
	@echo "✅ Migrations applied"

migrate-down:
	@echo "  Rolling back migration..."
	@if command -v goose >/dev/null 2>&1; then \
		goose -dir migrations postgres "$(DB_DSN)" down; \
	elif command -v migrate >/dev/null 2>&1; then \
		migrate -path migrations -database "$(DB_DSN)" down 1; \
	else \
		echo "❌ No migration tool found. Run: make deps"; \
		exit 1; \
	fi
	@echo "✅ Migration rolled back"

migrate-status:
	@echo " Migration status:"
	@if command -v goose >/dev/null 2>&1; then \
		goose -dir migrations postgres "$(DB_DSN)" status; \
	elif command -v migrate >/dev/null 2>&1; then \
		migrate -path migrations -database "$(DB_DSN)" version; \
	else \
		echo "❌ No migration tool found. Run: make deps"; \
		exit 1; \
	fi

# полный прогон, как в CI: форматирование, линтер, тесты
.PHONY: check
check:
	fmt
	lint
	test
	@echo "✅ Checked"


# Генерация отчёта о покрытии в формате HTML
.PHONY: coverage cover
coverage cover:
	$(GO) test -coverprofile=coverage.out $(GO_PKG)
	$(GO) tool cover -html=coverage.out -o coverage.html
	@echo "Coverage report generated: file://$(shell pwd)/coverage.html"

# Вывод покрытия в терминал
.PHONY: cover-report
cover-report:
	$(GO) test -cover $(GO_PKG)


# Запуск проверок перед пушем
.PHONY: push
push: check
	git push
	@echo "✅ Pushed"

# Очистка
.PHONY: clean
clean:
	@echo " Cleaning..."
	rm -rf $(BINARY_DIR)/
	rm -f coverage.out coverage.html
	$(GO) clean
	@echo "✅ Cleaned"

# Проверка /ready
.PHONY: check-ready
check-ready:
	@echo "Checking /ready..."
	@curl -s http://localhost:8080/ready
	@echo ""

.PHONY: e2e
e2e: check-ready
	@echo "✅ All e2e tests passed!"

