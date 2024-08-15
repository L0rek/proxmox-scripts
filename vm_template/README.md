# The script creates a template for virtual machines

## Usage
- download qcow2 image in this example debian-12-generic-amd64

```bash
wget -q --show-progress https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2
```

- download and run script
```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/L0rek/proxmox-scripts/main/vm_template/create_vm_template.sh) debian-12-generic-amd64.qcow2"
```