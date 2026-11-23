# hoosky — single source of truth for the install and verification commands.
# Docs point here instead of repeating shell invocations; `make help` lists targets.
# There is no build or CI: these are the local gates for contributors and releases.

SHELL := /bin/bash

HOOK         := prepare-commit-msg
INSTALLER    := install.sh
CHECKSUMS    := checksums.txt
HOOK_TEST    := $(HOOK).test.sh
INSTALL_TEST := install.test.sh
VERSION_CHK  := check-version.sh
VERSION_TEST := check-version.test.sh
GENERATOR    := generate-excludes.sh
REGISTRY     := secret-excludes.registry
# shasum -a 256 is the macOS/BSD fallback; both emit "<hash>  <file>".
SHA256       := $(shell if command -v sha256sum >/dev/null 2>&1; then printf sha256sum; else printf 'shasum -a 256'; fi)

.PHONY: help check-syntax check-generated generate-excludes check-version check-version-test check-hook check-install check-checksums test checksums install uninstall

help:  ## list targets
	@printf 'hoosky targets (single source of truth for install/test):\n'
	@printf '  make test                  run every local gate\n'
	@printf '  make generate-excludes     regenerate deny-list copies from secret-excludes.registry\n'
	@printf '  make checksums             regenerate checksums.txt after a hook/installer edit\n'
	@printf '  make install [ARGS]        run install.sh (global by default)\n'
	@printf '  make uninstall [ARGS]      run install.sh --uninstall (e.g. ARGS="--dir PATH")\n'
	@printf '  make help                  this text\n'

check-syntax:  ## bash -n on all shell scripts
	bash -n $(HOOK)
	bash -n $(INSTALLER)
	bash -n $(HOOK_TEST)
	bash -n $(INSTALL_TEST)
	bash -n $(VERSION_CHK)
	bash -n $(VERSION_TEST)
	bash -n $(GENERATOR)

check-generated:  ## generated deny-list blocks match the registry
	bash $(GENERATOR) --check

generate-excludes:  ## regenerate the four deny-list copies from the registry
	bash $(GENERATOR)

check-version:  ## every vX.Y.Z reference matches install.sh TAG
	bash $(VERSION_CHK)

check-version-test:  ## checker suite (scratch git repos; no network)
	bash $(VERSION_TEST)

check-hook:  ## hook suite (stubs curl; no network)
	bash $(HOOK_TEST)

check-install:  ## installer suite (stubs curl; sandboxed HOME/gitconfig)
	bash $(INSTALL_TEST)

check-checksums:  ## published hashes match the working-tree hook and installer
	$(SHA256) $(HOOK) $(INSTALLER) | diff - $(CHECKSUMS)

# Generated blocks and checksums first: a stale block or checksum makes later
# cases fail with confusing "refusing to install"/stale-string symptoms instead
# of telling you to run `make generate-excludes` / `make checksums`.
test: check-syntax check-generated check-version check-version-test check-checksums check-hook check-install  ## run every local gate

checksums:  ## regenerate the published checksums
	$(SHA256) $(HOOK) $(INSTALLER) > $(CHECKSUMS)

install:  ## run the installer; pass ARGS="--dir PATH" etc. for narrower scopes
	bash $(INSTALLER) $(ARGS)

uninstall:  ## run the installer's uninstall path; pass ARGS="--dir PATH" etc.
	bash $(INSTALLER) --uninstall $(ARGS)
