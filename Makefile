# Self-documenting Makefile: run `make` or `make help` to list the targets.
#
# Commands run inside Docker by default, as the team does. To run them on the host
# (or in CI), empty the wrapper, e.g. `make lint RUN=` or `make test RUN_TEST=`.

.DEFAULT_GOAL := help

COMPOSE ?= docker compose
RUN ?= $(COMPOSE) run --rm --no-deps app

# The specs need their own database. The DATABASE_URL in .env points to the
# development one, and in the test env the URL wins over config/database.yml, so the
# test run swaps the database name instead of reusing the URL as is.
TEST_DATABASE_URL ?= $(shell sed -n 's|^DATABASE_URL=\(.*\)/[^/]*$$|\1/bbb_app_rooms_test|p' .env)
RUN_TEST ?= $(COMPOSE) run --rm -e APP_THEME=elos -e DATABASE_URL=$(TEST_DATABASE_URL) test

THEME ?= elos
IMAGE ?= bbb-app-rooms:local

.PHONY: help
help: ## Show this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

.PHONY: install
install: ## Build the dev and test images and install the JavaScript packages
	$(COMPOSE) build app test
	$(RUN) yarn install --frozen-lockfile

.PHONY: run
run: ## Run the app with Postgres and Redis (port 3001)
	$(COMPOSE) up app

.PHONY: lint
lint: ## Run RuboCop (lint cops, as in CI) and Brakeman
	$(RUN) bundle exec rubocop -l --config .rubocop.yml
	$(RUN) bundle exec brakeman -q --no-pager

.PHONY: format
format: ## Auto-correct RuboCop offenses (safe corrections only)
	$(RUN) bundle exec rubocop -a --config .rubocop.yml

.PHONY: test
test: ## Prepare the test database and run the specs
	$(RUN_TEST) sh -c "bin/rails db:test:prepare && bundle exec rspec"

.PHONY: build
build: ## Build the production image (THEME=elos|rnp)
	docker build --build-arg APP_THEME=$(THEME) -t $(IMAGE) .
