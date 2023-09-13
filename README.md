# Initialise Intel Ethernet SR-IOV virtual functions

This is my compilation from multiple methods to adchieve SR-IOV for my network card (model: X540-AT2).

P.S.  I really need a new name for the service!

## Compatibility

Notable cards that supports SR-IOV from Intel (recommended): https://www.intel.com/content/www/us/en/support/articles/000005722/ethernet-products.html

Mine is an Intel 10GBPS Ethernet card with model number X540-AT2.

## Enable IOMMU function

Configure just like PCI passthrough, the recommended guide to enable passthrough: https://forum.proxmox.com/threads/pci-gpu-passthrough-on-proxmox-ve-8-installation-and-configuration.130218/

It is recommended to follow the above extensive guide to enable IOMMU, but note the `IMPORTANT` of this section because it would be useful 99% of the time.

Make sure that VT-d setting is enabled in BIOS or UEFI (mileage varies).

Append to `GRUB_CMDLINE_LINUX_DEFAULT` either `intel_iommu=on iommu=pt` for Intel CPUs or `amd_iommu=on iommu=pt` for AMD CPUs; example:
```
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt"
```

Update GRUB:
```
update-grub
```

To load the modules used for IOMMU, create `/etc/modules-load.d/vfio.conf` with:
```
vfio
vfio_iommu_type1
vfio_pci
```

IMPORTANT, update initramfs after modifying `modules-load.d` and `modprobe.d` for the kernel to apply your configuration (I learned it the hard way):
```
update-initramfs -u -k all
```

Reboot to apply the changes.

## Create virtual functions (VFs)

First, get the MAC address of the port(s) of the interface supporting SR-IOV, e.g. `6c:92:bf:01:23:45`.

Match that MAC address to the interface listed by:
```
ip link
```
Example: `enp4s0f1` will be our interface name.

To create virtual functions now, type:
```
echo <num_of_VFs> > /sys/class/net/<interface_name>/device/sriov_numvfs
```
Where `<num_of_VFs>` is the number of virtual functions to create, and `<interface_name>` being the interface name found before; example:
```
echo 5 > /sys/class/net/enp4s0f1/device/sriov_numvfs
```

The virtual functions will now shown as PCI devices:
```
lspci -nn | grep "Virtual Function"
```
and as interfaces:
```
ip link
```

These virtual functions disappear as PVE reboots; so to permanently create the virtual functions at startup:
- Find the kernel module used by the interface supporting SR-IOV:
```
lspci -nnk | grep -A4 Eth
```
Remember: not the module used by the PCI devices that have "Virtual Function" in their name; example: `ixgbe`
- Create a UDEV rule `/etc/udev/rules.d/81-net-intelsriov.rules` with:
```
ACTION=="add", SUBSYSTEM=="net", ENV{ID_NET_DRIVER}=="<kernel_module>", ATTR{address}=="<MAC_address>", ATTR{device/sriov_numvfs}="<num_of_VFs>"
```
Replace the `<>` with appropriate values found before, e.g.
```
ACTION=="add", SUBSYSTEM=="net", ENV{ID_NET_DRIVER}=="ixgbe", ATTR{address}=="6c:92:bf:01:23:45", ATTR{device/sriov_numvfs}="5"
```
Source: [Red Hat documentation, Section 16.2.2](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/virtualization_deployment_and_administration_guide/sect-pci_devices-pci_passthrough#sect-SR_IOV-Using_SR_IOV), Procedure 16.8, Step 4


## Prepare virtual functions for passthough

To allow the virtual functions passing to the VMs, the virtual functions must use the kernel module `vfio-pci`.  There are two options: either `softdep` or blacklist outright.  For my part I blacklist the virtual function module.

To get the module in-use and the PCI vendor:product, enters:
```
lspci -nnk | grep -A4 "Virtual Function"
```
In this case: `ixgbevf` is the virtual function kernel module and `8086:1515` is the PCI device vendor and product.

### Create soft dependency

Following the same recommended guide in [Enable IOMMU function], create `/etc/modprobe.d/vfio.conf` with:
```
options vfio-pci ids=<vid:pid_of_the_VF>
softdep <VF_kernel_module> pre: vfio-pci
```
E.g.:
```
options vfio-pci ids=8086:1515
softdep ixgbevf pre: vfio-pci
```

Update initramfs and reboot.

### Blacklist

Just create `/etc/modprobe.d/blacklist-vfs.conf` with:
```
blacklist <VF_kernel_module>
```
Example:
```
blacklist ixgbevf
```

Update initramfs and reboot.

## Set MAC address for virtual functions

By default, MAC address of the virtual function is randomly generated when active.  To enforce a MAC address for the virtual functions I have created a script and systemd service that executes before the VM autostart service.

### Installation

- Clone this repository
- Make the script `sriov-vf-setmac.sh` executable (apply `755` or `+x`)
- Copy the folder `net-sriov-vf-setmac` into `/etc`
- Copy `net-sriov-vf-setmac@.service` into `/etc/systemd/system`
- Reload systemd daemon (`systemctl daemon-reload`)
- Create config file in `/etc/net-sriov-vf-setmac` using the interface name that has virtual functions as config file name, ends with `.conf` with the virtual functions to set MAC address and the respective MAC addresses to set
- Active the service to start at startup: `systemctl enable net-sriov-vf-setmac@<interface-name>.service` where `<interface-name>` is the name of the aforementioned interface
- Set the MAC address now: `systemctl start net-sriov-vf-setmac@<interface-name>.service`.  Note: only matching virtual functions with MAC address `00:00:00:00:00:00` are set.

### Configuration file

The configuration file names the interface that has virtual functions to which MAC address(es) will be set.  Within the configuration file are the set of virtual functions and their respective MAC address to which to apply.  The structure is as follow:
```
VFS=("VF1" "VF0" "VF2")

VF1="00:11:22:33:44:55"
VF2="11:22:33:AA:BB:CC"
VF0="11:22:33:DD:EE:FF"
```
The array `VFS` contains a set of virtual functions to set MAC address.  Each string matches a represenative variable that contains the MAC address (e.g. `VF1`).  This configuration file is interpreted by the script as an environment file, providing the set and the MAC address(es) as environment variables to be filled into a standard command to set the MAC address.

### Specifying MAC address of the physical function instead

There exists an experimental script that use physical function MAC address to identify the interface instead of name.  To use it, clone this repository as usual, but switch the branch to `setmac_use_macaddr`; continue the install procedure above all the same except the cloning part, but name the configuration file with MAC address of the physical function instead in the form `00-00-00-00-00-00.conf` and use `00-00-00-00-00-00` as `<interface-name>` when calling the systemd service.
