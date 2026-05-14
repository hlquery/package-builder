#!/bin/bash
# Build RPM package for hlquery from a staged install tree

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

PACKAGE_NAME="hlquery"
MAINTAINER="${MAINTAINER:-Carlos F. Ferry <carlos.ferry@gmail.com>}"
DESCRIPTION="Search beyond keywords - High-performance search engine with RocksDB storage"
URL="https://www.hlquery.com"

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

if [ ! -d "$INSTALL_DIR" ]; then
    echo "Error: staged install directory not found: $INSTALL_DIR" >&2
    exit 1
fi

rm -rf "$RPM_DIR"
mkdir -p "$RPMBUILD_DIR"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
mkdir -p "$RPM_DIR/rpmdb"

if [ -f "$PACKAGE_DIR/hlquery.service" ]; then
    cp "$PACKAGE_DIR/hlquery.service" "$RPMBUILD_DIR/SOURCES/"
fi

if [ -f "$PACKAGE_DIR/hlquery.init" ]; then
    cp "$PACKAGE_DIR/hlquery.init" "$RPMBUILD_DIR/SOURCES/"
fi

SPEC_FILE="$RPMBUILD_DIR/SPECS/${PACKAGE_NAME}.spec"
cat > "$SPEC_FILE" <<EOF
%global debug_package %{nil}
%{!?_unitdir:%global _unitdir /usr/lib/systemd/system}
Name:           $PACKAGE_NAME
Version:        $VERSION
Release:        $RELEASE%{?dist}
Summary:        $DESCRIPTION
License:        BSD-3-Clause
URL:            $URL
Source0:        %{name}-%{version}.tar.gz
BuildArch:      $RPM_ARCH

%description
Search beyond keywords. High-performance search engine with RocksDB storage.
Provides full-text search, hybrid search, and vector similarity search.

%prep
%setup -q

%build
:

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
cp -a . %{buildroot}/
if [ -e %{buildroot}%{_bindir}/hlquery-wrapper ]; then
    ln -sfn hlquery-wrapper %{buildroot}%{_bindir}/hlqueryctl
fi
if [ -f %{_sourcedir}/hlquery.service ] && [ ! -f %{buildroot}%{_unitdir}/hlquery.service ]; then
    mkdir -p %{buildroot}%{_unitdir}
    install -m 0644 %{_sourcedir}/hlquery.service %{buildroot}%{_unitdir}/hlquery.service
fi
if [ -f %{_sourcedir}/hlquery.init ]; then
    mkdir -p %{buildroot}/etc/init.d
    install -m 0755 %{_sourcedir}/hlquery.init %{buildroot}/etc/init.d/hlquery
fi

%pre
if ! id -u hlquery >/dev/null 2>&1; then
    useradd -r -s /sbin/nologin -d /var/lib/hlquery hlquery || true
fi

%post
mkdir -p /var/lib/hlquery /var/log/hlquery /run/hlquery
chown -R hlquery:hlquery /var/lib/hlquery /var/log/hlquery /run/hlquery
chmod 755 /var/lib/hlquery /var/log/hlquery /run/hlquery
if [ -f /etc/hlquery/hlquery.conf ] &&
   grep -A4 '<llm' /etc/hlquery/hlquery.conf | grep -q 'enabled="true"' &&
   grep -q 'models_dir="run/models"' /etc/hlquery/hlquery.conf &&
   grep -q 'model_file="Qwen2.5-14B-Instruct-Q4_K_M.gguf"' /etc/hlquery/hlquery.conf; then
    sed -i '/<llm/,/>/ s/enabled="true"/enabled="false"/' /etc/hlquery/hlquery.conf
