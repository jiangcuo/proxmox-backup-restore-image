PACKAGE=proxmox-restore-vm-data

BUILDDIR=build
INITRAMFS_BUILDDIR=build/initramfs

ZFSONLINUX_SUBMODULE=submodules/zfsonlinux
KERNEL_SUBMODULE=submodules/ubuntu-hirsute
SHIM_DIR=init-shim-rs

KERNEL_IMG=${BUILDDIR}/bzImage
INITRAMFS_IMG=${INITRAMFS_BUILDDIR}/initramfs.img

CONFIG=config-base

RUST_SRC=$(wildcard ${SHIM_DIR}/**/*.rs) ${SHIM_DIR}/Cargo.toml

all: ${KERNEL_IMG} ${INITRAMFS_IMG}

${BUILDDIR}.prepared: ${CONFIG}
	rm -rf ${BUILDDIR}
	mkdir -p ${BUILDDIR}
	cp -a submodules patches ${BUILDDIR}/
	cp ${CONFIG} ${BUILDDIR}/${KERNEL_SUBMODULE}
	cd ${BUILDDIR}/${KERNEL_SUBMODULE}; \
	    for p in ../../patches/kernel/*.patch; do \
	        patch -Np1 < $$p; \
	    done
	touch $@

kernel.prepared: ${BUILDDIR}.prepared
	cd ${BUILDDIR}/${KERNEL_SUBMODULE}; \
	    KCONFIG_ALLCONFIG=${CONFIG} make allnoconfig && \
	    $(MAKE) prepare scripts
	touch $@

zfs.prepared: kernel.prepared
	cd ${BUILDDIR}/${ZFSONLINUX_SUBMODULE}; \
	    sh autogen.sh && \
	    ./configure \
	        --enable-linux-builtin \
	        --with-linux=../../${KERNEL_SUBMODULE} \
	        --with-linux-obj=../../${KERNEL_SUBMODULE} && \
	    ./copy-builtin ../../${KERNEL_SUBMODULE}
	# only now can we enable CONFIG_ZFS
	cd ${BUILDDIR}/${KERNEL_SUBMODULE}; \
	    ./scripts/config -e CONFIG_ZFS
	touch $@

${KERNEL_IMG}: zfs.prepared
	cd ${BUILDDIR}/${KERNEL_SUBMODULE}; $(MAKE)
	mv ${BUILDDIR}/${KERNEL_SUBMODULE}/arch/x86/boot/bzImage ${KERNEL_IMG}

${INITRAMFS_IMG}: ${BUILDDIR}.prepared ${RUST_SRC} build_initramfs.sh
	cd ${SHIM_DIR}; cargo build --release
	sh build_initramfs.sh

.PHONY: test-run
test-run: ${KERNEL_IMG} ${INITRAMFS_IMG}
	# note: this will always fail since /proxmox-restore-daemon is not
	# included in the initramfs, but it can be used to test the
	# kernel/init-shim-rs builds
	qemu-system-x86_64 -serial stdio -vnc none -enable-kvm \
	    -kernel ${KERNEL_IMG} \
	    -initrd ${INITRAMFS_IMG}

.PHONY: clean
clean:
	rm -rf *~ ${BUILDDIR} ${INITRAMFS_BUILDDIR} *.prepared