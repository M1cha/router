# Router
This is my full router setup.

## Hardware
NanoPi R4S (with CNC case, 4GB RAM, no unique MAC) - [friendlyelec](https://www.friendlyelec.com/index.php?route=product/product&product_id=284) [wiki](https://wiki.friendlyelec.com/wiki/index.php/NanoPi_R4S)

## Operating system

### CoreOS

#### Build modified image
Since with the default layout, the reserved partition is too small you have to
create a modified one.

Download and extract official image:

```bash
podman run --privileged --rm -v .:/data -w /data quay.io/coreos/coreos-installer:release download --architecture aarch64
unxz fedora-coreos-38.20230514.3.0-metal.aarch64.raw.xz
```

Dump the old partition table and edit it to increase the size of `reserved`:

```bash
sfdisk --dump fedora-coreos-38.20230514.3.0-metal.aarch64.raw > layout.sfdisk
# See coreos/layout.sfdisk for the edited version
```

Dump the original partitions:

```bash
kpartx -av fedora-coreos-38.20230514.3.0-metal.aarch64.raw
dd if=/dev/mapper/loop0p2 of=efi.bin
dd if=/dev/mapper/loop0p3 of=boot.bin
dd if=/dev/mapper/loop0p4 of=root.bin
kpartx -d fedora-coreos-38.20230514.3.0-metal.aarch64.raw
```

Create new disk image, apply the partition table, flash the partitions and compress it:

```bash
truncate -s 2880438272 new.raw
sfdisk new.raw < coreos/layout.sfdisk
kpartx -av new.raw
dd if=efi.bin of=/dev/mapper/loop0p2
dd if=boot.bin of=/dev/mapper/loop0p3
dd if=root.bin of=/dev/mapper/loop0p4
kpartx -d new.raw
cat new.raw | xz -1 > new.raw.xz
```

#### Install
Convert ignition config

```bash
podman run --interactive --rm quay.io/coreos/butane:release --pretty --strict < coreos/router.bu > coreos/router.ign
```

Write to micro SD:

```bash
sudo podman run --privileged --rm -v /dev:/dev -v /run/udev:/run/udev -v .:/data -w /data quay.io/coreos/coreos-installer:release install --offline --image-file new.raw.xz --ignition-file coreos/router.ign --insecure /dev/mmcblk0
```

### Install Firmware
- checkout uboot `v2022.10`
- apply `coreos/0001-HACK-remove-UHS-property.patch`
- compile u-boot with `nanopi-r4s-rk3399_defconfig`
- `dd if=u-boot-rockchip.bin of=/dev/mmcblk0 seek=64`

### Install additional packages

```bash
rpm-ostree install htop iperf3 NetworkManager-ppp pciutils ppp python3 sqm-scripts tcpdump traceroute usbutils
```

- htop, iperf3, pciutils, tcpdump, traceroute, usbutils: They're just very useful
- NetworkManager-ppp, ppp, sqm-scripts: Router stuff
- python3: For ansible

## ansible

Create vault:

```bash
ansible-vault create --vault-id main@prompt /path/to/router_secrets/vars.yaml
ansible-vault create --vault-id main@prompt /path/to/router_secrets/wg_main.nmconnection
ansible-vault create --vault-id main@prompt /path/to/router_secrets/wg_parents.nmconnection
ansible-vault create --vault-id main@prompt /path/to/router_secrets/dnsmasq-hosts
ansible-vault create --vault-id main@prompt /path/to/router_secrets/dnsmasq-private.conf
ansible-vault create --vault-id main@prompt /path/to/router_secrets/ddclient.conf
```

Apply with secrets:

```bash
ansible-playbook -e secrets_dir=/path/to/router_secrets --vault-id main@prompt main.yml
```

Apply without secrets:

```bash
ansible-playbook --skip-tags needs_secrets main.yml
```
