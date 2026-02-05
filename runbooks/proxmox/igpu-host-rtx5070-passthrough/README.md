# Proxmox: Host on AMD iGPU (DP) + Fedora VM on RTX 5070 Passthrough (HDMI)

## Goal

A stable dual-display workflow:

- **Proxmox host console** uses the **Ryzen 9 7900x iGPU** over **DisplayPort** (DP → motherboard).
- **Fedora Workstation VM** uses the **RTX 5070** passed through via **VFIO** over **HDMI** (HDMI → RTX 5070).
- Proxmox **never binds** to the NVIDIA GPU (prevents black screens / driver fights).
- VM is reachable on VLAN-tagged network (example: VM on VLAN 10, host on VLAN 40).

This avoids “finicky” behavior and keeps Proxmox stable while still giving the VM full GPU acceleration.

---

## Hardware / Setup Assumptions

- CPU: AMD Ryzen 9 7900x (iGPU present)
- Discrete GPU: NVIDIA RTX 5070
- Motherboard: ASRock (with iGPU + dGPU present)
- Proxmox VE installed (ZFS mirror in this setup)
- Monitor: LG ultrawide (or similar) with input switching
- Cabling:
  - DP → motherboard (host)
  - HDMI → RTX 5070 (VM)

---

## Common Failure Modes

### 1) Proxmox shows no display (DP/HDMI black)
Usually caused by:
- `nomodeset` lingering in kernel cmdline
- Host console mapped to the wrong framebuffer device (ASPEED/BMC or simpledrm)
- Host binding to NVIDIA instead of VFIO

### 2) VM “runs” but monitor shows **no signal** on HDMI (monitor powers off)
Usually caused by:
- OVMF Secure Boot / enrolled keys interfering
- ROM BAR disabled for the passthrough device
- GPU VBIOS not being provided (UEFI GOP doesn’t initialize output)

### 3) Passthrough intermittently fails after VM stop/start
Can be architecture/reset quirks. Mitigate by:
- Keeping the VM running instead of frequent stop/start
- Full host reboot if GPU fails to reinitialize (worst case)

---

## BIOS Settings (Recommended)

Names vary by board, but aim for:

- **Primary Display / Initial Display Output**: `iGPU` / `Onboard`
- **iGPU Multi-Monitor**: `Enabled`
- **SVM**: `Enabled`
- **IOMMU**: `Enabled`
- **CSM**: `Disabled` (UEFI)

Then cable:
- DP to motherboard for host
- HDMI to RTX for VM

---

## Proxmox Host Configuration

### 1) Ensure `nomodeset` is removed
On ZFS + UEFI, Proxmox often uses **systemd-boot**.

Check:
```bash
cat /etc/kernel/cmdline
````

Example desired cmdline:

```
root=ZFS=rpool/ROOT/pve-1 boot=zfs quiet amd_iommu=on iommu=pt
```

Apply:

```bash
proxmox-boot-tool refresh
update-initramfs -u -k all
reboot
```

> Note: If using GRUB, update `/etc/default/grub` then run `update-grub`.

### 2) Bind the RTX 5070 to VFIO (host must NOT load NVIDIA drivers)

Find GPU IDs:

```bash
lspci -nn | grep -i nvidia
```

Example:

* GPU: `10de:2f04`
* Audio: `10de:2f80`

Load VFIO modules:

```bash
cat >/etc/modules-load.d/vfio.conf <<'EOF'
vfio
vfio_pci
vfio_iommu_type1
EOF
```

Blacklist NVIDIA + nouveau on the host:

```bash
cat >/etc/modprobe.d/blacklist-nvidia.conf <<'EOF'
blacklist nouveau
blacklist nvidia
blacklist nvidiafb
blacklist nvidia_drm
blacklist nvidia_modeset
blacklist nvidia_uvm
EOF
```

Force VFIO to claim the GPU early:

```bash
cat >/etc/modprobe.d/vfio-pci.conf <<'EOF'
options vfio-pci ids=10de:2f04,10de:2f80 disable_vga=1
EOF
```

Rebuild + reboot:

```bash
update-initramfs -u -k all
reboot
```

Verify:

```bash
lspci -nnk -s 01:00.0
lspci -nnk -s 01:00.1
```

Expected:

* `Kernel driver in use: vfio-pci` on both.

### 3) Verify host display is on AMD iGPU

```bash
lsmod | egrep 'amdgpu|drm'
for f in /sys/class/graphics/fb*/name; do echo "$f: $(cat $f)"; done
```

Expected:

* `amdgpu` loaded
* `fb0: amdgpudrmfb`

---

## VM Configuration (Fedora Workstation)

### Proxmox VM settings (known-good)

* BIOS: `OVMF (UEFI)`
* Machine: `q35`
* Display: `none`
* CPU: `host`
* Add PCI Device:

  * Device: `0000:01:00.0`
  * ✅ All Functions
  * ✅ PCI-Express
  * ✅ Primary GPU
  * ROM-Bar: typically enabled in this setup (see below)

Example `/etc/pve/qemu-server/100.conf` essentials:

```conf
bios: ovmf
machine: q35
vga: none

