# =========================
# Config
# =========================
PG_MAJOR        ?= 17
VARIANT         ?= alpine
PLATFORMS       ?= linux/arm64,linux/amd64
VERSION         ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")

# Dev image from postgres-dev-builder project
REGISTRY        ?= ghcr.io/curt
DEV_IMAGE       ?= $(REGISTRY)/postgres-dev:$(PG_MAJOR)-$(VARIANT)

# Where "make install DESTDIR=" stages files
DIST_DIR        ?= dist

# Release artifact name
ARTIFACT_NAME   ?= base58id-$(VERSION)-pg$(PG_MAJOR)-$(VARIANT)

SHELL := bash
.ONESHELL:
.SILENT:

# =========================
# Targets
# =========================

## Compile the extension for specific platforms and stage to ./dist
compile:
	echo "→ Compiling extension with $(DEV_IMAGE) for $(PLATFORMS)"
	rm -rf "$(DIST_DIR)"; mkdir -p "$(DIST_DIR)"
	for platform in $$(echo $(PLATFORMS) | tr ',' ' '); do \
	  arch=$$(echo $$platform | cut -d/ -f2); \
	  echo "→ Building for $$platform..."; \
	  docker run --rm --platform=$$platform --user root \
	    -v "$$(pwd)/extension:/src/extension" \
	    -v "$$(pwd)/$(DIST_DIR)/$$arch:/out" \
	    -e PG_MAJOR=$(PG_MAJOR) \
	    $(DEV_IMAGE) \
	    sh -lc '\
	      set -euo pipefail; \
	      make -C /src/extension clean; \
	      make -C /src/extension; \
	      make -C /src/extension install DESTDIR=/out; \
	      chown -R $$(id -u):$$(id -g) /out 2>/dev/null || true \
	    '; \
	done
	echo "→ Compiled for all platforms"

## Package compiled artifacts into release archives
package: compile
	echo "→ Packaging release artifacts..."
	mkdir -p releases
	for platform in $$(echo $(PLATFORMS) | tr ',' ' '); do \
	  arch=$$(echo $$platform | cut -d/ -f2); \
	  archive="releases/$(ARTIFACT_NAME)-$$arch.tar.gz"; \
	  echo "→ Creating $$archive"; \
	  tar -czf "$$archive" -C "$(DIST_DIR)/$$arch" usr/; \
	done
	echo "→ Release artifacts:"
	ls -lh releases/

## Test compilation using dev container
test:
	echo "→ Testing extension build with $(DEV_IMAGE)"
	docker run --rm \
	  -v "$$(pwd)/extension:/src/extension" \
	  $(DEV_IMAGE) \
	  sh -lc '\
	    set -euo pipefail; \
	    make -C /src/extension clean; \
	    make -C /src/extension; \
	    echo "✓ Build successful" \
	  '

## Convenience: build and package everything
all: package

## Clean staged outputs and release artifacts
clean:
	rm -rf "$(DIST_DIR)" releases/

.PHONY: compile package test all clean
