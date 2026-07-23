SHELL := /bin/sh
.DEFAULT_GOAL := all
.DELETE_ON_ERROR:

ZSH_VERSION := 5.9.2
ZSH_SHA256 := 36fa734374b44783582cec09bcd67822e2f992c779ec1624ab5596df078d2f81
ZSH_URL := https://www.zsh.org/pub/zsh-$(ZSH_VERSION).tar.xz

ARCH ?= arm64e
IOS_MIN_VERSION ?= 15.0
SDK ?= iphoneos
HOST_TRIPLE ?= arm64e-apple-darwin
JOBS ?= $(shell sysctl -n hw.logicalcpu 2>/dev/null || echo 4)

CRYPTEX_IDENTIFIER ?= codes.rambo.research.zsh
CRYPTEX_ROOT ?= $(CURDIR)/zsh-cryptex.root
SRD_REPOSITORY ?= $(abspath $(CURDIR)/../security-research-device)
PATH_SRDTOOL := $(shell command -v srdtool 2>/dev/null)
SRDTOOL ?= $(if $(PATH_SRDTOOL),$(PATH_SRDTOOL),$(SRD_REPOSITORY)/bin/srdtool)
SRDTOOL_INSTALL_FLAGS ?= --persist

BUILD_ROOT := $(CURDIR)/build
DOWNLOAD_DIR := $(CURDIR)/downloads
ARCHIVE := $(DOWNLOAD_DIR)/zsh-$(ZSH_VERSION).tar.xz
SOURCE_DIR := $(BUILD_ROOT)/source/zsh-$(ZSH_VERSION)
BUILD_DIR := $(BUILD_ROOT)/zsh-$(ZSH_VERSION)-$(ARCH)
COMPAT_INCLUDE_DIR := $(BUILD_ROOT)/compat/include
CONFIG_CACHE := $(BUILD_DIR)/config.cache

SOURCE_STAMP := $(SOURCE_DIR)/.patched
COMPAT_STAMP := $(COMPAT_INCLUDE_DIR)/.prepared
CONFIGURE_STAMP := $(BUILD_DIR)/.configured
BUILD_STAMP := $(BUILD_DIR)/.built
CRYPTEX_STAMP := $(CRYPTEX_ROOT)/.zsh-cryptex

