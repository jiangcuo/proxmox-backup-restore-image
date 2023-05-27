include /usr/share/dpkg/pkg-info.mk
include /usr/share/dpkg/architecture.mk

PACKAGE=proxmox-backup-restore-image
PACKAGE_DBG=proxmox-backup-restore-image-debug

BUILDDIR=$(PACKAGE)-$(DEB_VERSION_UPSTREAM_REVISION)
DSC=$(PACKAGE)_$(DEB_VERSION_UPSTREAM).dsc

DEB=$(PACKAGE)_$(DEB_VERSION)_$(DEB_BUILD_ARCH).deb
DEB_DBG=$(PACKAGE_DBG)_$(DEB_VERSION)_$(DEB_BUILD_ARCH).deb
DSC_DBG=$(PACKAGE_DBG)_$(DEB_VERSION).dsc

all: deb

ZFSONLINUX_SUBMODULE=src/submodules/zfsonlinux
KERNEL_SUBMODULE=src/submodules/ubuntu-jammy

submodules.prepared:
	git submodule update --init $(KERNEL_SUBMODULE)
	git submodule update --init --recursive $(ZFSONLINUX_SUBMODULE)
	touch $@

.PHONY: builddir
builddir: $(BUILDDIR)

$(BUILDDIR): submodules.prepared
	rm -rf $@ $@.tmp
	cd src; make clean
	cp -a src $@.tmp
	cp -a debian $@.tmp/
	rm -rf $@.tmp/pkgs
	cd $@.tmp; DOWNLOAD_ONLY="1" ./build_initramfs.sh && mv build/initramfs/pkgs .
	mv $@.tmp $@

.PHONY: deb
deb: $(DEB)
$(DEB): $(BUILDDIR)
	cd $(BUILDDIR); dpkg-buildpackage -b -us -uc
	lintian $(DEB) $(DEB_DBG)
$(DEB_DBG): $(DEB)

.PHONY: dsc
dsc: clean
	$(MAKE) $(DSC)
	lintian $(DSC)

$(DSC): $(BUILDDIR)
	cd $(BUILDDIR); dpkg-buildpackage -S -us -uc -d

sbuild: $(DSC)
	sbuild $<

.PHONY: dinstall
dinstall: deb
	dpkg -i $(DEB) $(DEB_DBG)

.PHONY: upload
upload: $(DEB)
	tar cf - $(DEB) $(DEB_DBG) | ssh -X repoman@repo.proxmox.com upload --product pve --dist bullseye

.PHONY: clean
clean:
	$(MAKE) -C src $@
	rm -rf $(PACKAGE)-[0-9]*/ *.prepared
	rm -f $(PACKAGE)*.tar* *.deb *.dsc *.changes *.build *.buildinfo
