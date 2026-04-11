CHART_DIR := chart
CI_DIR    := $(CHART_DIR)/ci
RELEASE   := test

.PHONY: help lint test template template-all template-ci dry-run package clean version bump-patch bump-minor bump-major

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

lint: ## Run helm lint
	helm lint $(CHART_DIR)

test: ## Run the full test suite (162 tests)
	bash tests/test_chart.sh

template: ## Render templates with minimal values (image only)
	helm template $(RELEASE) $(CHART_DIR) --set image.repository=nginx --set image.tag=latest

template-all: ## Render templates with full-values.yaml
	helm template $(RELEASE) $(CHART_DIR) -f $(CI_DIR)/full-values.yaml

template-ci: ## Render every CI values file and report pass/fail
	@for f in $(CI_DIR)/*.yaml; do \
		name=$$(basename "$$f"); \
		if helm template $(RELEASE) $(CHART_DIR) -f "$$f" > /dev/null 2>&1; then \
			printf "  \033[32m✓\033[0m %s\n" "$$name"; \
		else \
			printf "  \033[31m✗\033[0m %s\n" "$$name"; \
		fi; \
	done

dry-run: ## kubectl apply --dry-run=server for all non-Gateway CI fixtures
	@for f in $(CI_DIR)/*.yaml; do \
		name=$$(basename "$$f"); \
		case "$$name" in gateway-*) continue;; esac; \
		output=$$(helm template $(RELEASE) $(CHART_DIR) -f "$$f" 2>&1); \
		filtered=$$(echo "$$output" | grep -v "^kind: Cluster$$" | grep -v "^kind: Pooler$$" | grep -v "^kind: ScheduledBackup$$"); \
		if echo "$$output" | kubectl apply --dry-run=server -f - > /dev/null 2>&1; then \
			printf "  \033[32m✓\033[0m %s\n" "$$name"; \
		else \
			printf "  \033[31m✗\033[0m %s (server rejected)\n" "$$name"; \
		fi; \
	done

# ---------------------------------------------------------------------------
# CI (runs everything)
# ---------------------------------------------------------------------------

ci: lint template-ci test ## Run lint + template matrix + test suite

# ---------------------------------------------------------------------------
# Development
# ---------------------------------------------------------------------------

template-db: ## Render CNPG database template
	helm template $(RELEASE) $(CHART_DIR) -f $(CI_DIR)/database-cnpg-values.yaml --show-only templates/database.yaml

template-ingress: ## Render ingress with Authentik
	helm template $(RELEASE) $(CHART_DIR) -f $(CI_DIR)/ingress-values.yaml --show-only templates/ingress.yaml

template-deploy: ## Render deployment with full values
	helm template $(RELEASE) $(CHART_DIR) -f $(CI_DIR)/full-values.yaml --show-only templates/deployment.yaml

schema-validate: ## Validate a values file against the JSON schema (usage: make schema-validate F=myvalues.yaml)
	helm template $(RELEASE) $(CHART_DIR) -f $(F) > /dev/null

debug: ## Render with --debug flag (usage: make debug F=chart/ci/full-values.yaml)
	helm template $(RELEASE) $(CHART_DIR) -f $(F) --debug

# ---------------------------------------------------------------------------
# Packaging
# ---------------------------------------------------------------------------

package: lint ## Package the chart as a .tgz
	helm package $(CHART_DIR)

push: package ## Package and push to GHCR (requires helm registry login)
	@VERSION=$$(grep '^version:' $(CHART_DIR)/Chart.yaml | awk '{print $$2}'); \
	helm push hull-$$VERSION.tgz oci://ghcr.io/kampe

# ---------------------------------------------------------------------------
# Versioning
# ---------------------------------------------------------------------------

version: ## Show current chart version
	@grep '^version:' $(CHART_DIR)/Chart.yaml | awk '{print $$2}'

bump-patch: ## Bump patch version (0.1.0 -> 0.1.1)
	@VERSION=$$(grep '^version:' $(CHART_DIR)/Chart.yaml | awk '{print $$2}'); \
	MAJOR=$$(echo $$VERSION | cut -d. -f1); \
	MINOR=$$(echo $$VERSION | cut -d. -f2); \
	PATCH=$$(echo $$VERSION | cut -d. -f3); \
	NEW="$$MAJOR.$$MINOR.$$((PATCH + 1))"; \
	sed -i '' "s/^version: .*/version: $$NEW/" $(CHART_DIR)/Chart.yaml; \
	echo "$$VERSION -> $$NEW"

bump-minor: ## Bump minor version (0.1.0 -> 0.2.0)
	@VERSION=$$(grep '^version:' $(CHART_DIR)/Chart.yaml | awk '{print $$2}'); \
	MAJOR=$$(echo $$VERSION | cut -d. -f1); \
	MINOR=$$(echo $$VERSION | cut -d. -f2); \
	NEW="$$MAJOR.$$((MINOR + 1)).0"; \
	sed -i '' "s/^version: .*/version: $$NEW/" $(CHART_DIR)/Chart.yaml; \
	echo "$$VERSION -> $$NEW"

bump-major: ## Bump major version (0.1.0 -> 1.0.0)
	@VERSION=$$(grep '^version:' $(CHART_DIR)/Chart.yaml | awk '{print $$2}'); \
	MAJOR=$$(echo $$VERSION | cut -d. -f1); \
	NEW="$$((MAJOR + 1)).0.0"; \
	sed -i '' "s/^version: .*/version: $$NEW/" $(CHART_DIR)/Chart.yaml; \
	echo "$$VERSION -> $$NEW"

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

clean: ## Remove packaged charts
	rm -f hull-*.tgz
