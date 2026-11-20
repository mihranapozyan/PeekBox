#!/bin/zsh
# Builds the 7-Zip console helper (7zz) from the official source and puts it in Vendor/7zip/7zz.
# PeekBox runs it for archives libarchive can't handle (encrypted RAR/7z, Zstandard).
set -euo pipefail
cd "${0:A:h:h}"
VERSION=26.06
TAG=${VERSION//./}
SHA256=a4e374c8f864f51df48c2cfd0e1413ec3b2ea030deae852d6a655402ebb61ac4
WORK=build/7zip-$VERSION
mkdir -p "$WORK" Vendor/7zip
if [[ ! -f "$WORK/src.tar.xz" ]]; then
  curl -fsSL -o "$WORK/src.tar.xz" "https://github.com/ip7z/7zip/releases/download/$VERSION/7z$TAG-src.tar.xz"
fi
print "$SHA256  $WORK/src.tar.xz" | shasum -a 256 -c --quiet
rm -rf "$WORK/src" && mkdir "$WORK/src"
tar -xJf "$WORK/src.tar.xz" -C "$WORK/src"
# Apple Silicon only, like the app. The stock makefile targets macOS 11; build for the app's 14.0 instead.
make -C "$WORK/src/CPP/7zip/Bundles/Alone2" -f ../../cmpl_mac_arm64.mak -j"$(sysctl -n hw.ncpu)" \
  MY_ARCH="-arch arm64 -mmacosx-version-min=14.0" >/dev/null
cp "$WORK/src/CPP/7zip/Bundles/Alone2/b/m_arm64/7zz" Vendor/7zip/7zz
cp "$WORK/src/DOC/License.txt" Vendor/7zip/License.txt
print "Built 7-Zip $VERSION → Vendor/7zip/7zz"
