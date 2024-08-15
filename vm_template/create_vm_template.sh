#!/bin/sh

abort_msg() {
    {
        echo "***************"
        echo "*** ABORTED ***"
        echo "***************"
        echo "An error occurred. Exiting..."
    } >&2
    exit 1
}

usage() {
    {
        echo "Usage: $(basename "$0") <image_file>"
    } >&2
}

create_vm() {
    _VMID=$1
    _STORAGE=$2

    qm create "$_VMID" \
        --ostype l26 \
        --cpu host \
        --socket 1 \
        --cores 1 \
        --memory 512 \
        --net0 virtio \
        --serial0 socket \
        --agent 1 \
        --scsihw virtio-scsi-pci \
        --machine q35
}

import_disk() {
    _VMID=$1
    _STORAGE=$2
    _IMAGE=$3

    qm set "$_VMID" \
        --scsi0 "$_STORAGE:0,discard=on,format=qcow2,import-from=$(pwd)/$_IMAGE" \
        --boot order=scsi0
    qm disk resize "$_VMID" scsi0 4G
}

config_bios() {
    _VMID=$1
    _STORAGE=$2

    qm set "$_VMID" \
        --bios ovmf \
        --efidisk0 "$_STORAGE:1,efitype=4m,pre-enrolled-keys=1"
}

config_cloudinit() {
    _VMID=$1
    _STORAGE=$2

    DEFAULT_USER="user"

    mkdir -p "/var/lib/vz/snippets/"
    {
        echo "#cloud-config"
        echo ""
        echo "# Update timezone"
        echo "timezone: $(cat /etc/timezone)"
        echo ""
        echo "package_update: true"
        echo "package_upgrade: true"
        echo "package_reboot_if_required: true"
        echo ""
        echo "# Install packages"
        echo "packages:"
        echo "    - qemu-guest-agent"
        echo "runcmd:"
        echo "    - systemctl start qemu-guest-agent"
    } >"/var/lib/vz/snippets/$_VMID-cloud-init.yaml"

    qm set "$_VMID" \
        --ide0 "$_STORAGE:cloudinit" \
        --cicustom "vendor=local:snippets/$_VMID-cloud-init.yaml" \
        --sshkeys ~/.ssh/authorized_keys \
        --ipconfig0 ip=dhcp

    printf "Set username default (%s): " "$DEFAULT_USER"
    read -r USER
    if [ -z "$USER" ]; then
        USER=$DEFAULT_USER
    fi

    qm set "$_VMID" --ciuser "$USER" --cipassword
}

create_template() {
    _IMG=$1

    VMID=9000
    LOCAL_STORAGE=$(sed -rn 's/.*(local-.+).*/\1/p' </etc/pve/storage.cfg)

    printf "Set template id default (%s): " $VMID
    read -r USER_VMID
    if [ -n "$USER_VMID" ]; then
        VMID=$USER_VMID
    fi

    printf "Set template storage default (%s): " "$LOCAL_STORAGE"
    read -r STORAGE
    if [ -z "$STORAGE" ]; then
        STORAGE=$LOCAL_STORAGE
    fi

    trap 'abort_msg' 0
    set -e

    create_vm "$VMID" "$STORAGE"
    import_disk "$VMID" "$STORAGE" "$_IMG"
    config_bios "$VMID" "$STORAGE"

    printf "Would you like to config cloudinit (y/n): "
    read -r ANSWARE
    if [ "$ANSWARE" = 'y' ] || [ -z "$ANSWARE" ] ; then
        config_cloudinit "$VMID" "$STORAGE"
    fi

    qm template "$VMID"

    trap : 0

    printf "Set template name: "
    read -r NAME
    if [ -n "$NAME" ]; then
        qm set "$_VMID" --name "$NAME"
    fi

    echo "VM $_VMID was created"
}

main() {
    if [ $# -ne 1 ]; then
        echo "Error: Illegal number of parameters" >&2
        usage
        exit 22
    fi

    if [ ! -f "$1" ]; then
        echo "Image \"$1\" not found!"
        exit 2
    fi

    if ! command -v qm >/dev/null 2>&1; then
        echo "Error: qm could not be found"
        exit 127
    fi

    create_template "$1"
}

main "$@"
