# Package Builder for hlquery

**Search beyond keywords** - This directory contains scripts and configuration files for building distribution packages (Debian `.deb` and RPM `.rpm`) for hlquery.

## Quick Start

### Building All Package Types

```bash
./build.sh
```

This will build both Debian and RPM packages in the `dist/` directory.

### Building Specific Package Types

```bash
# Build only Debian package
./build.sh --type deb

# Build only RPM package
./build.sh --type rpm
```

### Using Make

```bash
# Build all packages
make

# Build specific package type
make deb
make rpm

# Clean build directories
make clean
```

## Requirements

### For Debian Packages

- `dpkg-deb` (usually included in `dpkg-dev` package)
- `fakeroot` (recommended for proper file ownership)

Install on Debian/Ubuntu:
```bash
sudo apt-get install dpkg-dev fakeroot
```

### For RPM Packages

- `rpmbuild` (usually included in `rpm-build` package)

Install on RedHat/CentOS/Fedora:
```bash
sudo dnf install rpm-build
```

## Usage

### Basic Usage

```bash
# Build with default settings (clones from GitHub unstable branch)
./build.sh

# Build from a specific Git branch or tag
./build.sh --git-version 1.0.0

# Build with custom package version
./build.sh --version 1.0.0 --release 1

# Build for specific architecture
./build.sh --arch x86_64
```

### Advanced Usage

```bash
# Build with all options
./build.sh \
  --type all \
  --version 1.0.0 \
  --git-version v1.0.0 \
  --release 1 \
  --arch x86_64

# Build from a specific branch
./build.sh --git-version develop --version 1.1.0-dev

# Clean build directories
./build.sh --clean
```

### Command-Line Options

- `--type TYPE`: Package type to build (`deb`, `rpm`, or `all`)
- `--version VER`: Package version (default: `1.0.0`)
- `--git-version VER`: Git branch or tag to clone (default: `unstable`)
  - Examples: `unstable`, `1.0.0`, `v1.0.0`, `develop`
- `--release REL`: Package release number (default: `1`)
- `--arch ARCH`: Target architecture (default: auto-detect)
- `--clean`: Clean build directories and exit
- `--help`: Show help message

### Environment Variables

You can also set these via environment variables:

```bash
export VERSION=1.0.0
export GIT_VERSION=unstable
export RELEASE=1
export ARCH=x86_64
export BUILD_MODE=release
./build.sh
```

## Package Structure

### Debian Package (.deb)

The Debian package includes:

- **Binary files**: `/usr/bin/hlquery`, `/usr/bin/hlquery-cli`
- **Configuration**: `/etc/hlquery/`
- **Data directories**: `/var/lib/hlquery`, `/var/log/hlquery`, `/run/hlquery`
- **Systemd service**: `/lib/systemd/system/hlquery.service` (if available)

### RPM Package (.rpm)

The RPM package includes:

- **Binary files**: `/usr/bin/hlquery`, `/usr/bin/hlquery-cli`
- **Configuration**: `/etc/hlquery/`
- **Data directories**: `/var/lib/hlquery`, `/var/log/hlquery`, `/run/hlquery`
- **Systemd service**: `/usr/lib/systemd/system/hlquery.service` (if available)

## Installation

### Installing Debian Package

```bash
# Install package
sudo dpkg -i dist/hlquery_1.0.0-1_amd64.deb

# Fix dependencies if needed
sudo apt-get install -f

# Verify installation
hlquery-cli status
```

### Installing RPM Package

```bash
# Install package
sudo rpm -ivh dist/hlquery-1.0.0-1.x86_64.rpm

# Or use yum/dnf
sudo yum install dist/hlquery-1.0.0-1.x86_64.rpm
sudo dnf install dist/hlquery-1.0.0-1.x86_64.rpm

# Verify installation
hlquery-cli status
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

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Build Packages

on:
  release:
    types: [created]

jobs:
  build-packages:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y dpkg-dev fakeroot rpm-build
      
      - name: Build packages
        run: |
          cd etc/package
          ./build.sh --version ${{ github.event.release.tag_name }} --git-version ${{ github.event.release.tag_name }} --release 1
      
      - name: Upload artifacts
        uses: actions/upload-artifact@v3
        with:
          name: packages
          path: etc/package/dist/*
```

### GitLab CI Example

```yaml
build-packages:
  image: ubuntu:22.04
  before_script:
    - apt-get update
    - apt-get install -y dpkg-dev fakeroot rpm-build build-essential
  script:
    - cd etc/package
    - ./build.sh --version ${CI_COMMIT_TAG} --git-version ${CI_COMMIT_TAG} --release 1
  artifacts:
    paths:
      - etc/package/dist/
    expire_in: 1 week
```

## Troubleshooting

### Build Fails with Permission Errors

Use `fakeroot` for Debian packages:

```bash
fakeroot ./build.sh --type deb
```

### Architecture Mismatch

Specify the correct architecture:

```bash
# For x86_64
./build.sh --arch x86_64

# For ARM64
./build.sh --arch aarch64
```

### Missing Dependencies

Install required build tools:

```bash
# Debian/Ubuntu
sudo apt-get install dpkg-dev fakeroot rpm-build

# RedHat/CentOS/Fedora
sudo dnf install rpm-build dpkg-dev
```

### Package Installation Issues

Check package contents:

```bash
# Debian
dpkg -c dist/hlquery_1.0.0-1_amd64.deb

# RPM
rpm -qlp dist/hlquery-1.0.0-1.x86_64.rpm
```

## Directory Structure

```
etc/package/
├── README.md          # This file
├── Makefile           # Makefile for building packages
├── build.sh           # Main build script
├── build-deb.sh       # Debian package builder
├── build-rpm.sh       # RPM package builder
├── build/             # Temporary build directory (created during build)
└── dist/              # Output directory for built packages
```

## Best Practices

1. **Version Management**: Always use semantic versioning (e.g., `1.0.0`)
2. **Release Numbers**: Increment release number for package rebuilds
3. **Architecture**: Build packages for target architecture
4. **Testing**: Test packages in clean environments before distribution
5. **Signing**: Sign packages for production distribution

## Signing Packages

### Debian Package Signing

```bash
# Generate GPG key (if needed)
gpg --gen-key

# Sign package
debsigs --sign=origin dist/hlquery_1.0.0-1_amd64.deb
```

### RPM Package Signing

```bash
# Generate GPG key (if needed)
gpg --gen-key

# Sign package
rpm --addsign dist/hlquery-1.0.0-1.x86_64.rpm
```

## Additional Resources

- [Debian Packaging Guide](https://www.debian.org/doc/manuals/packaging-tutorial/)
- [RPM Packaging Guide](https://rpm-packaging-guide.github.io/)
- [hlquery Documentation](https://docs.hlquery.com)

## Support

For issues or questions:

- [GitHub Issues](https://github.com/hlquery/hlquery/issues)
- [Documentation](https://docs.hlquery.com)
