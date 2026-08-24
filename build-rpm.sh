#!/bin/bash
# Build RPM package for hlquery from a staged install tree

if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
fi

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
DESCRIPTION="High-performance full-text and vector search engine"
URL="https://www.hlquery.com"

usage() {
    echo "Usage: $0 INSTALL_DIR VERSION RELEASE ARCH" >&2
    echo "Example: $0 build/install-rpm 1.0.0 1 x86_64" >&2
    echo "Tip: use './build.sh --type rpm' to build and stage hlquery automatically." >&2
}

if [ "$#" -eq 0 ]; then
    exec "$PACKAGE_DIR/build.sh" --type rpm
fi

if [ "$#" -ne 4 ]; then
    usage
    exit 1
fi

validate_rpm_version() {
    local version="$1"
    local release="$2"

    if [[ ! "$version" =~ ^[0-9][A-Za-z0-9.+~_]*$ ]]; then
        echo "Error: invalid RPM package version '$version'." >&2
        echo "Use a version such as '1.0.0' or '1.0.0~rc1'; spaces, hyphens, and OS release text are not valid." >&2
        exit 1
    fi

    if [[ ! "$release" =~ ^[A-Za-z0-9.+~_]+$ ]]; then
        echo "Error: invalid RPM package release '$release'." >&2
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

normalize_rpm_version() {
    local raw_version normalized

    raw_version="$(trim_value "$1")"

    normalized="${raw_version//-/\~}"
    if [ "$normalized" != "$raw_version" ]; then
        echo "Warning: normalized RPM metadata version '$raw_version' to '$normalized' because RPM package versions cannot contain hyphens." >&2
    fi

    printf '%s' "$normalized"
}

artifact_version() {
    local raw_version

    raw_version="$(trim_value "$1")"
    printf '%s' "${raw_version//~/-}"
}

DISPLAY_VERSION="$(canonicalize_display_version "$VERSION")"
VERSION="$(normalize_rpm_version "$DISPLAY_VERSION")"
ARTIFACT_VERSION="$(artifact_version "$DISPLAY_VERSION")"
RELEASE="$(trim_value "$RELEASE")"
validate_rpm_version "$VERSION" "$RELEASE"

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

cat > "$RPMBUILD_DIR/SOURCES/80-hlquery.preset" <<'EOF'
enable hlquery.service
EOF

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
Requires:       perl
Requires(pre):  shadow-utils
Requires(post): systemd
Requires(preun): systemd
Requires(postun): systemd

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
mkdir -p %{buildroot}%{_prefix}/lib/systemd/system-preset
install -m 0644 %{_sourcedir}/80-hlquery.preset %{buildroot}%{_prefix}/lib/systemd/system-preset/80-hlquery.preset
if [ -f %{_sourcedir}/hlquery.init ]; then
    mkdir -p %{buildroot}/etc/init.d
    install -m 0755 %{_sourcedir}/hlquery.init %{buildroot}/etc/init.d/hlquery
fi
rmdir %{buildroot}/run/hlquery 2>/dev/null || true
rmdir %{buildroot}/run 2>/dev/null || true

%pre
if ! getent group hlquery >/dev/null 2>&1; then
    groupadd -r hlquery
fi
if ! id -u hlquery >/dev/null 2>&1; then
    useradd -r -g hlquery -s /sbin/nologin -d /var/lib/hlquery hlquery
elif ! id -nG hlquery | tr ' ' '\n' | grep -qx hlquery; then
    usermod -a -G hlquery hlquery
fi

%post
mkdir -p /var/lib/hlquery /var/log/hlquery /run/hlquery
chown hlquery:hlquery /var/lib/hlquery /var/log/hlquery /run/hlquery
chmod 755 /var/lib/hlquery /var/log/hlquery /run/hlquery
if [ -d /etc/hlquery ]; then
    chown root:hlquery /etc/hlquery
    chmod 750 /etc/hlquery
    find /etc/hlquery -maxdepth 1 -type f -exec chown root:hlquery {} \;
    find /etc/hlquery -maxdepth 1 -type f -exec chmod 640 {} \;
fi
if [ -f /etc/hlquery/hlquery.conf ] &&
   grep -A4 '<llm' /etc/hlquery/hlquery.conf | grep -q 'enabled="true"' &&
   grep -q 'models_dir="run/models"' /etc/hlquery/hlquery.conf &&
   grep -q 'model_file="Qwen2.5-14B-Instruct-Q4_K_M.gguf"' /etc/hlquery/hlquery.conf; then
    sed -i '/<llm/,/>/ s/enabled="true"/enabled="false"/' /etc/hlquery/hlquery.conf
fi
if [ -f /etc/hlquery/hlquery.conf ] &&
   grep -Eq 'target="(hlquery|database|queries|links)\.log"' /etc/hlquery/hlquery.conf; then
    sed -i \
        -e 's|target="hlquery.log"|target="/var/log/hlquery/hlquery.log"|g' \
        -e 's|target="database.log"|target="/var/log/hlquery/database.log"|g' \
        -e 's|target="queries.log"|target="/var/log/hlquery/queries.log"|g' \
        -e 's|target="links.log"|target="/var/log/hlquery/links.log"|g' \
        /etc/hlquery/hlquery.conf
fi
warn_service_start_failed() {
    echo "Warning: hlquery service did not start during package installation." >&2
    echo "Inspect with: systemctl status hlquery.service || journalctl -u hlquery.service -n 80 --no-pager" >&2
}

if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ] && [ -f %{_unitdir}/hlquery.service ]; then
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl preset hlquery.service >/dev/null 2>&1 || true
    systemctl enable hlquery.service >/dev/null 2>&1 || true
    if systemctl start hlquery.service >/dev/null 2>&1; then
        echo "hlquery service started."
    else
        warn_service_start_failed
    fi
