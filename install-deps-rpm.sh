#!/bin/bash

set -e

sudo dnf install -y rpm-build systemd-rpm-macros gcc-c++ make openssl-devel zlib-devel cmake git tar gzip perl 'perl(File::Copy)'
