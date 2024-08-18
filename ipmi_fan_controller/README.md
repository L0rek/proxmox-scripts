# Ipmi fan controller 

This script is designed for manually managing fan speeds based on defined curves.

- The fan speed is set according to the maximum value from the defined curves.
- The configuration allows defining any number of points on the curve.
- Temperature values cannot be repeated.
- The desired fan speed is determined using a linear function.
- For a temperature value of 0, the default fan speed is set to 0.
- If no curve is defined for a particular sensor, that sensor will be ignored.
- For more details, refer to the configuration file.

Tested on Dell R730xd

## Usage
- Install

```bash
mkdir /root/ipmi_fan_controller
cd /root/ipmi_fan_controller
bash -c "$(wget -qLO - https://raw.githubusercontent.com/L0rek/proxmox-scripts/main/ipmi_fan_controller/installer.sh) --install"
```

- Uninstall

```bash
cd /root/ipmi_fan_controller
bash -c "$(wget -qLO - https://raw.githubusercontent.com/L0rek/proxmox-scripts/main/ipmi_fan_controller/installer.sh) --uninstall"
```

- Reset after config was updated

```bash
systemctl restart ipmi_fan_controller.service
```