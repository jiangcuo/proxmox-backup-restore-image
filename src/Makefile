PACKAGE=proxmox-restore-vm-data

BUILDDIR=build
INITRAMFS_BUILDDIR=build/initramfs

ZFSONLINUX_SUBMODULE=submodules/zfsonlinux
KERNEL_SUBMODULE=submodules/ubuntu-kernel
SHIM_DIR=init-shim-rs

KERNEL_IMG=$(BUILDDIR)/bzImage
INITRAMFS_IMG=$(INITRAMFS_BUILDDIR)/initramfs.img
INITRAMFS_IMG_DBG=$(INITRAMFS_BUILDDIR)/initramfs-debug.img

ZFS_TOOLS=$(BUILDDIR)/zfstools

CONFIG=config-base

RUST_SRC=$(wildcard $(SHIM_DIR)/**/*.rs) $(SHIM_DIR)/Cargo.toml

all: $(KERNEL_IMG) $(INITRAMFS_IMG_DBG)

$(BUILDDIR).prepared: $(CONFIG)
	rm -rf $(BUILDDIR)
	mkdir -p $(BUILDDIR)
	cp -a submodules patches $(BUILDDIR)/
	cp $(CONFIG) $(BUILDDIR)/$(KERNEL_SUBMODULE)
	cd $(BUILDDIR)/$(KERNEL_SUBMODULE); \
	    for p in ../../patches/kernel/*.patch; do \
	        echo "applying patch $$p"; patch -Np1 < $$p; \
	    done
	touch $@

kernel.prepared: $(BUILDDIR).prepared
	cd $(BUILDDIR)/$(KERNEL_SUBMODULE); \
	    KCONFIG_ALLCONFIG=$(CONFIG) make allnoconfig && \
	    $(MAKE) prepare scripts
	touch $@

$(BUILDDIR)/$(ZFSONLINUX_SUBMODULE).prepared: $(BUILDDIR).prepared
	cd $(BUILDDIR)/$(ZFSONLINUX_SUBMODULE); \
	    for p in ../../patches/zfs/*.patch; do \
	        patch -Np1 < $$p; \
	    done
	touch $@

zfs.prepared: kernel.prepared $(BUILDDIR)/$(ZFSONLINUX_SUBMODULE).prepared
	cd $(BUILDDIR)/$(ZFSONLINUX_SUBMODULE); \
	    sh autogen.sh && \
	    ./configure \
	        --enable-linux-builtin \
	        --with-linux=../../$(KERNEL_SUBMODULE) \
	        --with-linux-obj=../../$(KERNEL_SUBMODULE) && \
	    ./copy-builtin ../../$(KERNEL_SUBMODULE)
	# only now can we enable CONFIG_ZFS
	cd $(BUILDDIR)/$(KERNEL_SUBMODULE); \
	    ./scripts/config -e CONFIG_ZFS
	touch $@

kernel-img: $(KERNEL_IMG)
$(KERNEL_IMG): zfs.prepared kernel.prepared
	cd $(BUILDDIR)/$(KERNEL_SUBMODULE); $(MAKE)
	mv $(BUILDDIR)/$(KERNEL_SUBMODULE)/arch/x86/boot/bzImage $(KERNEL_IMG)

$(ZFS_TOOLS): zfs.prepared
	cd $(BUILDDIR)/$(ZFSONLINUX_SUBMODULE); \
	    ./configure \
	        --bindir=/usr/bin \
	        --sbindir=/sbin \
	        --libdir=/lib/"$(DEB_HOST_MULTIARCH)" \
	        --with-zfsexecdir=/usr/lib/zfs-linux \
	        --disable-systemd \
	        --disable-pyzfs \
	        --with-config=user
	# absolute path required for 'make install'
	$(MAKE) -C $(BUILDDIR)/$(ZFSONLINUX_SUBMODULE) install DESTDIR=$(PWD)/$(ZFS_TOOLS)

$(INITRAMFS_IMG): $(BUILDDIR).prepared $(RUST_SRC) build_initramfs.sh $(ZFS_TOOLS)
	cd $(SHIM_DIR); cargo build --release
	sh build_initramfs.sh

$(INITRAMFS_IMG_DBG): $(INITRAMFS_IMG)

.PHONY: test-run
test-run: $(KERNEL_IMG) $(INITRAMFS_IMG)
	# note: this will always fail since /proxmox-restore-daemon is not
	# included in the initramfs, but it can be used to test the
	# kernel/init-shim-rs builds
	qemu-system-x86_64 -serial stdio -vnc none -enable-kvm \
	    -kernel $(KERNEL_IMG) \
	    -initrd $(INITRAMFS_IMG)

.PHONY: clean
clean:
	rm -rf *~ $(BUILDDIR) $(INITRAMFS_BUILDDIR) *.prepared

# separate target to avoid that source package build removes this, called by top-level clean target
clean-pkgs:
	rm -rvf pkgs/
