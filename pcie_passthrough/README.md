# The script installs all required stuff for PCI Passthrough

## Usage
- Install

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/L0rek/proxmox-scripts/main/vm_template/pcie_passthrough.sh) --install"
```

- Uninstall

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/L0rek/proxmox-scripts/main/vm_template/pcie_passthrough.sh) --uninstall"
```


## Problems
`kernel: vfio_iommu_type1_attach_group: No interrupt remapping support.`

If you got this message in the logs after a reboot use this command

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/L0rek/proxmox-scripts/main/vm_template/pcie_passthrough.sh) --unsafe_interrupts"
```