# Helpful for NVIDIA passthrough
cpu: host,hidden=1,flags=+pcid
args: -cpu 'host,kvm=off'

# GPU passthrough
hostpci0: 0000:01:00,pcie=1,x-vga=1,rombar=1

# EFI disk (Secure Boot OFF recommended while debugging)
# pre-enrolled-keys=0 is important if you hit black screen/no-signal issues
efidisk0: local-zfs:vm-100-disk-0,efitype=4m,pre-enrolled-keys=0,size=1M
```

### Critical fixes that restored HDMI output

#### A) Disable OVMF Secure Boot / Pre-enrolled keys

If HDMI shows **no signal**:

* Edit EFI Disk
* Set `pre-enrolled-keys=0`
* Remove `ms-cert=...` if present

#### B) Enable ROM BAR for the passthrough GPU

Set `rombar=1` on `hostpci0`.

#### C) If still no signal: pass the GPU VBIOS ROM file

Some systems never initialize the dGPU at boot (because iGPU is primary),
so OVMF doesn’t have a usable GOP to light up HDMI.

Dump VBIOS:

```bash
GPU_PATH="/sys/bus/pci/devices/0000:01:00.0"
echo 1 > "$GPU_PATH/rom"
cat "$GPU_PATH/rom" > /usr/share/kvm/rtx5070.rom
echo 0 > "$GPU_PATH/rom"
ls -lh /usr/share/kvm/rtx5070.rom
```

Use it in VM config:

```conf
hostpci0: 0000:01:00,pcie=1,x-vga=1,rombar=1,romfile=rtx5070.rom
```

Restart VM:

```bash
qm stop 100
qm start 100
```

---

## Validation Checklist

### Host

```bash
lspci -nnk -s 01:00.0 | grep -E 'Kernel driver in use|Kernel modules'
# expect vfio-pci in use

for f in /sys/class/graphics/fb*/name; do echo "$f: $(cat $f)"; done
# expect amdgpudrmfb on fb0
```

### VM (from inside Fedora)

```bash
lspci -nnk | grep -A3 -i nvidia
# expect NVIDIA GPU present + driver in use once installed
```

---

## Notes / Operational Guidance

* Prefer keeping the Fedora workstation VM running rather than frequent stop/start.
* If the GPU ever stops initializing after a VM reboot, fully power-cycle the host as a last resort.
* Keep all VFIO + blacklist settings documented and versioned here.
* For networking: Proxmox host can remain on VLAN 40, VM on VLAN 10 using `tag=10` on the VM NIC.

---

## Change Log

* 2016-02-05: Restored dual display workflow (iGPU host DP + RTX 5070 passthrough HDMI).
* Key fixes: disabled pre-enrolled keys (Secure Boot), enabled ROM BAR, optional VBIOS ROM file.

