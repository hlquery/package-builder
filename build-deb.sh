#!/bin/bash
# Build Debian (.deb) package for hlquery

set -e

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

DEB_ARCH="$(map_deb_arch "$ARCH")"

# Create Debian package structure
rm -rf "$DEB_DIR"
mkdir -p "$DEB_DIR/DEBIAN"

# Copy staged install tree produced by make install-system.
if [ ! -d "$INSTALL_DIR" ]; then
    echo "Error: staged install directory not found: $INSTALL_DIR" >&2
    exit 1
fi

cp -a "$INSTALL_DIR"/. "$DEB_DIR"/

mkdir -p "$DEB_DIR/lib/systemd/system"

# Copy systemd service file if it exists
if [ -f "$PACKAGE_DIR/hlquery.service" ]; then
    cp "$PACKAGE_DIR/hlquery.service" "$DEB_DIR/lib/systemd/system/"
fi

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
Depends: libc6 (>= 2.17), libssl3 | libssl1.1
EOF

# Create postinst script
cat > "$DEB_DIR/DEBIAN/postinst" <<'EOF'
#!/bin/bash
set -e

# Create user if it doesn't exist
if ! id -u hlquery >/dev/null 2>&1; then
    if command -v adduser >/dev/null 2>&1; then
        adduser --system --group --home /var/lib/hlquery --no-create-home --disabled-login hlquery || true
    else
        useradd -r -s /usr/sbin/nologin -d /var/lib/hlquery hlquery || true
    fi
fi

# Set permissions
chown -R hlquery:hlquery /var/lib/hlquery /var/log/hlquery /run/hlquery 2>/dev/null || true
chmod 755 /var/lib/hlquery /var/log/hlquery /run/hlquery 2>/dev/null || true

# Enable systemd service if it exists
if [ -f /lib/systemd/system/hlquery.service ]; then
    systemctl daemon-reload || true
fi

exit 0
EOF
chmod +x "$DEB_DIR/DEBIAN/postinst"

# Create prerm script
cat > "$DEB_DIR/DEBIAN/prerm" <<'EOF'
#!/bin/bash
set -e

# Stop service before removal
if systemctl is-active --quiet hlquery 2>/dev/null; then
    systemctl stop hlquery || true
fi

exit 0
EOF
chmod +x "$DEB_DIR/DEBIAN/prerm"

# Create postrm script
cat > "$DEB_DIR/DEBIAN/postrm" <<'EOF'
#!/bin/bash
set -e

# Reload systemd if service file exists
if [ -f /lib/systemd/system/hlquery.service ]; then
    systemctl daemon-reload || true
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
dpkg-deb --build "$DEB_DIR" "$DIST_DIR/${PACKAGE_NAME}_${VERSION}-${RELEASE}_${DEB_ARCH}.deb"

echo "Debian package built: $DIST_DIR/${PACKAGE_NAME}_${VERSION}-${RELEASE}_${DEB_ARCH}.deb"
