#!/bin/bash
# Build Debian (.deb) package for hlquery

set -e

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

INSTALL_DIR="$1"
VERSION="$2"
RELEASE="$3"
ARCH="$4"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$SCRIPT_DIR"
DIST_DIR="$PACKAGE_DIR/dist"
DEB_DIR="$PACKAGE_DIR/build/deb"

# Package metadata
PACKAGE_NAME="hlquery"
MAINTAINER="${MAINTAINER:-Carlos F. Ferry <carlos.ferry@gmail.com>}"
DESCRIPTION="Search beyond keywords - High-performance search engine with RocksDB storage"
URL="https://www.hlquery.com"

validate_debian_version() {
    local version="$1"
    local release="$2"

    if [[ ! "$version" =~ ^[0-9][A-Za-z0-9.+~_]*$ ]]; then
        echo "Error: invalid Debian package version '$version'." >&2
        echo "Use a version such as '1.0.0' or '1.0.0~rc1'; OS release text with spaces is not valid." >&2
        exit 1
    fi

    if [[ ! "$release" =~ ^[A-Za-z0-9.+~_]+$ ]]; then
        echo "Error: invalid Debian package release '$release'." >&2
        exit 1
    fi
}

trim_value() {
    local value="$1"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

canonicalize_display_version() {
    local raw_version normalized

    raw_version="$(trim_value "$1")"

    if [[ "$raw_version" =~ ^hlquery-([0-9][A-Za-z0-9.+~_-]*)$ ]]; then
        normalized="${BASH_REMATCH[1]}"
        echo "Warning: normalized package artifact version '$raw_version' to '$normalized' by dropping the package name." >&2
        printf '%s' "$normalized"
        return 0
    fi

    if [[ "$raw_version" =~ ^v([0-9][A-Za-z0-9.+~_-]*)$ ]]; then
        normalized="${BASH_REMATCH[1]}"
        echo "Warning: normalized package artifact version '$raw_version' to '$normalized' by dropping the leading v." >&2
        printf '%s' "$normalized"
        return 0
    fi

    printf '%s' "$raw_version"
}

normalize_debian_version() {
    local raw_version normalized

    raw_version="$(trim_value "$1")"

    if [[ "$raw_version" =~ ^([0-9][A-Za-z0-9.+~_-]*)[[:space:]]+ ]]; then
        normalized="${BASH_REMATCH[1]}"
        echo "Warning: normalized Debian package version '$raw_version' to '$normalized'." >&2
        raw_version="$normalized"
    fi

    normalized="${raw_version//-/\~}"
    if [ "$normalized" != "$raw_version" ]; then
        echo "Warning: normalized Debian metadata version '$raw_version' to '$normalized' because Debian package versions cannot contain hyphens." >&2
    fi

    printf '%s' "$normalized"
}

artifact_version() {
    local raw_version

    raw_version="$(trim_value "$1")"
    printf '%s' "${raw_version//~/-}"
}

map_deb_arch() {
    case "$1" in
        x86_64|amd64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        armv7l)
            echo "armhf"
            ;;
        i386|i686)
            echo "i386"
            ;;
        *)
            echo "$1"
            ;;
    esac
}

DISPLAY_VERSION="$(canonicalize_display_version "$VERSION")"
VERSION="$(normalize_debian_version "$DISPLAY_VERSION")"
ARTIFACT_VERSION="$(artifact_version "$DISPLAY_VERSION")"
RELEASE="$(trim_value "$RELEASE")"
validate_debian_version "$VERSION" "$RELEASE"

DEB_ARCH="$(map_deb_arch "$ARCH")"

dpkg_root_owner_group_supported() {
    dpkg-deb --help 2>/dev/null | grep -q -- '--root-owner-group'
}

compute_debian_depends() {
    local shlib_output shlib_deps
    local candidate
    local -a elf_files depends_parts

    if [ -d "$DEB_DIR/usr/bin" ]; then
        while IFS= read -r candidate; do
            if readelf -h "$candidate" >/dev/null 2>&1; then
                elf_files+=("$candidate")
            fi
        done < <(find "$DEB_DIR/usr/bin" -maxdepth 1 -type f -executable)
    fi

    shlib_deps=""
    if command -v dpkg-shlibdeps >/dev/null 2>&1 && [ "${#elf_files[@]}" -gt 0 ]; then
        shlib_output="$(dpkg-shlibdeps -O "${elf_files[@]}" 2>/dev/null || true)"
        shlib_deps="$(printf '%s\n' "$shlib_output" | sed -n 's/^shlibs:Depends=//p' | head -n1)"
    fi

    depends_parts=("perl")
    if [ -n "$shlib_deps" ]; then
        depends_parts+=("$shlib_deps")
    else
        depends_parts+=("libc6 (>= 2.17), libgcc-s1, libstdc++6, libssl3 | libssl1.1, zlib1g")
    fi

    local joined=""
    local part
    for part in "${depends_parts[@]}"; do
        if [ -n "$joined" ]; then
            joined+=", "
        fi
        joined+="$part"
    done

    printf '%s' "$joined"
}

