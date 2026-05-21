#!/bin/bash
# Package builder script for hlquery
# Builds Debian (.deb) and RPM (.rpm) packages

set -e

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$SCRIPT_DIR"
BUILD_DIR="$PACKAGE_DIR/build"
DIST_DIR="$PACKAGE_DIR/dist"
SOURCE_DIR="$BUILD_DIR/hlquery-src"
VERSION="${VERSION:-1.0.0}"
GIT_VERSION="${GIT_VERSION:-unstable}"
RELEASE="${RELEASE:-1}"
ARCH="${ARCH:-$(uname -m)}"
BUILD_MODE="${BUILD_MODE:-release}"
GIT_REPO="https://github.com/hlquery/hlquery.git"

# Package metadata
PACKAGE_NAME="hlquery"
MAINTAINER="${MAINTAINER:-Carlos F. Ferry <carlos.ferry@gmail.com>}"
DESCRIPTION="Search beyond keywords - High-performance search engine with RocksDB storage"
URL="https://www.hlquery.com"

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

trim_value() {
    local value="$1"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

normalize_package_version() {
    local raw_version normalized

    raw_version="$(trim_value "$1")"

    if [[ "$raw_version" =~ ^v([0-9][A-Za-z0-9.+~_-]*)$ ]]; then
        normalized="${BASH_REMATCH[1]}"
        log_warn "Normalized package version '$raw_version' to '$normalized' by dropping the leading v." >&2
        printf '%s' "$normalized"
        return 0
    fi

    if [[ "$raw_version" =~ ^([0-9][A-Za-z0-9.+~_-]*)[[:space:]]+ ]]; then
        normalized="${BASH_REMATCH[1]}"
        log_warn "Normalized package version '$raw_version' to '$normalized'." >&2
        printf '%s' "$normalized"
        return 0
    fi

    printf '%s' "$raw_version"
}

validate_package_version() {
    local version="$1"

    if [[ "$version" =~ ^[0-9][A-Za-z0-9.+~_]*$ ]]; then
        return 0
    fi

    log_error "Invalid package version '$version'."
    log_error "Use a package version such as '1.0.0' or '1.0.0~rc1'. Do not use OS release text like '24.04.4 LTS (Noble Numbat)'."
    exit 1
}

validate_package_release() {
    local release="$1"

    if [[ "$release" =~ ^[A-Za-z0-9.+~_]+$ ]]; then
        return 0
    fi

    log_error "Invalid package release '$release'."
    log_error "Use a release value such as '1' or '1ubuntu1'; spaces and hyphens are not valid here."
    exit 1
}

require_command() {
    local command_name="$1"
    local package_hint="$2"

    if command -v "$command_name" >/dev/null 2>&1; then
        return 0
    fi

    MISSING_MESSAGES+=("Missing command '$command_name'${package_hint:+ (package: $package_hint)}")
    return 1
}

require_dpkg_package() {
    local package_name="$1"

    if dpkg -s "$package_name" >/dev/null 2>&1; then
        return 0
    fi

    MISSING_MESSAGES+=("Missing Debian package '$package_name'")
    return 1
}

is_rpm_platform() {
    if [ -r /etc/os-release ]; then
        . /etc/os-release
        case " ${ID:-} ${ID_LIKE:-} " in
            *" fedora "*|*" rhel "*|*" centos "*|*" rocky "*|*" almalinux "*|*" suse "*|*" opensuse "*)
                return 0
                ;;
        esac
    fi

    command -v dnf >/dev/null 2>&1 ||
        command -v yum >/dev/null 2>&1 ||
        command -v zypper >/dev/null 2>&1
}

is_debian_platform() {
    if [ -r /etc/os-release ]; then
        . /etc/os-release
        case " ${ID:-} ${ID_LIKE:-} " in
            *" debian "*|*" ubuntu "*)
                return 0
                ;;
        esac
    fi

    command -v apt-get >/dev/null 2>&1
}

check_debian_build_dependencies() {
    MISSING_MESSAGES=()

    require_command git git || true
    require_command make build-essential || true
    require_command g++ build-essential || true
    require_command cmake cmake || true
    require_command dpkg-deb dpkg-dev || true
    require_command fakeroot fakeroot || true

    if is_debian_platform && command -v dpkg >/dev/null 2>&1; then
        require_dpkg_package build-essential || true
        require_dpkg_package zlib1g-dev || true
        require_dpkg_package libssl-dev || true
        require_dpkg_package dpkg-dev || true
        require_dpkg_package fakeroot || true
        require_dpkg_package cmake || true
    fi

    if [ "${#MISSING_MESSAGES[@]}" -eq 0 ]; then
        return 0
    fi

    log_error "Missing Debian build dependencies."
    for message in "${MISSING_MESSAGES[@]}"; do
        log_error "  - $message"
    done
    echo
    log_info "Install them with:"
    echo "  sudo apt-get update"
    echo "  sudo apt-get install build-essential zlib1g-dev libssl-dev dpkg-dev fakeroot cmake git"
    exit 1
}

