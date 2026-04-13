# NVIDIA RTX 5070 (Blackwell) on Fedora 43 — Blank Screen Fix Runbook

**Date:** 2026-03-25
**System:** ASRock Rack B650D4U-2L2T/BCM, AMD Ryzen (Raphael), NVIDIA GeForce RTX 5070 (GB205), Fedora 43, KDE Plasma / SDDM / Wayland

---

## Symptoms

1. **Blank screen on boot** — After selecting Fedora in GRUB, the monitor showed a backlit black screen. No login screen, no console, nothing.
2. **High fan speeds / CPU load** — After getting back in via `nomodeset`, Chrome was consuming 85-90% CPU. Fans were running noticeably louder than normal despite minimal workloads (Chrome, Cursor, Ghostty).
3. **Slow boot / double-reboot required** — First power-on would hang at the ASRock screen (Redfish/OData server timeout from the BMC). A second manual reboot was needed to reach the GRUB menu.

## Root Causes

### 1. NVIDIA Driver Version Mismatch (caused high CPU / fan issue)

A system update (`dnf update`) installed new NVIDIA userspace libraries (`580.126.18`) but the kernel module running in memory was still the old version (`580.119.02`). This broke GPU acceleration entirely.

```
$ nvidia-smi
Failed to initialize NVML: Driver/library version mismatch
NVML library version: 580.126
```

Chrome detected the broken GPU and fell back to **software rendering** (`--disable-gpu-compositing` flag on all renderer processes), causing the CPU to do all compositing work.

**Fix:**
```bash
sudo akmods --force && sudo dracut --force
# Then reboot
```

### 2. Blank Screen Without `nomodeset` (the main issue)

This had **three interacting causes**:

#### a) Fedora kernel patch conflict with `nvidia-drm.modeset=1` on command line

Fedora's kernel has a custom patch that detects `nvidia-drm.modeset=1` on the kernel command line and **suppresses simpledrm framebuffer registration** in response. The intent is "NVIDIA will handle display, so don't load simpledrm." But NVIDIA modules weren't in the initramfs, so they loaded 30+ seconds after boot. Result: no simpledrm AND no NVIDIA for 30 seconds = blank screen.

> RPM Fusion documents this: "The parameter nvidia-drm.modeset=1 produces a bad interaction with a Fedora Kernel specific patch to deal with early boot display with simpledrm."

On Fedora, `nvidia-drm.modeset=1` must be set via `/etc/modprobe.d/` only, **never on the kernel command line**.

#### b) Three-way VGA device conflict

The system has three VGA-capable devices:

| Device | PCI Address | Role |
|--------|-------------|------|
| NVIDIA RTX 5070 | `01:00.0` | Primary display (discrete GPU) |
| ASPEED AST2600 | `09:00.0` | BMC out-of-band management chip |
| AMD Raphael iGPU | `0f:00.0` | CPU integrated graphics |

At boot, the ASPEED BMC chip **owned VGA I/O and memory resources** while NVIDIA was designated the "boot VGA device." The AMD iGPU failed to initialize (`error -22`). This three-way conflict disrupted the display handoff when NVIDIA tried to take over KMS.

#### c) Late NVIDIA module loading

NVIDIA modules were not in the initramfs. They loaded from disk ~30 seconds after boot, long after `simpledrm` had claimed the framebuffer. The simpledrm-to-nvidia DRM handoff during KMS initialization failed silently, producing a blank screen.

### 3. BMC Redfish Boot Delay

The ASRock Rack B650D4U has an ASPEED BMC (Baseboard Management Controller) with IPMI/Redfish support. At each power-on, the BMC tries to fetch firmware configuration from a Redfish OData server on the network. Since no such server exists, it times out, adding significant delay to every boot.

**Fix:** Disable Redfish network boot in BIOS/UEFI settings (BMC/IPMI configuration section).

## The Solution

### Step 1: Fix GRUB — Remove nvidia-drm params from kernel command line

```bash
# /etc/default/grub should have:
GRUB_CMDLINE_LINUX="rd.luks.uuid=luks-331f43a5-f71c-4a70-a831-793cd532a28d rhgb quiet rd.driver.blacklist=nouveau,nova_core amdgpu.modeset=0 module_blacklist=ast"
```

Key points:
- **No `nomodeset`** — this disables all GPU KMS and forces software rendering
- **No `nvidia-drm.modeset=1`** on the command line — causes Fedora kernel patch conflict
- **`amdgpu.modeset=0`** — prevents AMD iGPU from competing for display
- **`module_blacklist=ast`** — prevents ASPEED BMC driver from loading into the display stack (note: `module_blacklist=` is the correct kernel parameter syntax, not `modprobe.blacklist=`)

Apply:
```bash
sudo grubby --update-kernel=ALL --remove-args='nvidia-drm.modeset=1 nvidia-drm.fbdev=1 modprobe.blacklist=ast nomodeset'
sudo grubby --update-kernel=ALL --args='amdgpu.modeset=0 module_blacklist=ast'
sudo grub2-mkconfig -o /boot/grub2/grub.cfg
```

### Step 2: Set nvidia-drm options via modprobe.d (the correct Fedora way)

```bash
echo 'options nvidia-drm modeset=1 fbdev=1' | sudo tee /etc/modprobe.d/nvidia.conf
```

- `modeset=1` — enables NVIDIA KMS
- `fbdev=1` — registers NVIDIA framebuffer device, required on kernel 6.11+ for Blackwell boot display output