# Create Debian package structure
rm -rf "$DEB_DIR"
mkdir -p "$DEB_DIR/DEBIAN"

# Copy staged install tree produced by make install-system.
if [ ! -d "$INSTALL_DIR" ]; then
    echo "Error: staged install directory not found: $INSTALL_DIR" >&2
    exit 1
fi

cp -a "$INSTALL_DIR"/. "$DEB_DIR"/

mkdir -p "$DEB_DIR/etc/init.d"

# Normalize systemd unit path for Debian packages.
if [ -f "$DEB_DIR/usr/lib/systemd/system/hlquery.service" ]; then
    mkdir -p "$DEB_DIR/lib/systemd/system"
    mv "$DEB_DIR/usr/lib/systemd/system/hlquery.service" "$DEB_DIR/lib/systemd/system/hlquery.service"
    rmdir "$DEB_DIR/usr/lib/systemd/system" 2>/dev/null || true
    rmdir "$DEB_DIR/usr/lib/systemd" 2>/dev/null || true
    rmdir "$DEB_DIR/usr/lib" 2>/dev/null || true
elif [ -f "$PACKAGE_DIR/hlquery.service" ] && [ ! -f "$DEB_DIR/lib/systemd/system/hlquery.service" ]; then
    mkdir -p "$DEB_DIR/lib/systemd/system"
    cp "$PACKAGE_DIR/hlquery.service" "$DEB_DIR/lib/systemd/system/"
fi

# Copy SysV init script for non-systemd environments.
if [ -f "$PACKAGE_DIR/hlquery.init" ]; then
    cp "$PACKAGE_DIR/hlquery.init" "$DEB_DIR/etc/init.d/hlquery"
    chmod 0755 "$DEB_DIR/etc/init.d/hlquery"
fi

DEBIAN_DEPENDS="$(compute_debian_depends)"

# Create control file
cat > "$DEB_DIR/DEBIAN/control" <<EOF
Package: $PACKAGE_NAME
Version: $VERSION-$RELEASE
Section: database
Priority: optional
Architecture: $DEB_ARCH
Maintainer: $MAINTAINER
Description: $DESCRIPTION
 Search beyond keywords. High-performance search engine with RocksDB storage.
 Provides full-text search, hybrid search, and vector similarity search.
Homepage: $URL
Depends: $DEBIAN_DEPENDS
EOF

# Create postinst script
cat > "$DEB_DIR/DEBIAN/postinst" <<'EOF'
#!/bin/bash
set -e

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

# Create user if it doesn't exist
if ! id -u hlquery >/dev/null 2>&1; then
    if command -v useradd >/dev/null 2>&1; then
        useradd -r -s /usr/sbin/nologin -d /var/lib/hlquery hlquery || true
    elif command -v adduser >/dev/null 2>&1; then
        adduser --system --group --home /var/lib/hlquery --no-create-home --disabled-login hlquery || true
    fi
fi

# Ensure runtime directories exist before first start
mkdir -p /var/lib/hlquery /var/log/hlquery /run/hlquery
chown -R hlquery:hlquery /var/lib/hlquery /var/log/hlquery /run/hlquery
chmod 755 /var/lib/hlquery /var/log/hlquery /run/hlquery

# Older packages shipped a development LLM config that points at run/models.
# dpkg preserves conffiles on reinstall, so normalize that unsafe default before
# starting the service. User configs with different model paths are left alone.
if [ -f /etc/hlquery/hlquery.conf ] &&
   grep -A4 '<llm' /etc/hlquery/hlquery.conf | grep -q 'enabled="true"' &&
   grep -q 'models_dir="run/models"' /etc/hlquery/hlquery.conf &&
   grep -q 'model_file="Qwen2.5-14B-Instruct-Q4_K_M.gguf"' /etc/hlquery/hlquery.conf; then
    sed -i '/<llm/,/>/ s/enabled="true"/enabled="false"/' /etc/hlquery/hlquery.conf
fi

if [ -f /etc/hlquery/hlquery.conf ]; then
    sed -i \
        -e 's|target="hlquery.log"|target="/var/log/hlquery/hlquery.log"|g' \
        -e 's|target="database.log"|target="/var/log/hlquery/database.log"|g' \
        -e 's|target="queries.log"|target="/var/log/hlquery/queries.log"|g' \
        -e 's|target="links.log"|target="/var/log/hlquery/links.log"|g' \
        /etc/hlquery/hlquery.conf
fi