check_rpm_build_dependencies() {
    MISSING_MESSAGES=()

    require_command git git || true
    require_command make make || true
    require_command g++ gcc-c++ || true
    require_command cmake cmake || true
    require_command rpmbuild rpm-build || true
    require_command tar tar || true
    require_command gzip gzip || true

    if is_rpm_platform && command -v rpm >/dev/null 2>&1; then
        for package_name in gcc-c++ make openssl-devel zlib-devel cmake git rpm-build systemd-rpm-macros tar gzip; do
            if ! rpm -q "$package_name" >/dev/null 2>&1; then
                MISSING_MESSAGES+=("Missing RPM package '$package_name'")
            fi
        done
    elif is_debian_platform && command -v dpkg >/dev/null 2>&1; then
        require_dpkg_package build-essential || true
        require_dpkg_package zlib1g-dev || true
        require_dpkg_package libssl-dev || true
        require_dpkg_package cmake || true
        require_dpkg_package git || true
    fi

    if [ "${#MISSING_MESSAGES[@]}" -eq 0 ]; then
        return 0
    fi

    log_error "Missing RPM build dependencies."
    for message in "${MISSING_MESSAGES[@]}"; do
        log_error "  - $message"
    done
    echo

    if command -v dnf >/dev/null 2>&1; then
        log_info "Install them with:"
        echo "  sudo dnf install rpm-build systemd-rpm-macros gcc-c++ make openssl-devel zlib-devel cmake git tar gzip"
    else
        log_info "Install them with:"
        echo "  sudo apt-get update"
        echo "  sudo apt-get install build-essential zlib1g-dev libssl-dev cmake git rpm"
    fi

    exit 1
}

resolve_remote_default_branch() {
    local default_ref

    default_ref="$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null || true)"
    default_ref="${default_ref#refs/remotes/origin/}"

    if [ -n "$default_ref" ]; then
        echo "$default_ref"
        return 0
    fi

    default_ref="$(git remote show origin 2>/dev/null | sed -n '/HEAD branch/s/.*: //p' | head -n1)"
    if [ -n "$default_ref" ]; then
        echo "$default_ref"
        return 0
    fi

    return 1
}

resolve_checkout_ref() {
    local requested_ref="$1"
    local fallback_ref

    if git rev-parse --verify --quiet "$requested_ref^{commit}" >/dev/null; then
        echo "$requested_ref"
        return 0
    fi

    if git show-ref --verify --quiet "refs/remotes/origin/$requested_ref"; then
        echo "origin/$requested_ref"
        return 0
    fi

    if git show-ref --verify --quiet "refs/tags/$requested_ref"; then
        echo "$requested_ref"
        return 0
    fi

    if [ "$requested_ref" = "unstable" ]; then
        fallback_ref="$(resolve_remote_default_branch || true)"
        if [ -n "$fallback_ref" ] && git show-ref --verify --quiet "refs/remotes/origin/$fallback_ref"; then
            log_warn "Requested ref 'unstable' not found; falling back to remote default branch '$fallback_ref'" >&2
            echo "origin/$fallback_ref"
            return 0
        fi
    fi

    return 1
}

