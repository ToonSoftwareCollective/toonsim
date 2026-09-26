#!/bin/sh
# Builds bin/toonsim on Linux with the system's Qt 5.15 (tools/build.bat is the Windows build).
# Debian/Ubuntu: the packages are in docs/MANUAL.md ("Linux").
set -e
cd "$(dirname "$0")/../src"
mkdir -p build-linux
cd build-linux
qmake ../toonsim.pro CONFIG+=release
make -j"$(nproc)"
echo "built $(cd ../../bin && pwd)/toonsim"
