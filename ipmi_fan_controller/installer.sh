#!/bin/sh


SCRIPT_NAME="ipmi_fan_controller"
GIT_REPO="https://raw.githubusercontent.com/L0rek/proxmox-scripts/main"
SCRIPT_URL="ipmi_fan_controller/ipmi_fan_controller.sh"
CONFIG_URL="ipmi_fan_controller/ipmi_fan_controller.conf"

usage() {
    {
        echo "Usage: $(basename "$0") <option>"
        echo "  --install                 Install ipmi fan controler"
        echo "  --uninstall               Uninstall ipmi fan controler" 
    } >&2
}

create_service() {
    _service_name=$1
    _script_path=$2
    _working_dir=$3
    _description=$5

    if systemctl is-active --quiet "${_service_name}.service"; then
        systemctl stop "${_service_name}.service"
        systemctl disable "${_service_name}.service"
    fi

    {
        echo "[Unit]"
        echo "Description=$_description"
        echo ""
        echo "[Service]"
        echo "User=root"
        echo "WorkingDirectory=$_working_dir"
        echo "ExecStart=$_script_path"
        echo "Restart=always"
        echo "RestartSec=3"
        echo ""
        echo "[Install]"
        echo "WantedBy=multi-user.target"
    } >"${_service_name}.service"

    mv "${_service_name}.service" "/lib/systemd/system/${_service_name}.service"
    systemctl daemon-reload
    systemctl start "${_service_name}.service"
    if systemctl is-active --quiet "${_service_name}.service"; then
        systemctl enable "${_service_name}.service"
        return 0
    fi

    return 1
}

remove_service() {
    _service_name=$1

    if systemctl is-active --quiet "${_service_name}.service"; then
        systemctl stop "${_service_name}"
        systemctl stop "${_service_name}.service"
        systemctl disable "${_service_name}.service"
    fi

    if  [ -f "/lib/systemd/system/${_service_name}.service" ]; then
        echo "Remove service: ${_service_name}"
        rm "/lib/systemd/system/${_service_name}.service"
    fi
}

download_file() {
    _file_url=$1
    _destiny=$2

    if ! wget -qO "$_destiny" "$_file_url"; then
        echo "Unbale to download file form url \"$_file_url\"" >&2
        exit 1
    fi
}

load_modules() {
    module=$1

    if lsmod | grep -q "$module"; then
        return 0
    fi

    if ! user_ask "Kernel module: \"${module}\" is not loaded. Would you like to load it? (y/n) "; then
        return 1
    fi

    echo "Load module: ${module}"

    if ! error=$(modprobe "$module" > /dev/null 2>&1); then
        msg_err "$error"
        return 1
    fi

    echo "$module" >"/etc/modules-load.d/${module}.conf"
    return 0
}

install() {
    load_modules "drivetemp"

    download_file "$GIT_REPO/$SCRIPT_URL" "${SCRIPT_NAME}.sh"
    download_file "$GIT_REPO/$CONFIG_URL" "${SCRIPT_NAME}.conf"

    chmod +x "${SCRIPT_NAME}.sh"

    if [ ! -d  "/var/log/$SCRIPT_NAME" ]; then
        mkdir "/var/log/$SCRIPT_NAME"
    fi
    
    create_service "$SCRIPT_NAME" "$(pwd)/${SCRIPT_NAME}.sh" "$(pwd)" "Service to control fan speed over ipmitool"
}

unistall() {
    remove_service "$SCRIPT_NAME"
    rm "${SCRIPT_NAME}.sh" > /dev/null 2>&1
    rm "${SCRIPT_NAME}.conf" > /dev/null 2>&1
    rm -r "/var/log/$SCRIPT_NAME"
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

    *)
        STATEMENTS
        usage
        ;;
    esac

}

main "$@"
