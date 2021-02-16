include /usr/share/dpkg/pkg-info.mk
include /usr/share/dpkg/architecture.mk

PACKAGE=proxmox-restore-vm-data

BUILDDIR=build
INITRAMFS_BUILDDIR=build/initramfs

ZFSONLINUX_SUBMODULE=submodules/zfsonlinux
KERNEL_SUBMODULE=submodules/ubuntu-hirsute
SHIM_DIR=init-shim-rs

KERNEL_IMG=${BUILDDIR}/${KERNEL_SUBMODULE}/arch/x86/boot/bzImage
INITRAMFS_IMG=${INITRAMFS_BUILDDIR}/initramfs.img

CONFIG=config-base

RUST_SRC=$(wildcard ${SHIM_DIR}/**/*.rs) ${SHIM_DIR}/Cargo.toml

DEB=${PACKAGE}_${DEB_VERSION_UPSTREAM_REVISION}_${DEB_BUILD_ARCH}.deb
DSC=${PACKAGE}_${DEB_VERSION_UPSTREAM_REVISION}.dsc

all: deb

submodules.prepared:
	git submodule update --init ${KERNEL_SUBMODULE}
	git submodule update --init --recursive ${ZFSONLINUX_SUBMODULE}
	touch $@

${BUILDDIR}.prepared: submodules.prepared ${CONFIG}
	rm -rf ${BUILDDIR}
	mkdir -p ${BUILDDIR}
	cp -a submodules debian patches ${BUILDDIR}/
	cp ${CONFIG} ${BUILDDIR}/${KERNEL_SUBMODULE}
	cd ${BUILDDIR}/${KERNEL_SUBMODULE}; \
		for p in ../../patches/kernel/*.patch; do \
			patch -Np1 < $$p; \
		done
	touch $@

kernel.prepared: ${BUILDDIR}.prepared
	cd ${BUILDDIR}/${KERNEL_SUBMODULE}; \
		KCONFIG_ALLCONFIG=${CONFIG} make allnoconfig && \
		make -j$(nproc) prepare scripts
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
	cd ${BUILDDIR}/${KERNEL_SUBMODULE}; \
	    make -j$(nproc)
	mv ${BUILDDIR}/${KERNEL_SUBMODULE}/arch/x86/boot/bzImage ${BUILDDIR}/

${INITRAMFS_IMG}: ${BUILDDIR}.prepared ${RUST_SRC} build_initramfs.sh
	cd ${SHIM_DIR}; cargo build --release
	sh build_initramfs.sh

.PHONY: dinstall
dinstall: deb
	dpkg -i ${DEB}

.PHONY: deb
deb: ${DEB}
${DEB}: ${KERNEL_IMG} ${INITRAMFS_IMG}
	cd ${BUILDDIR}; dpkg-buildpackage -b -us -uc
	lintian ${DEB}

.PHONY: dsc
dsc: ${DSC}
${DSC}: ${KERNEL_IMG} ${INITRAMFS_IMG}
	cd ${BUILDDIR}; dpkg-buildpackage -S -us -uc -d
	lintian ${DSC}

.PHONY: upload
upload: ${DEB}
	tar cf - ${DEB} | ssh -X repoman@repo.proxmox.com upload --product pbs --dist buster
	tar cf - ${DEB} | ssh -X repoman@repo.proxmox.com upload --product pve --dist buster

.PHONY: test-run
test-run: ${KERNEL_IMG} ${INITRAMFS_IMG}
	# note: this will always fail since /proxmox-restore-daemon is not
	# included in the initramfs, but it can be used to test the
	# kernel/init-shim-rs builds
	qemu-system-x86_64 -serial stdio -vnc none -enable-kvm \
		-kernel build/${KERNEL_SUBMODULE}/arch/x86/boot/bzImage \
		-initrd build/initramfs/initramfs.img

.PHONY: clean
clean:
	rm -rf *~ ${BUILDDIR} ${INITRAMFS_BUILDDIR} *.prepared
	rm -f ${PACKAGE}_${DEB_VERSION_UPSTREAM_REVISION}.tar.gz
	rm -f *.deb *.changes *.buildinfo *.dsc
