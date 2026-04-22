#!/bin/bash
# Build RPM package for hlquery

set -e

INSTALL_DIR="$1"
VERSION="$2"
RELEASE="$3"
ARCH="$4"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_DIR="$SCRIPT_DIR"
DIST_DIR="$PACKAGE_DIR/dist"
RPM_DIR="$PACKAGE_DIR/build/rpm"
RPMBUILD_DIR="$RPM_DIR/rpmbuild"

# Package metadata
PACKAGE_NAME="hlquery"
MAINTAINER="${MAINTAINER:-Carlos F. Ferry <carlos.ferry@gmail.com>}"
DESCRIPTION="Search beyond keywords - High-performance search engine with RocksDB storage"
URL="https://www.hlquery.com"

# Map architecture names
case "$ARCH" in
    x86_64)
        RPM_ARCH="x86_64"
        ;;
    aarch64|arm64)
        RPM_ARCH="aarch64"
        ;;
    *)
        RPM_ARCH="$ARCH"
        ;;
esac

# Create RPM build structure
mkdir -p "$RPMBUILD_DIR"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

# Set PACKAGE_DIR for use in spec file
export PACKAGE_DIR="$PACKAGE_DIR"

# Copy systemd service file to SOURCES if it exists
if [ -f "$PACKAGE_DIR/hlquery.service" ]; then
    cp "$PACKAGE_DIR/hlquery.service" "$RPMBUILD_DIR/SOURCES/"
fi

# Create spec file
SPEC_FILE="$RPMBUILD_DIR/SPECS/${PACKAGE_NAME}.spec"
cat > "$SPEC_FILE" <<EOF
Name:           $PACKAGE_NAME
Version:        $VERSION
Release:        $RELEASE%{?dist}
Summary:        $DESCRIPTION
License:        BSD-3-Clause
URL:            $URL
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  gcc-c++
BuildRequires:  make
BuildRequires:  openssl-devel
BuildRequires:  cmake
# Optional: If vendor/rocksdb is not present, system RocksDB will be used
# BuildRequires:  rocksdb-devel snappy-devel lz4-devel zstd-devel bzip2-devel

%description
Search beyond keywords. High-performance search engine with RocksDB storage.
Provides full-text search, hybrid search, and vector similarity search.

%prep
%setup -q

%build
./configure --layout=rpm
make BUILD_MODE=release -j\$(nproc)

%install
rm -rf %{buildroot}
make install-system DESTDIR=%{buildroot}
mkdir -p %{buildroot}/usr/lib/systemd/system

# Copy systemd service file if it exists
if [ -f %{_sourcedir}/hlquery.service ]; then
    cp %{_sourcedir}/hlquery.service %{buildroot}/usr/lib/systemd/system/
fi

%pre
# Create user if it doesn't exist
if ! id -u hlquery >/dev/null 2>&1; then
    useradd -r -s /sbin/nologin -d /var/lib/hlquery hlquery || true
fi

%post
# Set permissions
chown -R hlquery:hlquery /var/lib/hlquery /var/log/hlquery /run/hlquery 2>/dev/null || true
chmod 755 /var/lib/hlquery /var/log/hlquery /run/hlquery 2>/dev/null || true
# Enable systemd service if it exists
if [ -f /usr/lib/systemd/system/hlquery.service ]; then
    systemctl daemon-reload || true
fi

%preun
# Stop service before removal
if systemctl is-active --quiet hlquery 2>/dev/null; then
    systemctl stop hlquery || true
fi

%postun
# Reload systemd if service file exists
if [ -f /usr/lib/systemd/system/hlquery.service ]; then
    systemctl daemon-reload || true
fi

%files
%defattr(-,root,root,-)
/usr/bin/hlquery
/usr/bin/hlquery-cli
%config(noreplace) /etc/hlquery/*
%dir %attr(0755,hlquery,hlquery) /var/lib/hlquery
%dir %attr(0755,hlquery,hlquery) /var/log/hlquery
%dir %attr(0755,hlquery,hlquery) /run/hlquery
%dir /usr/lib/hlquery
%dir /usr/lib/hlquery/modules
%{_prefix}/lib/hlquery/modules/*
%{_unitdir}/hlquery.service

%changelog
* $(date '+%a %b %d %Y') $MAINTAINER - $VERSION-$RELEASE
- Initial package release
EOF

# Copy source files
cd "$(dirname "$SCRIPT_DIR")/.."
tar czf "$RPMBUILD_DIR/SOURCES/${PACKAGE_NAME}-${VERSION}.tar.gz" \
    --exclude='.git' \
    --exclude='build' \
    --exclude='*.o' \
    --exclude='*.a' \
    --exclude='dist' \
    .

# Build RPM
mkdir -p "$DIST_DIR"
rpmbuild --define "_topdir $RPMBUILD_DIR" \
         --define "_rpmdir $DIST_DIR" \
         -ba "$SPEC_FILE"

# Find and report the built RPM
RPM_FILE=$(find "$DIST_DIR" -name "${PACKAGE_NAME}-${VERSION}-${RELEASE}*.${RPM_ARCH}.rpm" | head -1)
if [ -n "$RPM_FILE" ]; then
    # Move to dist directory with consistent naming
    mv "$RPM_FILE" "$DIST_DIR/${PACKAGE_NAME}-${VERSION}-${RELEASE}.${RPM_ARCH}.rpm"
    echo "RPM package built: $DIST_DIR/${PACKAGE_NAME}-${VERSION}-${RELEASE}.${RPM_ARCH}.rpm"
else
    echo "RPM package built in: $DIST_DIR"
    find "$DIST_DIR" -name "*.rpm"
fi