fi
if [ -f /etc/hlquery/hlquery.conf ] &&
   grep -Eq 'target="(hlquery|database|queries|sam|links)\.log"' /etc/hlquery/hlquery.conf; then
    sed -i \
        -e 's|target="hlquery.log"|target="/var/log/hlquery/hlquery.log"|g' \
        -e 's|target="database.log"|target="/var/log/hlquery/database.log"|g' \
        -e 's|target="queries.log"|target="/var/log/hlquery/queries.log"|g' \
        -e 's|target="sam.log"|target="/var/log/hlquery/sam.log"|g' \
        -e 's|target="links.log"|target="/var/log/hlquery/links.log"|g' \
        /etc/hlquery/hlquery.conf
fi
if command -v systemctl >/dev/null 2>&1 && [ -f %{_unitdir}/hlquery.service ]; then
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl enable hlquery.service >/dev/null 2>&1 || true
    systemctl start hlquery.service >/dev/null 2>&1 || true
elif [ -x /etc/init.d/hlquery ]; then
    if command -v chkconfig >/dev/null 2>&1; then
        chkconfig --add hlquery >/dev/null 2>&1 || true
        chkconfig hlquery on >/dev/null 2>&1 || true
    fi
fi

%preun
if [ "\$1" -eq 0 ]; then
    if command -v systemctl >/dev/null 2>&1 && [ -f %{_unitdir}/hlquery.service ]; then
        systemctl stop hlquery.service >/dev/null 2>&1 || true
        systemctl disable hlquery.service >/dev/null 2>&1 || true
    elif [ -x /etc/init.d/hlquery ]; then
        if command -v chkconfig >/dev/null 2>&1; then
            chkconfig --del hlquery >/dev/null 2>&1 || true
        fi
    fi
fi

%postun
if command -v systemctl >/dev/null 2>&1 && [ -f %{_unitdir}/hlquery.service ]; then
    systemctl daemon-reload >/dev/null 2>&1 || true
    if [ "\$1" -ge 1 ]; then
        systemctl try-restart hlquery.service >/dev/null 2>&1 || true
    fi
fi

%files
%defattr(-,root,root,-)
%{_bindir}/hlquery
%{_bindir}/hlquery-cli
%{_bindir}/hlquery-benchmark
%{_bindir}/hlquery-talk
%{_bindir}/hlquery-wrapper
%{_bindir}/hlqueryctl
%dir %{_sysconfdir}/hlquery
%config(noreplace) %{_sysconfdir}/hlquery/*
%verify(not user group) %dir /var/lib/hlquery
%verify(not user group) %dir /var/log/hlquery
%verify(not user group) %dir /run/hlquery
%dir %{_prefix}/lib/hlquery
%dir %{_prefix}/lib/hlquery/modules
%{_prefix}/lib/hlquery/modules/*
%{_unitdir}/hlquery.service
/etc/init.d/hlquery

%changelog
* $(date '+%a %b %d %Y') $MAINTAINER - $VERSION-$RELEASE
- Initial package release
EOF

mkdir -p "$DIST_DIR"

tar czf "$RPMBUILD_DIR/SOURCES/${PACKAGE_NAME}-${VERSION}.tar.gz" \
    -C "$INSTALL_DIR" \
    --transform "s,^,${PACKAGE_NAME}-${VERSION}/," \
    .

rpmbuild --define "_topdir $RPMBUILD_DIR" \
         --define "_rpmdir $DIST_DIR" \
         --define "_dbpath $RPM_DIR/rpmdb" \
         -ba "$SPEC_FILE"

RPM_FILE=$(find "$DIST_DIR" -name "${PACKAGE_NAME}-${VERSION}-${RELEASE}*.${RPM_ARCH}.rpm" | head -1)
if [ -n "$RPM_FILE" ]; then
    mv "$RPM_FILE" "$DIST_DIR/${PACKAGE_NAME}-${VERSION}-${RELEASE}.${RPM_ARCH}.rpm"
    echo "RPM package built: $DIST_DIR/${PACKAGE_NAME}-${VERSION}-${RELEASE}.${RPM_ARCH}.rpm"
else
    echo "RPM package built in: $DIST_DIR"
    find "$DIST_DIR" -name "*.rpm"
fi
