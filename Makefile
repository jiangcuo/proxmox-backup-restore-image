include /usr/share/dpkg/pkg-info.mk
include /usr/share/dpkg/architecture.mk

PACKAGE=proxmox-backup-restore-image
PACKAGE_DBG=proxmox-backup-restore-image-debug

BUILDDIR=${PACKAGE}-${DEB_VERSION_UPSTREAM_REVISION}

DEB=${PACKAGE}_${DEB_VERSION}_${DEB_BUILD_ARCH}.deb
DSC=${PACKAGE}_${DEB_VERSION}.dsc
DEB_DBG=${PACKAGE_DBG}_${DEB_VERSION}_${DEB_BUILD_ARCH}.deb
DSC_DBG=${PACKAGE_DBG}_${DEB_VERSION}.dsc

all: deb

ZFSONLINUX_SUBMODULE=src/submodules/zfsonlinux
KERNEL_SUBMODULE=src/submodules/ubuntu-hirsute

submodules.prepared:
	git submodule update --init ${KERNEL_SUBMODULE}
	git submodule update --init --recursive ${ZFSONLINUX_SUBMODULE}
	touch $@

.PHONY: builddir
builddir: ${BUILDDIR}

${BUILDDIR}: submodules.prepared
	rm -rf ${BUILDDIR} ${BUILDDIR}.tmp
	cd src; make clean
	cp -a src ${BUILDDIR}.tmp
	cp -a debian ${BUILDDIR}.tmp/
	mv ${BUILDDIR}.tmp ${BUILDDIR}

.PHONY: deb
deb: ${DEB}
${DEB}: ${BUILDDIR}
	cd ${BUILDDIR}; dpkg-buildpackage -b -us -uc
	lintian ${DEB} ${DEB_DBG}
${DEB_DBG}: ${DEB}

.PHONY: dsc
dsc: ${DSC}
${DSC}: ${BUILDDIR}
	cd ${BUILDDIR}; dpkg-buildpackage -S -us -uc -d
	lintian ${DSC} ${DSC_DBG}
${DSC_DBG}: ${DSC}

.PHONY: dinstall
dinstall: deb
	dpkg -i ${DEB} ${DEB_DBG}

.PHONY: upload
upload: ${DEB}
	tar cf - ${DEB} ${DEB_DBG} | ssh -X repoman@repo.proxmox.com upload --product pbs,pve --dist buster

.PHONY: clean
clean:
	rm -rf *~ ${BUILDDIR} ${PACKAGE}-*/ *.prepared
	rm -f ${PACKAGE}*.tar.gz *.deb *.changes *.buildinfo *.dsc