update_source_checkout() {
    local requested_ref="$1"
    local checkout_ref

    git fetch --tags origin "+refs/heads/*:refs/remotes/origin/*"

    checkout_ref="$(resolve_checkout_ref "$requested_ref")" || {
        log_error "Version '$requested_ref' not found locally or on origin."
        log_error "Available remote branches:"
        git branch -r | head -10
        exit 1
    }

    if [[ "$checkout_ref" == origin/* ]]; then
        local branch_name="${checkout_ref#origin/}"
        git checkout -B "$branch_name" "$checkout_ref"
        git branch --set-upstream-to="$checkout_ref" "$branch_name" >/dev/null 2>&1 || true
    else
        git checkout "$checkout_ref"
    fi
}

cleanup() {
    log_info "Cleaning up build directories..."
    rm -rf "$BUILD_DIR" "$DIST_DIR"
    log_info "Cleanup complete"
}

build_and_stage() {
    local layout="$1"
    local stage_dir="$2"
    local staged_config

    log_info "Configuring source tree for '$layout' layout..."
    ./configure --layout="$layout"

    log_info "Building hlquery from source..."
    make BUILD_MODE="$BUILD_MODE" -j"$(nproc)"

    log_info "Staging install tree for '$layout' layout..."
    rm -rf "$stage_dir"
    make install-system DESTDIR="$stage_dir"

    staged_config="$stage_dir/etc/hlquery/hlquery.conf"
    if [ -f "$staged_config" ]; then
        # The source tree may enable local LLMs with repo-local model paths.
        # Distribution packages must start cleanly without bundling GGUF models.
        sed -i '/<llm/,/>/ s/enabled="true"/enabled="false"/' "$staged_config"

        # Keep packaged logs out of /etc when older binaries or preserved
        # config files resolve relative targets against the config directory.
        sed -i \
            -e 's|target="hlquery.log"|target="/var/log/hlquery/hlquery.log"|g' \
            -e 's|target="database.log"|target="/var/log/hlquery/database.log"|g' \
            -e 's|target="queries.log"|target="/var/log/hlquery/queries.log"|g' \
            -e 's|target="sam.log"|target="/var/log/hlquery/sam.log"|g' \
            -e 's|target="links.log"|target="/var/log/hlquery/links.log"|g' \
            "$staged_config"
    fi
}

# Parse arguments
PACKAGE_TYPE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --type)
            PACKAGE_TYPE="$2"
            shift 2
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --git-version)
            GIT_VERSION="$2"
            shift 2
            ;;
        --release)
            RELEASE="$2"
            shift 2
            ;;
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --clean)
            cleanup
            exit 0
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --type TYPE         Package type: deb, rpm, or all (default: auto-detect)"
            echo "  --version VER        Package version (default: 1.0.0)"
            echo "  --git-version VER    Git branch/tag to clone (default: unstable)"
            echo "  --release REL        Package release (default: 1)"
            echo "  --arch ARCH          Architecture (default: auto-detect)"
            echo "  --clean              Clean build directories"
            echo "  --help               Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

VERSION="$(normalize_package_version "$VERSION")"
RELEASE="$(trim_value "$RELEASE")"
validate_package_version "$VERSION"
validate_package_release "$RELEASE"

# Default to the native package type when the platform is clear.
if [ -z "$PACKAGE_TYPE" ]; then
    if is_rpm_platform && ! is_debian_platform; then
        PACKAGE_TYPE="rpm"
    elif is_debian_platform && ! is_rpm_platform; then
        PACKAGE_TYPE="deb"
    else
        PACKAGE_TYPE="all"
    fi
fi

case "$PACKAGE_TYPE" in
    deb|rpm|all)
        ;;
    *)
        log_error "Invalid package type '$PACKAGE_TYPE'. Use 'deb', 'rpm', or 'all'."
        exit 1
        ;;
esac

log_info "Building $PACKAGE_NAME version $VERSION"
log_info "Package type: $PACKAGE_TYPE"
log_info "Architecture: $ARCH"
log_info "Build mode: $BUILD_MODE"
log_info "Git version: $GIT_VERSION"

if [ "$PACKAGE_TYPE" = "all" ] || [ "$PACKAGE_TYPE" = "deb" ]; then
    log_info "Checking Debian package build prerequisites..."
    check_debian_build_dependencies
fi

if [ "$PACKAGE_TYPE" = "all" ] || [ "$PACKAGE_TYPE" = "rpm" ]; then
    log_info "Checking RPM package build prerequisites..."
    check_rpm_build_dependencies
fi

# Create directories
mkdir -p "$BUILD_DIR" "$DIST_DIR"

# Clone source code from GitHub
if [ -d "$SOURCE_DIR" ]; then
    log_info "Source directory exists, updating..."
    cd "$SOURCE_DIR"
    update_source_checkout "$GIT_VERSION"
else
    log_info "Cloning hlquery from GitHub (version: $GIT_VERSION)..."
    # First attempt: Try to clone the specific branch/tag with --depth 1 (shallow clone)
    # Fallback: If that fails (e.g., for commits or non-existent branches), do a full clone and checkout
    # This approach supports both branches/tags and specific commit hashes
    if git clone --branch "$GIT_VERSION" --depth 1 "$GIT_REPO" "$SOURCE_DIR" 2>/dev/null; then
        log_info "Successfully cloned $GIT_VERSION (shallow clone)"
    else
        log_warn "Shallow clone failed for $GIT_VERSION, trying full clone..."
        git clone "$GIT_REPO" "$SOURCE_DIR" || {
            log_error "Failed to clone repository from $GIT_REPO"
            exit 1
        }
        cd "$SOURCE_DIR"
        update_source_checkout "$GIT_VERSION"
        log_info "Successfully checked out $GIT_VERSION"
        cd ..
    fi
fi

cd "$SOURCE_DIR"

# Build packages
if [ "$PACKAGE_TYPE" = "all" ] || [ "$PACKAGE_TYPE" = "deb" ]; then
    log_info "Building Debian package..."
    build_and_stage "debian" "$BUILD_DIR/install-deb"
    "$PACKAGE_DIR/build-deb.sh" "$BUILD_DIR/install-deb" "$VERSION" "$RELEASE" "$ARCH"
fi

if [ "$PACKAGE_TYPE" = "all" ] || [ "$PACKAGE_TYPE" = "rpm" ]; then
    log_info "Building RPM package..."
    build_and_stage "rpm" "$BUILD_DIR/install-rpm"
    "$PACKAGE_DIR/build-rpm.sh" "$BUILD_DIR/install-rpm" "$VERSION" "$RELEASE" "$ARCH"
fi

log_info "Packages built successfully in $DIST_DIR"
ls -lh "$DIST_DIR"
