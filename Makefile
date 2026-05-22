# Makefile for hlquery package builder

PACKAGE_NAME = hlquery
PACKAGE_VERSION ?= 1.0.0
RELEASE ?= 1
ARCH ?= $(shell uname -m)
BUILD_MODE ?= release

PACKAGE_DIR = $(shell pwd)
DIST_DIR = $(PACKAGE_DIR)/dist
BUILD_DIR = $(PACKAGE_DIR)/build

.PHONY: all deb rpm clean help

all: deb rpm

deb:
	@echo "Building Debian package..."
	@./build.sh --type deb --version $(PACKAGE_VERSION) --release $(RELEASE) --arch $(ARCH)

rpm:
	@echo "Building RPM package..."
	@./build.sh --type rpm --version $(PACKAGE_VERSION) --release $(RELEASE) --arch $(ARCH)

clean:
	@echo "Cleaning build directories..."
	@rm -rf $(BUILD_DIR) $(DIST_DIR)

help:
	@echo "hlquery Package Builder"
	@echo ""
	@echo "Usage: make [TARGET] [VARIABLE=value]"
	@echo ""
	@echo "Targets:"
	@echo "  all      Build all package types (default)"
	@echo "  deb      Build Debian package (.deb)"
	@echo "  rpm      Build RPM package (.rpm)"
	@echo "  clean    Clean build directories"
	@echo "  help     Show this help message"
	@echo ""
	@echo "Variables:"
	@echo "  PACKAGE_VERSION  Package version (default: 1.0.0)"
	@echo "  RELEASE  Package release (default: 1)"
	@echo "  ARCH     Architecture (default: auto-detect)"
	@echo "  BUILD_MODE Build mode (default: release)"
	@echo ""
	@echo "Examples:"
	@echo "  make PACKAGE_VERSION=1.0.0 RELEASE=1"
	@echo "  make deb PACKAGE_VERSION=1.0.0"
	@echo "  make rpm ARCH=x86_64"