# Register and start the service using Debian helpers when available.
warn_service_start_failed() {
    echo "Warning: hlquery service did not start during package installation." >&2
    echo "Inspect with: systemctl status hlquery.service || journalctl -u hlquery.service -n 80 --no-pager" >&2
}

if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ] && [ -f /lib/systemd/system/hlquery.service ]; then
    systemctl daemon-reload
    if command -v deb-systemd-helper >/dev/null 2>&1; then
        deb-systemd-helper unmask hlquery.service >/dev/null || true
        deb-systemd-helper enable hlquery.service >/dev/null || true
    else
        systemctl preset hlquery.service >/dev/null 2>&1 || true
    fi

    if command -v deb-systemd-invoke >/dev/null 2>&1; then
        deb-systemd-invoke start hlquery.service >/dev/null || warn_service_start_failed
    elif command -v invoke-rc.d >/dev/null 2>&1; then
        invoke-rc.d hlquery start >/dev/null 2>&1 || warn_service_start_failed
    else
        systemctl start hlquery.service >/dev/null 2>&1 || warn_service_start_failed
    fi
elif [ -x /etc/init.d/hlquery ]; then
    if command -v update-rc.d >/dev/null 2>&1; then
        update-rc.d hlquery defaults >/dev/null 2>&1 || true
    fi
    if command -v invoke-rc.d >/dev/null 2>&1; then
        invoke-rc.d hlquery start >/dev/null 2>&1 || warn_service_start_failed
    else
        /etc/init.d/hlquery start >/dev/null 2>&1 || warn_service_start_failed
    fi
fi

exit 0
EOF
chmod +x "$DEB_DIR/DEBIAN/postinst"

# Create prerm script
cat > "$DEB_DIR/DEBIAN/prerm" <<'EOF'
#!/bin/bash
set -e

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

# Stop service before removal
if [ "$1" = "remove" ] || [ "$1" = "deconfigure" ] || [ "$1" = "upgrade" ]; then
    if command -v deb-systemd-invoke >/dev/null 2>&1; then
        deb-systemd-invoke stop hlquery.service >/dev/null || true
    elif command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet hlquery.service 2>/dev/null; then
        systemctl stop hlquery.service || true
    elif [ -x /etc/init.d/hlquery ]; then
        /etc/init.d/hlquery stop >/dev/null 2>&1 || true
    fi
fi

exit 0
EOF
chmod +x "$DEB_DIR/DEBIAN/prerm"

# Create postrm script
cat > "$DEB_DIR/DEBIAN/postrm" <<'EOF'
#!/bin/bash
set -e

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

if command -v systemctl >/dev/null 2>&1 && [ -f /lib/systemd/system/hlquery.service ]; then
    systemctl daemon-reload || true
    if [ "$1" = "purge" ] && command -v deb-systemd-helper >/dev/null 2>&1; then
        deb-systemd-helper purge hlquery.service >/dev/null || true
    elif [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
        systemctl disable hlquery.service >/dev/null 2>&1 || true
    fi
fi

if [ "$1" = "purge" ] && [ -x /etc/init.d/hlquery ] && command -v update-rc.d >/dev/null 2>&1; then
    update-rc.d -f hlquery remove >/dev/null 2>&1 || true
fi

exit 0
EOF
chmod +x "$DEB_DIR/DEBIAN/postrm"

# Create conffiles
if [ -d "$DEB_DIR/etc/hlquery" ]; then
    find "$DEB_DIR/etc/hlquery" -type f | sort | sed "s#^$DEB_DIR##" > "$DEB_DIR/DEBIAN/conffiles"
fi

# Build the package
mkdir -p "$DIST_DIR"

DPKG_DEB_ARGS=()
if dpkg_root_owner_group_supported; then
    DPKG_DEB_ARGS+=(--root-owner-group)
fi

DEB_PACKAGE_PATH="$DIST_DIR/${PACKAGE_NAME}_${ARTIFACT_VERSION}_${DEB_ARCH}.deb"
dpkg-deb "${DPKG_DEB_ARGS[@]}" --build "$DEB_DIR" "$DEB_PACKAGE_PATH"

cat > "$DIST_DIR/install-${PACKAGE_NAME}-deb.sh" <<EOF
#!/bin/sh
set -e

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\${PATH:-}"

PACKAGE_PATH="\$(dirname "\$0")/${PACKAGE_NAME}_${ARTIFACT_VERSION}_${DEB_ARCH}.deb"

if [ "\$(id -u)" -ne 0 ]; then
    exec sudo env PATH="\$PATH" dpkg -i "\$PACKAGE_PATH"
fi

exec dpkg -i "\$PACKAGE_PATH"
EOF
chmod 0755 "$DIST_DIR/install-${PACKAGE_NAME}-deb.sh"

echo "Debian package built: $DEB_PACKAGE_PATH"
echo "Install helper built: $DIST_DIR/install-${PACKAGE_NAME}-deb.sh"
