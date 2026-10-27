# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# The module must run from the initramfs, before nvidia binds the card.
MODULES_INITRAMFS_IUSE=+initramfs
PYTHON_COMPAT=( python3_{12..15} )
inherit edo linux-mod-r1 python-any-r1

COMMIT=6081407b312aa3139a2bed62bdda354f4ffddc1d
# Pinned upstream: the firmware is extracted from this driver release and
# its paths are compiled into the module. Unrelated to installed nvidia-drivers.
NV_PV=610.43.03
NV_URI=https://download.nvidia.com/XFree86
NV_INSTALLER=NVIDIA-Linux-x86_64-${NV_PV}-no-compat32.run
NV_SOURCE=NVIDIA-kernel-module-source-${NV_PV}

DESCRIPTION="Pre-driver unlock of the full FP16/BF16/TF32 rate on consumer NVIDIA Ampere cards"
HOMEPAGE="https://github.com/gi0baro/gpu-unlock"
SRC_URI="
	https://github.com/gi0baro/gpu-unlock/archive/${COMMIT}.tar.gz -> ${P}.tar.gz
	${NV_URI}/NVIDIA-kernel-module-source/${NV_SOURCE}.tar.xz
	${NV_URI}/Linux-x86_64/${NV_PV}/${NV_INSTALLER}
"
S=${WORKDIR}/${PN}-${COMMIT}

LICENSE="GPL-2 NVIDIA-2025"
SLOT="0"
KEYWORDS="-* ~amd64"
RESTRICT="bindist mirror"

BDEPEND="
	${PYTHON_DEPS}
	app-arch/zstd
"

CONFIG_CHECK="PCI FW_LOADER"

pkg_setup() {
	python-any-r1_pkg_setup
	linux-mod-r1_pkg_setup
}

src_unpack() {
	# The installer is read in place by extract_gsp.py, not unpacked.
	unpack ${P}.tar.gz ${NV_SOURCE}.tar.xz
}

src_compile() {
	local assets=${WORKDIR}/assets
	edo "${EPYTHON}" firmware/extract_gsp.py "${DISTDIR}/${NV_INSTALLER}" "${assets}"
	edo "${EPYTHON}" firmware/extract_boot_assets.py "${WORKDIR}/${NV_SOURCE}" "${assets}"

	local modlist=( gpu_unlock=extra:kernel/gpu_unlock )
	local modargs=( KDIR="${KV_OUT_DIR}" )
	linux-mod-r1_src_compile
}

src_install() {
	linux-mod-r1_src_install

	# The kernel firmware loader searches /lib/firmware.
	emake DESTDIR="${D}" ASSETS="${WORKDIR}/assets" \
		FWDIR=/lib/firmware/gpu-unlock/${NV_PV} \
		LICENSEDIR=/usr/share/doc/${PF} \
		install-firmware
	# The GSP images are ELF files that must stay byte-identical.
	dostrip -x /lib/firmware/gpu-unlock

	# The eclass only adds the module to the image. It has no PCI ID table,
	# so nothing would load it: force_drivers loads it before udev starts.
	if use initramfs; then
		cat packaging/boot/dracut.conf >> \
			"${ED}"/usr/lib/dracut/dracut.conf.d/10-${PN}.conf || die
	fi
}

pkg_postinst() {
	linux-mod-r1_pkg_postinst

	if ! use initramfs; then
		ewarn "USE=-initramfs: gpu_unlock is not in the initramfs and will never run."
	fi
	elog "gpu_unlock loads on every boot but does nothing until the kernel"
	elog "command line opts in, e.g. in /etc/default/grub:"
	elog "  GRUB_CMDLINE_LINUX=\"gpu_unlock.targets=all\""
	elog "then: grub-mkconfig -o /boot/grub/grub.cfg"
	elog "Remove the option in the GRUB edit screen to boot without the unlock."
	elog "Check the result with: journalctl -k -b | grep gpu_unlock"
}
