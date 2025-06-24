#!/bin/sh

set -e

ROOT="root"
BUILDDIR="build/initramfs"
INIT="../../init-shim-rs/target/x86_64-unknown-linux-gnu/release/init-shim-rs"

echo "Using build dir: $BUILDDIR"
rm -rf "$BUILDDIR"
mkdir -p "$BUILDDIR"
if [ -d pkgs ]; then
    echo "copying package cache into build-dir"
    cp -a pkgs "$BUILDDIR/pkgs"
    NO_DOWNLOAD="1"
fi
cd "$BUILDDIR"
mkdir -p "$ROOT/usr"

for dir in "bin" "sbin" "lib" "lib32" "lib64" ; do
    mkdir "$ROOT/usr/$dir"
    ln -sr "$ROOT/usr/$dir" "$ROOT/$dir"
done

# adds necessary packages to initramfs build root folder
add_pkgs() {
    debdir=$2

    if [ -z "$NO_DOWNLOAD" ]; then
        DEPS=""
        for pkg in $1; do
            printf " getting reverse dependencies for '%s'\n" "$pkg"
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
            dpkg-deb --fsys-tarfile "$deb" |tar -C "$ROOT" --keep-directory-symlink -x
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
    busybox:amd64 \
    libstdc++6:amd64 \
    libssl3t64:amd64 \
    libacl1:amd64 \
    libblkid1:amd64 \
    libuuid1:amd64 \
    zlib1g:amd64 \
    libzstd1:amd64 \
    liblz4-1:amd64 \
    liblzma5:amd64 \
    libgcrypt20:amd64 \
    libtirpc3t64:amd64 \
    lvm2:amd64 \
    thin-provisioning-tools:amd64 \
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
    rm -rf ${ROOT:?}/usr/lib/zfs-linux # zpool.d/zed.d snippets, zpool_influxdb
    rm -f ${ROOT:?}/lib/x86_64-linux-gnu/*.a # static libraries
    rm -f ${ROOT:?}/lib/x86_64-linux-gnu/*.la # libtool info files
    strip -s  ${ROOT:?}/sbin/* ||true
    strip -s  ${ROOT:?}/usr/bin/* ||true
    strip -g ${ROOT:?}/lib/x86_64-linux-gnu/*.so.* || true

    make_cpio "initramfs.img"
fi

echo "getting extra/debug dependencies"

cp -a pkgs/base pkgs/debug

# add debug helpers for debug initramfs, packages from above are included too
add_pkgs "
    util-linux:amd64 \
    gdb:amd64 \
    strace:amd64 \
" 'debug'

if [ -z "$DOWNLOAD_ONLY" ]; then
    # leave /usr/share here, it contains necessary stuff for gdb
    make_cpio "initramfs-debug.img"
fi
