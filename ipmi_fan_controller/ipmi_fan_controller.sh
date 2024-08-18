#!/bin/bash

CONFIG_FILE="ipmi_fan_controller.conf"

declare -A CPU_TEMP
declare -A DISK_TEMP
declare -A NVME_TEMP

LOG_DEBUG=1
LOG_INFO=2
LOG_WARN=3
LOG_ERROR=4

DEBUG_COLOR="\033[0m"
INFO_COLOR="\033[0;32m"
WARN_COLOR="\033[0;33m"
ERROR_COLOR="\033[0;31m"
RESET_COLOR="\033[0m"

# Config file section
IPMITOOL_ARGS=""

TEMP_READ_INT=5
CPU_CRIT_TEMP=90
DISK_CRIT_TEMP=90
NVME_CRIT_TEMP=90

LOG_LEVEL=$LOG_INFO
LOG_FILE_PATH=""
# End config file section

log() {
    local level=$1
    local message=$2
    local color
    local level_str
    local date_str
    
    if [ $LOG_LEVEL -gt "$level" ]; then
        return
    fi

    case $level in
    "$LOG_DEBUG") color=$DEBUG_COLOR level_str="DBG" ;;
    "$LOG_INFO") color=$INFO_COLOR level_str="INF" ;;
    "$LOG_WARN") color=$WARN_COLOR level_str="WAR" ;;
    "$LOG_ERROR") color=$ERROR_COLOR level_str="ERR" ;;
    *) color=$RESET_COLOR ;;
    esac

    date_str="$(date +'%Y-%m-%d %H:%M:%S')"

    if [ -f "$LOG_FILE_PATH" ]; then
        printf '%s [%s] %s\n' "$date_str" "$level_str" "$message" >>"$LOG_FILE_PATH"
    elif [ -d "$LOG_FILE_PATH" ]; then
        printf '%s [%s] %s\n' "$date_str" "$level_str" "$message" >>"$LOG_FILE_PATH/$(date +'%Y%m%d')"
    elif [ "$(ps -o ppid= -p $$)" -eq 1 ]; then
        printf '[%s] %s\n' "$level_str" "$message"
    else
        printf '%b%s [%s] %s%b\n' "$color" "$date_str" "$level_str" "$message" "$RESET_COLOR"
    fi
}