PATCHES := $(sort $(wildcard $(CURDIR)/patches/*.patch))
NCURSES_HEADERS := curses.h ncurses.h ncurses_dll.h term.h unctrl.h
TERMINFO_SOURCE_DIR ?= /usr/share/terminfo
TERMINFO_ENTRIES ?= ansi dumb linux screen screen-256color tmux tmux-256color vt100 xterm xterm-color xterm-256color
REQUIRED_STATIC_MODULES := \
	zsh/zle zsh/complete zsh/complist zsh/computil \
	zsh/termcap zsh/terminfo zsh/curses \
	zsh/regex zsh/zpty zsh/net/socket zsh/net/tcp zsh/system

SDK_PATH = $(shell xcrun --sdk "$(SDK)" --show-sdk-path)
MACOS_SDK_PATH = $(shell xcrun --sdk macosx --show-sdk-path)
IOS_CC = $(shell xcrun --sdk "$(SDK)" --find clang)

TARGET_FLAGS = -isysroot $(SDK_PATH) -arch $(ARCH) -miphoneos-version-min=$(IOS_MIN_VERSION)
TARGET_CFLAGS ?= -O2 $(TARGET_FLAGS)
TARGET_CPPFLAGS ?= -isysroot $(SDK_PATH) -I$(COMPAT_INCLUDE_DIR)
TARGET_LDFLAGS ?= $(TARGET_FLAGS)

.PHONY: all download source configure build cryptex dstroot check install clean distclean help

all: cryptex

download: $(ARCHIVE)

source: $(SOURCE_STAMP)

configure: $(CONFIGURE_STAMP)

build: $(BUILD_STAMP)

cryptex dstroot: $(CRYPTEX_STAMP)

$(ARCHIVE):
	@mkdir -p "$(DOWNLOAD_DIR)"
	@echo "Downloading zsh $(ZSH_VERSION)"
	@curl --fail --location --retry 3 --output "$@.tmp" "$(ZSH_URL)"
	@actual="$$(shasum -a 256 "$@.tmp" | awk '{print $$1}')"; \
	if test "$$actual" != "$(ZSH_SHA256)"; then \
		echo "SHA-256 mismatch for $@.tmp" >&2; \
		echo "expected: $(ZSH_SHA256)" >&2; \
		echo "actual:   $$actual" >&2; \
		rm -f "$@.tmp"; \
		exit 1; \
	fi
	@mv "$@.tmp" "$@"

$(SOURCE_STAMP): $(ARCHIVE) $(PATCHES)
	@echo "Extracting and patching zsh $(ZSH_VERSION)"
	@rm -rf "$(SOURCE_DIR)"
	@mkdir -p "$(SOURCE_DIR)"
	@tar -xf "$(ARCHIVE)" -C "$(SOURCE_DIR)" --strip-components=1
	@for patch_file in $(PATCHES); do \
		echo "Applying $${patch_file##*/}"; \
		patch --batch --forward -d "$(SOURCE_DIR)" -p1 < "$$patch_file" || exit 1; \
	done
	@touch "$@"

$(COMPAT_STAMP):
	@echo "Grafting ncurses headers from the macOS SDK"
	@mkdir -p "$(COMPAT_INCLUDE_DIR)"
	@for header in $(NCURSES_HEADERS); do \
		test -f "$(MACOS_SDK_PATH)/usr/include/$$header" || { \
			echo "Missing macOS SDK header: $$header" >&2; \
			exit 1; \
		}; \
		cp "$(MACOS_SDK_PATH)/usr/include/$$header" "$(COMPAT_INCLUDE_DIR)/$$header"; \
	done
	@touch "$@"

$(CONFIG_CACHE): config.cache.ios | $(BUILD_DIR)
	@cp "$<" "$@"

$(BUILD_DIR):
	@mkdir -p "$@"

$(CONFIGURE_STAMP): $(SOURCE_STAMP) $(COMPAT_STAMP) $(CONFIG_CACHE)
	@echo "Configuring zsh for $(ARCH) iOS"
	@cd "$(BUILD_DIR)" && env \
		CC="$(IOS_CC)" \
		CPP="$(IOS_CC) -E -isysroot $(SDK_PATH) -I$(COMPAT_INCLUDE_DIR)" \
		CFLAGS="$(TARGET_CFLAGS)" \
		CPPFLAGS="$(TARGET_CPPFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS)" \
		"$(SOURCE_DIR)/configure" \
			--build="$$("$(SOURCE_DIR)/config.guess")" \
			--host="$(HOST_TRIPLE)" \
			--prefix=/usr \
			--enable-etcdir=/usr/share/zsh/srd \
			--enable-multibyte \
			--disable-dynamic \
			--with-term-lib=ncurses \
			--cache-file="$(CONFIG_CACHE)"
	@touch "$@"

$(BUILD_STAMP): $(CONFIGURE_STAMP)
	@echo "Building zsh for $(ARCH) iOS"
	@$(MAKE) -C "$(BUILD_DIR)" -j"$(JOBS)"
	@touch "$@"

$(CRYPTEX_STAMP): $(BUILD_STAMP) config/zshenv config/zshrc
	@echo "Creating cryptex root at $(CRYPTEX_ROOT)"
	@rm -rf "$(CRYPTEX_ROOT)"
	@mkdir -p "$(CRYPTEX_ROOT)"
	@$(MAKE) -C "$(BUILD_DIR)" \
		DESTDIR="$(CRYPTEX_ROOT)" \
		install.bin install.fns
	@codesign --force --sign - "$(CRYPTEX_ROOT)/usr/bin/zsh-$(ZSH_VERSION)"
	@rm -f "$(CRYPTEX_ROOT)/usr/bin/zsh"
	@ln "$(CRYPTEX_ROOT)/usr/bin/zsh-$(ZSH_VERSION)" "$(CRYPTEX_ROOT)/usr/bin/zsh"
	@mkdir -p "$(CRYPTEX_ROOT)/usr/share/zsh/srd"
	@install -m 0644 config/zshenv "$(CRYPTEX_ROOT)/usr/share/zsh/srd/zshenv"
	@install -m 0644 config/zshrc "$(CRYPTEX_ROOT)/usr/share/zsh/srd/zshrc"
	@echo "Installing common terminal descriptions"
	@for term in $(TERMINFO_ENTRIES); do \
		entry="$$(find -L "$(TERMINFO_SOURCE_DIR)" -type f -name "$$term" -print -quit)"; \
		if test -z "$$entry"; then \
			echo "Missing host terminfo entry: $$term" >&2; \
			exit 1; \
		fi; \
		relative="$${entry#$(TERMINFO_SOURCE_DIR)/}"; \
		mkdir -p "$(CRYPTEX_ROOT)/usr/share/terminfo/$$(dirname "$$relative")"; \
		install -m 0644 "$$entry" "$(CRYPTEX_ROOT)/usr/share/terminfo/$$relative"; \
	done
	@touch "$@"

check: $(CRYPTEX_STAMP)
	@echo "Verifying cryptex contents"
	@test "$$(lipo -archs "$(CRYPTEX_ROOT)/usr/bin/zsh")" = "$(ARCH)"
	@codesign --verify --strict --verbose=2 "$(CRYPTEX_ROOT)/usr/bin/zsh"
	@otool -L "$(CRYPTEX_ROOT)/usr/bin/zsh"
	@xcrun vtool -show-build "$(CRYPTEX_ROOT)/usr/bin/zsh" | grep -q 'platform IOS'
	@for module in $(REQUIRED_STATIC_MODULES); do \
		grep -F "name=$$module " "$(BUILD_DIR)/config.modules" | \
			grep -q ' link=static ' || { \
				echo "Required static module missing: $$module" >&2; \
				exit 1; \
			}; \
	done
	@test -f "$(CRYPTEX_ROOT)/usr/share/zsh/$(ZSH_VERSION)/functions/compinit"
	@test -f "$(CRYPTEX_ROOT)/usr/share/zsh/srd/zshrc"
	@test -n "$$(find "$(CRYPTEX_ROOT)/usr/share/terminfo" -type f -name xterm-256color -print -quit)"
	@smoke_dir="$$(mktemp -d "$${TMPDIR:-/tmp}/srdzsh-smoke.XXXXXX")"; \
	trap 'rm -rf "$$smoke_dir"' 0 1 2 15; \
	HOME="$$smoke_dir" TERM=xterm-256color /bin/zsh -dfi \
		"$(CURDIR)/tests/smoke.zsh" "$(CURDIR)/config/zshrc" </dev/null
	@/bin/zsh "$(CURDIR)/tests/cryptex-paths.zsh" "$(CURDIR)/config/zshenv"
	@echo "Verified $(ARCH) zsh $(ZSH_VERSION) cryptex root"

install: check
	@command -v "$(SRDTOOL)" >/dev/null 2>&1 || { \
		echo "srdtool not found or not executable: $(SRDTOOL)" >&2; \
		echo "Add srdtool to PATH or set SRDTOOL=/path/to/srdtool." >&2; \
		exit 1; \
	}
	@"$(SRDTOOL)" cryptex install $(SRDTOOL_INSTALL_FLAGS) \
		--identifier "$(CRYPTEX_IDENTIFIER)" \
		$(if $(ECID),--ecid "$(ECID)",) \
		"$(CRYPTEX_ROOT)"

clean:
	@rm -rf "$(BUILD_ROOT)" "$(CRYPTEX_ROOT)"

distclean: clean
	@rm -rf "$(DOWNLOAD_DIR)"

help:
	@echo "Targets:"
	@echo "  all / cryptex  Download, patch, build, and create the cryptex root"
	@echo "  check          Validate architecture, signature, modules, and resources"
	@echo "  install        Install the cryptex with srdtool"
	@echo "  clean          Remove build products and the cryptex root"
	@echo "  distclean      Also remove downloaded source archives"
	@echo ""
	@echo "Useful overrides:"
	@echo "  IOS_MIN_VERSION=$(IOS_MIN_VERSION)  ARCH=$(ARCH)"
	@echo "  CRYPTEX_IDENTIFIER=$(CRYPTEX_IDENTIFIER)"
	@echo "  SRDTOOL=$(SRDTOOL)"
	@echo "  ECID=<device-ecid>"
