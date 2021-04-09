#!/bin/sh

set -e

ROOT="root"
BUILDDIR="build/initramfs"
INIT="../../init-shim-rs/target/release/init-shim-rs"

PKGS=" \
    libc6:amd64 \
    libgcc1:amd64 \
    libstdc++6:amd64 \
    libssl1.1:amd64 \
    libattr1:amd64 \
    libacl1:amd64
"

echo "Using build dir: $BUILDDIR"
rm -rf "$BUILDDIR"
mkdir -p "$BUILDDIR"
cd "$BUILDDIR"
mkdir "$ROOT"

# add necessary packages to initramfs
for pkg in $PKGS; do
    apt-get download "$pkg"
    dpkg-deb -x ./*.deb "$ROOT"
    rm ./*.deb
done

rm -rf ${ROOT:?}/usr/share # contains only docs and debian stuff

cp $INIT "$ROOT/init"
chmod a+x "$ROOT/init" # just to be sure

# tell daemon it's running in the correct environment
touch "$ROOT/restore-vm-marker"

fakeroot -- sh -c "
    cd '$ROOT';
    find . -print0 | cpio --null -oV --format=newc -F ../initramfs.img
"