load_config() {
    if [[ ! -f $CONFIG_FILE ]]; then
        log "$LOG_ERROR" "Configuration file $CONFIG_FILE not found!"
        exit 1
    fi

    source "$CONFIG_FILE"
    log "$LOG_INFO" "Configuration loaded from $CONFIG_FILE."

    if [[ ${#CPU_TEMP[@]} -eq 0 ]]; then
        log "$LOG_ERROR" "CPU fan speed lookup table can not be empty"
        exit 1
    fi

    if [ "$LOG_FILE_PATH" != "" ] && [ ! -d "$LOG_FILE_PATH" ] && [ ! -f "$LOG_FILE_PATH" ]; then
        log "$LOG_ERROR" "Log directory \"$LOG_FILE_PATH\" not found"
    fi
}

get_sensor_array() {
    local sensor_type="$1"
    local -n sensor_arr="$2"

    sensor_arr=()
    for sensor_file in /sys/class/hwmon/hwmon*/temp*_input; do
        if [[ "$(cat "$(dirname "$sensor_file")/name")" == "$sensor_type" ]]; then
            sensor_arr+=("$sensor_file")
        fi
    done

    IFS=$'\n' read -d '' -r -a sensor_arr < <(printf '%s\n' "${sensor_arr[@]}" | sort -V)
}

log_sensors() {
    local sensor_type="$1"
    local -n sensor_array="$2"

    if [ ${#sensor_array[@]} ]; then
        log "$LOG_INFO" "Found ${sensor_type} temperature sensors:"
        for sensor in "${sensor_array[@]}"; do
            local device_path
            if [[ $sensor_type == "NVME" ]]; then
                device_path="$(dirname "$sensor")/device"
                log "$LOG_INFO" " - $(cat "${sensor//_input/_label}") $(tr -d '[:space:]' <"$device_path/model") SN:$(cat "$device_path/serial")"
            else
                log "$LOG_INFO" " - $(cat "${sensor//_input/_label}")"
            fi
        done
    else
        log "$LOG_WARN" "No ${sensor_type} temperature sensors found."
    fi
}

initialize_sensors() {
    local -a sensors

    get_sensor_array "coretemp" sensors
    CPU_SENSORS=("${sensors[@]}")
    log_sensors "CPU" CPU_SENSORS

    if ! [ ${#DISK_TEMP[@]} -eq 0 ]; then
        get_sensor_array "drivetemp" sensors
        DISK_SENSORS=("${sensors[@]}")
        log_sensors "Drive" DISK_SENSORS
    fi

    if ! [ ${#NVME_TEMP[@]} -eq 0 ]; then
        get_sensor_array "nvme" sensors
        NVME_SENSORS=("${sensors[@]}")
        log_sensors "NVME" NVME_SENSORS
    fi
}

get_max_temp() {
    local sensor_list=("$@")
    local max_temp=0
    local temp

    for sensor_file in "${sensor_list[@]}"; do
        temp=$(cat "$sensor_file")
        if [ "$temp" -gt "$max_temp" ]; then
            max_temp=$temp
        fi
    done

    if [ "$max_temp" -lt 0 ]; then
        return 0
    fi

    return $((max_temp / 1000))
}

lookup_fan_speed() {
    local temperature=$1
    local -n lookup_table=$2
    local fan_speed
    local x_1
    local y_1
    local x_2
    local y_2


    IFS=$'\n' read -d '' -r -a sorted_keys < <(printf '%s\n' "${!lookup_table[@]}" | sort -n)

    x_1=0
    y_1=0
    x_2="${sorted_keys[0]}"
    y_2="${lookup_table[$x_2]}"
    unset 'sorted_keys[0]'

    for threshold in "${sorted_keys[@]}"; do
        if [ "$temperature" -gt "$x_2" ]; then
            x_1=$x_2
            y_1=$y_2
            x_2=$threshold
            y_2="${lookup_table[$threshold]}"
        else
            break
        fi
    done

    fan_speed=$((y_2 - (x_2 - temperature) * (y_2 - y_1) / (x_2 - x_1)))

    return "$fan_speed"
}

get_fan_speed_for_sensor() {
    local sensor_type=$1
    local -n temp_map
    local sensors
    local crit_temp
    local max_temp
    local fan_speed

    if [[ $sensor_type == "CPU" ]]; then
        sensors=("${CPU_SENSORS[@]}")
        crit_temp=$CPU_CRIT_TEMP
        temp_map=CPU_TEMP
    elif [[ $sensor_type == "Drive" ]]; then
        sensors=("${DISK_SENSORS[@]}")
        crit_temp=$DISK_CRIT_TEMP
        temp_map=DISK_TEMP
    elif [[ $sensor_type == "NVME" ]]; then
        sensors=("${NVME_SENSORS[@]}")
        crit_temp=$NVME_CRIT_TEMP
        temp_map=NVME_TEMP
    else
        log "$LOG_ERROR" "Unknown sensor type: $sensor_type"
        return 0
    fi

    if [[ ${#sensors[@]} -eq 0 ]]; then
        log "$LOG_DEBUG" "Current $sensor_type sensor list is empty"
        return 0
    fi

    if [ ${#temp_map[@]} -eq 0 ]; then
        log "$LOG_ERROR" "Current $sensor_type lookup table is empty"
        return 0
    fi

    get_max_temp "${sensors[@]}"
    max_temp=$?
    log "$LOG_DEBUG" "Current $sensor_type temperature: $max_temp°C."

    if [ $max_temp -ge $crit_temp ]; then
        log "$LOG_ERROR" "$sensor_type temperature ($max_temp°C) exceeds the critical threshold of $crit_temp°C."
        return 255
    fi

    lookup_fan_speed "$max_temp" temp_map
    fan_speed=$?
    log "$LOG_DEBUG" "Current $sensor_type fan speed: $fan_speed%."

    return $fan_speed
}

set_fan_speed() {
    local speed=$1
    local speed_hex
    speed_hex=$(printf "0x%02x" "$speed")
    ipmitool $IPMITOOL_ARGS raw 0x30 0x30 0x02 0xff "$speed_hex" >/dev/null
    log "$LOG_INFO" "Fan speed set to ${speed}%."
}

set_mode() {
    local mode=$1
    local mode_value

    if [ "$mode" == "manual" ]; then
        mode_value=0x00
    elif [ "$mode" == "auto" ]; then
        mode_value=0x01
    else
        return
    fi

    log "$LOG_INFO" "Switching to $mode mode."
    ipmitool $IPMITOOL_ARGS raw 0x30 0x30 0x01 "$mode_value" >/dev/null
}

exit_trap() {
    set_mode "auto"
    log "$LOG_INFO" "$(basename "$0") was closed"
}

main_loop() {
    local cpu_speed
    local drive_speed
    local nvme_speed
    local max_speed
    local manual_mode=1
    local actual_fan_speed

    load_config

    log "$LOG_INFO" "Statring  $(basename "$0")"
    trap exit_trap EXIT
    initialize_sensors
    set_mode "manual"
    actual_fan_speed=0

    while :; do

        sleep "$TEMP_READ_INT"

        get_fan_speed_for_sensor "CPU"
        cpu_speed=$?
        get_fan_speed_for_sensor "Drive"
        drive_speed=$?
        get_fan_speed_for_sensor "NVME"
        nvme_speed=$?

        max_speed=$cpu_speed
        if [ "$drive_speed" -gt "$max_speed" ]; then
            max_speed=$drive_speed
        elif [ "$nvme_speed" -gt "$max_speed" ]; then
            max_speed=$nvme_speed
        fi

        if [ "$actual_fan_speed" -gt "$max_speed" ]; then
            max_speed=$((actual_fan_speed - 1))
        fi

        if [ "$max_speed" -gt 100 ]; then
            if [ $manual_mode ]; then
                set_mode "auto"
                manual_mode=0
            fi
            continue
        fi

        if ! [ "$manual_mode" ]; then
            set_mode "manual"
            manual_mode=1
        fi

        log "$LOG_DEBUG" "Adjusting fan speed to ${max_speed}%."
        if ! [ "$max_speed" -eq "$actual_fan_speed" ]; then
            set_fan_speed "$max_speed"
            actual_fan_speed=$max_speed
        fi
    done

}

main_loop