### Step 3: Hard-blacklist the ASPEED ast driver

```bash
echo 'install ast /usr/bin/false' | sudo tee /etc/modprobe.d/blacklist-ast.conf
```

This is stronger than `module_blacklist=` — it ensures the `ast` module can never load, even if something tries to pull it in. BMC remote management (IPMI/KVM-over-IP) is unaffected since it doesn't use the kernel-side `ast` DRM driver.

### Step 4: Add NVIDIA modules to initramfs (early boot loading)

```bash
cat << 'EOF' | sudo tee /etc/dracut.conf.d/nvidia.conf
add_drivers+=" nvidia nvidia_modeset nvidia_uvm nvidia_drm "
install_items+=" /lib/firmware/nvidia/580.126.18/gsp_ga10x.bin /lib/firmware/nvidia/580.126.18/gsp_tu10x.bin "
EOF
```

This is the critical fix. Loading NVIDIA in the initramfs means it initializes within seconds of boot (before simpledrm can establish itself), eliminating the framebuffer handoff problem entirely.

> **Note:** The `install_items` firmware paths are version-specific. After a driver update (e.g., 580.x to 590.x), update the paths and rebuild.

### Step 5: Add SDDM startup delay

```bash
sudo mkdir -p /etc/systemd/system/sddm.service.d
echo -e '[Service]\nExecStartPre=/usr/bin/sleep 2' | sudo tee /etc/systemd/system/sddm.service.d/delay.conf
```

Confirmed fix for an RTX 5070 race condition where SDDM starts before the GPU is fully ready.

### Step 6: Rebuild initramfs and reboot

```bash
sudo dracut --force

# Verify nvidia is in the initramfs
sudo lsinitrd /boot/initramfs-$(uname -r).img | grep -E 'nvidia|gsp'
# Should show nvidia.ko, nvidia_drm.ko, nvidia_modeset.ko, and gsp_*.bin files

sudo reboot
```

## Verification

After reboot (do NOT add `nomodeset`), confirm the GPU is working:

```bash
# nvidia-smi should show the GPU with processes using it
nvidia-smi

# Boot params should NOT contain nomodeset or nvidia-drm.modeset
cat /proc/cmdline

# Boot journal should show nvidia-drm initialized as primary fb0 within seconds
journalctl -b | grep -E "nvidia.*fb|Initialized nvidia"

# CPU load should be low (< 1.0 at idle)
uptime
```

Expected healthy state:
- `nvidia-smi`: GPU at ~28C, ~10-15W idle, multiple KDE/Wayland processes listed
- NVIDIA initializes within ~3 seconds of simpledrm (vs 30+ seconds without initramfs loading)
- CPU load average < 0.5 at idle
- Fans quiet

## Troubleshooting

### If blank screen still occurs after applying all fixes

1. **Press `e` at GRUB** and add `nomodeset` at the end of the `linux` line to get back in
2. **Try DisplayPort instead of HDMI** — there is a confirmed RTX 5070 bug where the driver defaults to DP output after reboot, leaving HDMI blank
3. **Check for a motherboard BIOS update** — multiple users have resolved RTX 5070 blank screen issues with BIOS updates alone
4. **Try `initcall_blacklist=simpledrm_platform_driver_init`** on the kernel command line as a last resort (disables simpledrm entirely; you lose Plymouth boot splash)
5. **NVIDIA GPU VBIOS update** — NVIDIA released a [GPU UEFI Firmware Update Tool](https://nvidia.custhelp.com/app/answers/detail/a_id/5411/) for RTX 50-series blank screen issues (Windows-only tool)

### After kernel or NVIDIA driver updates

The initramfs must be rebuilt to include the updated NVIDIA modules:
```bash
sudo dracut --force
# Update firmware paths in /etc/dracut.conf.d/nvidia.conf if the driver version changed
```

### Important: Do NOT upgrade to NVIDIA 590.x drivers

As of this writing, NVIDIA driver 590.48.01 has a known bug causing RTX 5070/5070 Ti to fall back to PCIe Gen1 (2.5 GT/s), resulting in black screens and system hangs. Stay on 580.x until this is resolved. (Ref: [NVIDIA open-gpu-kernel-modules #1010](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1010))

## References

- [RPM Fusion NVIDIA Howto](https://rpmfusion.org/Howto/NVIDIA) — Fedora-specific nvidia-drm.modeset warning
- [Arch Wiki NVIDIA/Troubleshooting](https://wiki.archlinux.org/title/NVIDIA/Troubleshooting) — ASPEED + NVIDIA multi-GPU conflict
- [NVIDIA Developer Forums: RTX 5070 Ti SOLVED](https://forums.developer.nvidia.com/t/solved-nvidia-drivers-msi-geforce-rtx-5070ti-inspire-3x-16gb-not-working-in-any-linux-distro/339530) — HDMI output bug
- [CachyOS Forum: SDDM Freeze with RTX 5070 Ti](https://discuss.cachyos.org/t/sddm-freeze-on-boot-with-nvidia-rtx-5070-ti-wayland-workaround-feedback-on-new-update/22569) — SDDM race condition
- [Fedora Discussion: simpledrm + NVIDIA interaction](https://discussion.fedoraproject.org/t/talk-proprietary-nvidia-driver-shows-a-black-screen-instead-of-a-virtual-terminal-or-a-graphical-session/75981)
- [GitLab: Fedora kernel-ark patch for simpledrm + nvidia-drm.modeset](https://gitlab.com/cki-project/kernel-ark/-/merge_requests/1788)
