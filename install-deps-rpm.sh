#!/bin/bash

set -e

sudo dnf install -y rpm-build gcc-c++ make openssl-devel zlib-devel cmake git tar gzip perl 'perl(File::Copy)'
