#!/bin/sh

VFIO_CONF="/etc/modules-load.d/vfio.conf"
KERNEL_IOMMU_CONF="/etc/default/grub.d/iommu.cfg"
MODPROBE_CONF="/etc/modprobe.d/iommu_unsafe_interrupts.conf"

usage() {
    {
        echo "Usage: $(basename "$0") <option>"
        echo "  --install                 Installs all required stuff for PCI Passthrough"
        echo "  --uninstall               Remove all stuff"
        echo "  --unsafe_interrupts       Special option for systems without interrupt remapping support"
    } >&2
}

enable_iommu() {
    _CONF_FILE="$1"
    _KERNE_CMD="iommu=pt"

    if [ -f "$_CONF_FILE" ]; then
        return
    fi

    echo "Adding required kernel command"

    if lscpu | grep -q "GenuineIntel"; then
        echo "Detected Intel cpu"
        _KERNE_CMD="$_KERNE_CMD intel_iommu=on"
    elif lscpu | grep -q "AuthenticAMD"; then
        echo "Detected AMD cpu"
        _KERNE_CMD="$_KERNE_CMD"
    else
        echo "Unown cpu type"
        exit 1
    fi

    echo "GRUB_CMDLINE_LINUX=\"\$GRUB_CMDLINE_LINUX $_KERNE_CMD\"" >"$_CONF_FILE"

    proxmox-boot-tool refresh
}

add_kernel_modules() {
    _CONF_FILE="$1"

    echo "Adding required kernel moduls"

    {
        echo "vfio"
        echo "vfio_iommu_type1"
        echo "vfio_pci"
    } >"$_CONF_FILE"

    update-initramfs -u -k all
}

reboot_ask() {
    printf "Reboot is needed, would you like reboot now (y/n): "
    read -r ANSWARE
    if [ "$ANSWARE" = 'y' ]; then
        reboot
    fi
}

allow_unsafe_interrupts() {

    if [ -f "$MODPROBE_CONF" ]; then
        return
    fi

    printf "Would you like to allow unsafe interrupts (y/n): "
    read -r ANSWARE
    if ! [ "$ANSWARE" = 'y' ]; then
        return
    fi

    echo "options vfio_iommu_type1 allow_unsafe_interrupts=1" >"$MODPROBE_CONF"
    echo "Unsafe interrupts now allowed"
    reboot_ask
}

install() {
    REBOOT=0

    if [ ! -f "$KERNEL_IOMMU_CONF" ]; then
        enable_iommu $KERNEL_IOMMU_CONF
        REBOOT=1
    fi

    if [ ! -f "$VFIO_CONF" ]; then
        add_kernel_modules $VFIO_CONF
        REBOOT=1
    fi

    if [ $REBOOT -eq 1 ]; then
        reboot_ask
    else
        echo "All is allready installed reboot not needed"
    fi
}

unistall() {
    REBOOT=0

    if [ -f "$KERNEL_IOMMU_CONF" ]; then
        rm -f $KERNEL_IOMMU_CONF
        proxmox-boot-tool refresh
        REBOOT=1
    fi

    if [ -f "$VFIO_CONF" ]; then
        rm -f $VFIO_CONF
        update-initramfs -u -k all
        REBOOT=1
    fi

    if [ -f "$MODPROBE_CONF" ]; then
        rm -f $MODPROBE_CONF
        REBOOT=1
    fi

    if [ $REBOOT -eq 1 ]; then
        reboot_ask
    else
        echo "All is allready uninstalled reboot not needed"
    fi
}

main() {
    if [ $# -ne 1 ]; then
        echo "Error: Illegal number of parameters" >&2
        usage
        exit 22
    fi

    if ! command -v proxmox-boot-tool refresh >/dev/null 2>&1; then
        echo "Error: This scprit is only for proxmox"
        exit 127
    fi

    case $1 in

    --install)
        install
        ;;

    --uninstall)
        unistall
        ;;

    --unsafe_interrupts)
        allow_unsafe_interrupts
        ;;

    *)
        STATEMENTS
        usage
        ;;
    esac

}

main "$@"
