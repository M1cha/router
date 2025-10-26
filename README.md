# Router

This is my full router setup.

## Operating system

### CoreOS

Convert ignition config

```bash
podman run --interactive --rm quay.io/coreos/butane:release --pretty --strict < coreos/router.bu > coreos/router.ign
```

Create VM

```bash
virt-install \
        --connect="qemu:///system" \
        --name=router \
        --os-variant="fedora-coreos-stable" \
        --vcpus=2 \
        --memory=4096 \
        --graphics=none \
        --nonetworks \
        --host-device=pci_0000_01_00_0 \
        --host-device=pci_0000_01_00_1 \
        --disk="size=10,backing_store=/var/lib/libvirt/images/fedora-coreos-40.20241019.3.0-qemu.x86_64.qcow2" \
        --qemu-commandline="-fw_cfg name=opt/com.coreos/config,file=/var/lib/libvirt/images/router.ign" \
        --import
```

### Install additional packages

```bash
rpm-ostree install htop iperf3 node-exporter sqm-scripts tcpdump traceroute usbutils
```

- htop, iperf3, tcpdump, traceroute, usbutils: They're just very useful
- node-exporter: for recording system information
- sqm-scripts: Router stuff

### Trust my own CA

The gotify client needs this.

```bash
update-ca-trust
```

### Update

```bash
./update
```