fi
if { ! command -v systemctl >/dev/null 2>&1 || [ ! -d /run/systemd/system ]; } && [ -x /etc/init.d/hlquery ]; then
    if command -v chkconfig >/dev/null 2>&1; then
        chkconfig --add hlquery >/dev/null 2>&1 || true
        chkconfig hlquery on >/dev/null 2>&1 || true
    fi
    if /etc/init.d/hlquery start >/dev/null 2>&1; then
        echo "hlquery service started."
    else
        warn_service_start_failed
    fi
fi

%preun
if [ "\$1" -eq 0 ] && command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    systemctl --no-reload disable --now hlquery.service >/dev/null 2>&1 || true
fi
if [ "\$1" -eq 0 ] && { ! command -v systemctl >/dev/null 2>&1 || [ ! -d /run/systemd/system ]; } && [ -x /etc/init.d/hlquery ]; then
    if command -v chkconfig >/dev/null 2>&1; then
        chkconfig --del hlquery >/dev/null 2>&1 || true
    fi
fi

%postun
if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
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
%{_bindir}/hlquery-backup
%{_bindir}/hlquery-wrapper
%{_bindir}/hlqueryctl
%attr(0755,root,root) %dir %{_sysconfdir}/hlquery
%attr(0644,root,root) %config(noreplace) %{_sysconfdir}/hlquery/*
%verify(not user group) %dir /var/lib/hlquery
%verify(not user group) %dir /var/log/hlquery
%dir %{_prefix}/lib/hlquery
%{_prefix}/lib/hlquery/modules
%dir %{_datadir}/hlquery
%{_datadir}/hlquery/benchmark
%{_unitdir}/hlquery.service
%{_prefix}/lib/systemd/system-preset/80-hlquery.preset
/etc/init.d/hlquery

%changelog
* $(LC_ALL=C date '+%a %b %d %Y') $MAINTAINER - $VERSION-$RELEASE
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
    mv "$RPM_FILE" "$DIST_DIR/${PACKAGE_NAME}-${ARTIFACT_VERSION}.${RPM_ARCH}.rpm"
    echo "RPM package built: $DIST_DIR/${PACKAGE_NAME}-${ARTIFACT_VERSION}.${RPM_ARCH}.rpm"
else
    echo "RPM package built in: $DIST_DIR"
    find "$DIST_DIR" -name "*.rpm"
fi
