#!/bin/sh

set -e

ROOT="root"
BUILDDIR="build/initramfs"
INIT="../../init-shim-rs/target/release/init-shim-rs"

echo "Using build dir: $BUILDDIR"
rm -rf "$BUILDDIR"
mkdir -p "$BUILDDIR"
cd "$BUILDDIR"
mkdir "$ROOT"

# adds necessary packages to initramfs build root folder
add_pkgs() {
    DEPS=""
    for pkg in $1; do
        LOCAL_DEPS=$(apt-rdepends -f Depends -s Depends "$pkg" | grep -v '^ ')
        DEPS="$DEPS $LOCAL_DEPS"
    done
    # debconf and gcc are unnecessary
    DEPS=$(echo "$DEPS" |\
        sed -E 's/debconf(-2\.0)?//' |\
        sed -E 's/gcc-.{1,2}-base//')
    apt-get download $DEPS
    for deb in ./*.deb; do
        dpkg-deb -x "$deb" "$ROOT"
    done
    rm ./*.deb
}

make_cpio() {
    fakeroot -- sh -c "
        cd '$ROOT';
        find . -print0 | cpio --null -oV --format=newc -F ../$1
    "
}

cp $INIT "$ROOT/init"
chmod a+x "$ROOT/init" # just to be sure

# tell daemon it's running in the correct environment
touch "$ROOT/restore-vm-marker"

add_pkgs "
    libstdc++6:amd64 \
    libssl1.1:amd64 \
    libacl1:amd64 \
"
rm -rf ${ROOT:?}/usr/share # contains only docs and debian stuff
make_cpio "initramfs.img"

# add debug helpers for debug initramfs, packages from above are included too
add_pkgs "
    util-linux:amd64 \
    busybox-static:amd64 \
    gdb:amd64 \
"
# leave /usr/share here, it contains necessary stuff for gdb
make_cpio "initramfs-debug.img"
