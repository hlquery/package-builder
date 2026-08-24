<div align="center">
  <img src="../docs/static/img/hlquery/2.png" alt="hlquery logo" width="200">
</div>

<div align="center">

**Distribution packaging tools for hlquery, built for repeatable Debian and RPM releases.**

[![Follow hlquery](https://img.shields.io/badge/Follow-%40hlquery-blue?logo=x&logoColor=white&labelColor=000000)](https://x.com/hlquery)
[![Debian package](https://img.shields.io/badge/Debian-.deb-a81d33?logo=debian&logoColor=white&labelColor=000000)](https://github.com/hlquery/package-builder/actions/workflows/package-builder.yml)
[![RPM package](https://img.shields.io/badge/RPM-.rpm-d71920?logo=fedora&logoColor=white&labelColor=000000)](https://github.com/hlquery/package-builder/actions/workflows/package-builder.yml)
[![Package Builder](https://img.shields.io/badge/GitHub-package--builder-blue?logo=github&logoColor=white&labelColor=000000)](https://github.com/hlquery/package-builder/)
[![License](https://img.shields.io/badge/License-BSD%203--Clause-a35a0f?logo=open-source-initiative&logoColor=white&labelColor=000000)](https://opensource.org/licenses/BSD-3-Clause)

</div>

### What is the hlquery Package Builder?

**Search beyond keywords** - This directory contains scripts and configuration files for building distribution packages (Debian `.deb` and RPM `.rpm`) for hlquery.

The package builder clones the requested hlquery branch or tag, builds the source tree with the selected package layout, stages an install tree, and produces native packages in `dist/`.

### Why use it?

Use the package builder when you need reproducible installable artifacts for Debian, Ubuntu, Fedora, RHEL-compatible systems, or other RPM-based distributions. It keeps the build, staging, service files, package metadata, and install scripts in one place instead of requiring manual packaging steps.

### Building Native Package Type

```bash
./build.sh
```

By default, `build.sh` auto-detects the current platform and builds the native
package type in the `dist/` directory:

- Debian/Ubuntu systems build a `.deb`
- Fedora/RHEL-compatible systems build an `.rpm`
- Ambiguous or mixed environments build both package types

At the start of each build, the builder removes all existing contents from
`dist/`, so the directory contains only artifacts produced by the current run.

### Building All Package Types

```bash
./build.sh --type all
```

Use `--type all` when you want to build both Debian and RPM packages in the
`dist/` directory.

### Building Specific Package Types

```bash
# Build only Debian package
$ ./build.sh --type deb

# Build only RPM package
$ ./build.sh --type rpm
```

### Using Make

```bash
### Build all packages
$ make

### Build specific package type
$ make deb
$ make rpm

### Clean build directories
$ make clean
```

### Requirements

### For Debian Packages

Install on Debian/Ubuntu:
```bash
$ sudo apt-get update
$ sudo apt-get install build-essential zlib1g-dev libssl-dev liburing-dev dpkg-dev fakeroot cmake git
```

If CMake prints a `uring` lookup warning while building RocksDB, `liburing-dev` is the package that usually fixes it. It installs the development files CMake looks for when optional `io_uring` support is enabled.

Or use the bundled helper:
```bash
$ ./install-deps-debian.sh
```

### For RPM Packages

Install on RedHat/CentOS/Fedora:
```bash
$ sudo dnf install rpm-build gcc-c++ make openssl-devel zlib-devel cmake git tar gzip perl 'perl(File::Copy)'
```

Or use the bundled helper:
```bash
$ ./install-deps-rpm.sh
```

## Usage

### Basic Usage

```bash
# Build with default settings (clones from the stable GitHub 1.0 branch)
$ ./build.sh

# Build from a specific Git branch or tag
$ ./build.sh --git-version 1.0.0

# Build with custom package version
$ ./build.sh --version 1.0.0 --release 1

# Build for specific architecture
$ ./build.sh --arch x86_64
```

The source checkout under `build/hlquery-src` is a disposable build cache.
Before updating or changing the selected Git branch/tag, the builder removes
generated files and local changes from that cached checkout.

### Advanced Usage

```bash
# Build with all options
$ ./build.sh \
  --type all \
  --version 1.0.0 \
  --git-version v1.0.0 \
  --release 1 \
  --arch x86_64

# Build from a specific branch
$ ./build.sh --git-version develop --version 1.1.0~dev

# Clean build directories
$ ./build.sh --clean
```

### Command-Line Options

- `--type TYPE`: Package type to build (`deb`, `rpm`, or `all`; default: auto-detect native package type). Use `--type all` to build both `.deb` and `.rpm` packages.
- `--version VER`: Package version (default: `1.0.0`)
  - Use package-safe values such as `1.0.0` or `1.0.0~rc1`; do not use OS release text such as `24.04.4 LTS (Noble Numbat)`
- `--git-version VER`: Git branch or tag to clone (default: `1.0`)
  - Examples: `1.0`, `v1.0.0`, `unstable`, `develop`
- `--release REL`: Package release number (default: `1`)
- `--arch ARCH`: Target architecture (default: auto-detect)
- `--clean`: Clean build directories and exit
- `--help`: Show help message

### Environment Variables

You can also set these via environment variables:

```bash
$ export VERSION=1.0.0
$ export GIT_VERSION=1.0
$ export RELEASE=1
$ export ARCH=x86_64
$ export BUILD_MODE=release
$ ./build.sh
```

## Package Structure

### Debian Package (.deb)

The Debian package includes:

- **Binary files**: `/usr/bin/hlquery`, `/usr/bin/hlquery-cli`, `/usr/bin/hlquery-wrapper`
- **Configuration**: `/etc/hlquery/`
- **Data directories**: `/var/lib/hlquery`, `/var/log/hlquery`, `/run/hlquery`
- **Systemd service**: `/usr/lib/systemd/system/hlquery.service`
- **SysV compatibility**: `/etc/init.d/hlquery`

### RPM Package (.rpm)

The RPM package includes:

- **Binary files**: `/usr/bin/hlquery`, `/usr/bin/hlquery-cli`, `/usr/bin/hlquery-wrapper`
- **Configuration**: `/etc/hlquery/`
- **Data directories**: `/var/lib/hlquery`, `/var/log/hlquery`, `/run/hlquery`
- **Systemd service**: `/usr/lib/systemd/system/hlquery.service`
- **SysV compatibility**: `/etc/init.d/hlquery`

### Installation

### Installing Debian Package

```bash
# Install package
$ sudo ./dist/install-hlquery-deb.sh

# Verify installation
$ systemctl status hlquery
$ sudo /etc/init.d/hlquery status
$ hlquery-wrapper status
```

The generated install helper sets Debian's standard root paths before invoking `dpkg`, which avoids install failures in minimal shells where `/usr/sbin` or `/sbin` are missing from `PATH`.

### Installing RPM Package

```bash
# Install package
$ sudo rpm -ivh dist/hlquery-1.0.0.x86_64.rpm

# Or use yum/dnf
$ sudo yum install dist/hlquery-1.0.0.x86_64.rpm
$ sudo dnf install dist/hlquery-1.0.0.x86_64.rpm

# Verify installation
$ systemctl status hlquery
$ sudo /etc/init.d/hlquery status
$ hlquery-wrapper status
```

## Build Process

The build process follows these steps:

1. **Clone Source**: Clones hlquery source code from GitHub (https://github.com/hlquery/hlquery)
2. **Source Build**: Configures the source tree for the target packaging layout and compiles hlquery
3. **Installation**: Installs files into a staged filesystem tree using `DESTDIR`
4. **Package Creation**: Creates package structure and metadata
5. **Package Building**: Builds the final package file

The build script automatically clones the specified version from GitHub, so you don't need the source code locally.

### Build Scripts

- `build.sh`: Main build script that orchestrates the build process
- `build-deb.sh`: Builds Debian packages
- `build-rpm.sh`: Builds RPM packages

## Customization

### Modifying Package Metadata

Edit the variables in `build.sh`:

```bash
PACKAGE_NAME="hlquery"
MAINTAINER="Your Name <your.email@example.com>"
DESCRIPTION="Your custom description"
URL="https://your-website.com"
```

### Adding Files to Package

Modify the respective build scripts:

- **Debian**: Edit `build-deb.sh` to add files to `$DEB_DIR`
- **RPM**: Edit `build-rpm.sh` spec file to add files to `%files` section

### Custom Dependencies

Edit the package control files:

- **Debian**: Modify `Depends:` in `build-deb.sh`
- **RPM**: Modify `Requires:` in `build-rpm.sh` spec file

### Missing Dependencies

Install required build tools:

```bash
# Debian/Ubuntu
sudo apt-get install dpkg-dev fakeroot rpm-build liburing-dev

# RedHat/CentOS/Fedora
sudo dnf install rpm-build dpkg-dev
```

### Package Installation Issues

Check package contents:

```bash
# Debian
$ dpkg -c dist/hlquery_1.0.0_amd64.deb

# RPM
$ rpm -qlp dist/hlquery-1.0.0.x86_64.rpm
```

## Support

For issues or questions:

- [GitHub Issues](https://github.com/hlquery/package-builder/issues)
- [Documentation](https://docs.hlquery.com)
