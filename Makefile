REGISTRY   ?= local
GIT_SHA    ?= $(shell git rev-parse --short=12 HEAD 2>/dev/null || echo dev)
BUILD_DATE ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)

# Narrow any target to some languages/versions (default: everything), e.g.
#   make test ONLY=java            make build ONLY="java:21 go:1.27"
ONLY ?=

export REGISTRY GIT_SHA BUILD_DATE
BAKE := docker buildx bake -f docker-bake.hcl -f pins.hcl

.DEFAULT_GOAL := help
.PHONY: help pins build lint test scan clean

help: ## Show this help
	@awk 'BEGIN{FS=":.*## "} /^[a-zA-Z_-]+:.*## /{printf "  \033[36m%-10s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)
	@echo; echo "  ONLY=<lang>[:<version>]...  narrows build/test/scan, e.g. make test ONLY=java:21"

pins: ## Re-resolve every upstream image in pins.tsv to a digest -> pins.hcl
	scripts/update-pins.sh

build: ## Build base images for the local platform (--load)
	$(BAKE) --load $(shell scripts/targets.sh $(ONLY))

lint: ## hadolint every Dockerfile + shellcheck the scripts (via containers)
	docker run --rm -i -v "$(CURDIR)/.hadolint.yaml:/.hadolint.yaml:ro" hadolint/hadolint hadolint - < images/go/Dockerfile
	docker run --rm -i -v "$(CURDIR)/.hadolint.yaml:/.hadolint.yaml:ro" hadolint/hadolint hadolint - < images/java/Dockerfile
	docker run --rm -i -v "$(CURDIR)/.hadolint.yaml:/.hadolint.yaml:ro" hadolint/hadolint hadolint - < images/python/Dockerfile
	docker run --rm -i -v "$(CURDIR)/.hadolint.yaml:/.hadolint.yaml:ro" hadolint/hadolint hadolint - < images/node/Dockerfile
	docker run --rm -i -v "$(CURDIR)/.hadolint.yaml:/.hadolint.yaml:ro" hadolint/hadolint hadolint - < images/tomcat/Dockerfile
	docker run --rm -v "$(CURDIR):/mnt:ro" -w /mnt koalaman/shellcheck:stable --severity=warning scripts/*.sh

test: build ## Verify version + hardening invariants, then build and run every example
	scripts/verify.sh $(ONLY)
	scripts/smoke-test.sh $(ONLY)

scan: ## Trivy: runtime images must have 0 fixable HIGH/CRITICAL; build images are report-only
	scripts/scan.sh $(ONLY)

clean: ## Remove locally built images
	-docker image ls --format '{{.Repository}}:{{.Tag}}' | grep '^$(REGISTRY)/' | xargs docker rmi
