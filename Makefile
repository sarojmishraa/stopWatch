API := backend/go-services/api
APP := apps/eagle-study-android
COMPOSE := docker compose -f infrastructure/docker/docker-compose.yml

.PHONY: db-up db-down db-psql devauth api test test-api test-app

db-up:        ## Start PostgreSQL 17 (localhost:5434)
	$(COMPOSE) up -d --wait

db-down:
	$(COMPOSE) down

db-psql:
	$(COMPOSE) exec postgres psql -U eagle -d eagle

devauth:      ## Local-only stand-in for Neon Auth on :8787
	cd $(API) && go run ./cmd/devauth

api:          ## Run the API with .env loaded
	set -a; . ./.env; set +a; cd $(API) && go run ./cmd/api

test: test-api test-app

test-api: db-up
	cd $(API) && go vet ./... && go test -race -count=1 -p 1 ./...

test-app:
	cd $(APP) && flutter analyze && flutter test
