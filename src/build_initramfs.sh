#!/bin/sh

set -e

ROOT="root"
BUILDDIR="build/initramfs"
INIT="../../init-shim-rs/target/aarch64-unknown-linux-gnu/release/init-shim-rs"

echo "Using build dir: $BUILDDIR"
rm -rf "$BUILDDIR"
mkdir -p "$BUILDDIR"
if [ -d pkgs ]; then
    echo "copying package cache into build-dir"
    cp -a pkgs "$BUILDDIR/pkgs"
    NO_DOWNLOAD="1"
fi
cd "$BUILDDIR"
mkdir "$ROOT"

# adds necessary packages to initramfs build root folder
add_pkgs() {
    debdir=$2

    if [ -z "$NO_DOWNLOAD" ]; then
        DEPS=""
        for pkg in $1; do
            printf " getting reverse dependencies for '%s'" "$pkg"
            LOCAL_DEPS=$(apt-rdepends -f Depends -s Depends "$pkg" | grep -v '^ ')
            DEPS="$DEPS $LOCAL_DEPS"
        done
        # debconf and gcc are unnecessary, libboost-regex doesn't install on bullseye
        DEPS=$(echo "$DEPS" |\
            sed -E 's/debconf(-2\.0)?//g' |\
            sed -E 's/libboost-regex//g' |\
            sed -E 's/gcc-.{1,2}-base//g')

        if [ ! -d "pkgs/$debdir" ]; then
            mkdir -p "pkgs/$debdir"
        fi

        if [ -n "$DEPS" ]; then
            (cd "pkgs/$debdir"; apt-get download $DEPS)
        fi
    fi
    if [ -z "$DOWNLOAD_ONLY" ]; then
        for deb in pkgs/$debdir/*.deb; do
            dpkg-deb -x "$deb" "$ROOT"
        done
    fi
}

make_cpio() {
    echo "creating CPIO archive '$1'"
    fakeroot -- sh -c "
        cd '$ROOT';
        find . -print0 | cpio --null -oV --format=newc -F ../$1
    "
}

if [ -z "$DOWNLOAD_ONLY" ]; then
    echo "copying init"
    install --strip $INIT "$ROOT/init"
    chmod a+x "$ROOT/init" # just to be sure

    # tell daemon it's running in the correct environment
    touch "$ROOT/restore-vm-marker"
fi

echo "getting base dependencies"

add_pkgs "
    busybox:arm64 \
    util-linux:arm64 \
    libstdc++6:arm64 \
    libssl3:arm64 \
    libacl1:arm64 \
    libblkid1:arm64 \
    libuuid1:arm64 \
    libcrypt1:arm64 \
    zlib1g:arm64 \
    libzstd1:arm64 \
    liblz4-1:arm64 \
    liblzma5:arm64 \
    libgcrypt20:arm64 \
    libtirpc3:arm64 \
    lvm2:arm64 \
    thin-provisioning-tools:arm64 \
    gdb:arm64 \
    strace:arm64 \
" 'base'

if [ -z "$DOWNLOAD_ONLY" ]; then

    echo "install ZFS tool"
    # install custom ZFS tools (built without libudev)
    mkdir -p "$ROOT/sbin"
    cp -a ../zfstools/sbin/* "$ROOT/sbin/"
    cp -a ../zfstools/etc/* "$ROOT/etc/"
    cp -a ../zfstools/lib/* "$ROOT/lib/"
    cp -a ../zfstools/usr/* "$ROOT/usr/"

    echo "cleanup unused data from base dependencies"
    rm -rf ${ROOT:?}/usr/share # contains only docs and debian stuff
    rm -rf ${ROOT:?}/usr/local/include # header files
    rm -rf ${ROOT:?}/usr/local/share # mostly ZFS tests
    rm -f ${ROOT:?}/lib/aarch64-linux-gnu/*.a # static libraries
    rm -f ${ROOT:?}/lib/aarch64-linux-gnu/*.la # libtool info files
    strip -s  ${ROOT:?}/sbin/* ||true
    strip -s  ${ROOT:?}/usr/bin/* ||true
    strip -g ${ROOT:?}/lib/aarch64-linux-gnu/*.so.* || true

    make_cpio "initramfs.img"
fi

echo "getting extra/debug dependencies"

cp -a pkgs/base pkgs/debug

# add debug helpers for debug initramfs, packages from above are included too
add_pkgs "
    util-linux:arm64 \
    gdb:arm64 \
    strace:arm64 \
" 'debug'

if [ -z "$DOWNLOAD_ONLY" ]; then
    # leave /usr/share here, it contains necessary stuff for gdb
    make_cpio "initramfs-debug.img"
fi
