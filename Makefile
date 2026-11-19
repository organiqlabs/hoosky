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
# shasum -a 256 is the macOS/BSD fallback; both emit "<hash>  <file>".
SHA256       := $(shell if command -v sha256sum >/dev/null 2>&1; then printf sha256sum; else printf 'shasum -a 256'; fi)

.PHONY: help check-syntax check-version check-version-test check-hook check-install check-checksums test checksums install uninstall

help:  ## list targets
	@printf 'hoosky targets (single source of truth for install/test):\n'
	@printf '  make test                  run every local gate\n'
	@printf '  make checksums             regenerate checksums.txt after a hook/installer edit\n'
	@printf '  make install [ARGS="..."] run install.sh (global by default)\n'
	@printf '  make uninstall             run install.sh --uninstall\n'
	@printf '  make help                  this text\n'

check-syntax:  ## bash -n on all shell scripts
	bash -n $(HOOK)
	bash -n $(INSTALLER)
	bash -n $(VERSION_CHK)
	bash -n $(VERSION_TEST)

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

# Checksums first: a stale checksums.txt makes every installer case fail with a
# confusing "refusing to install" instead of telling you to regenerate it.
test: check-syntax check-version check-version-test check-checksums check-hook check-install  ## run every local gate

checksums:  ## regenerate the published checksums
	$(SHA256) $(HOOK) $(INSTALLER) > $(CHECKSUMS)

install:  ## run the installer; pass ARGS="--dir PATH" etc. for narrower scopes
	bash $(INSTALLER) $(ARGS)

uninstall:  ## run the installer's uninstall path
	bash $(INSTALLER) --uninstall $(ARGS)
