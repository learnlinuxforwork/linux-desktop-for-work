# Canonical Ubuntu

Sets up an Ubuntu Desktop LTS VM in VirtualBox and provisions it as a work machine:
cloud CLIs, container/IaC tooling, everyday desktop apps, a hardened firewall, and a
bottom-docked taskbar instead of the default side dock.

Two scripts, because VM creation happens on the host and provisioning happens inside
the guest OS:

| Script | Runs on | Purpose |
|---|---|---|
| [`01-host-create-launch-vm.sh`](01-host-create-launch-vm.sh) | Host (has VirtualBox) | Downloads Ubuntu Desktop, verifies its checksum, creates the VM, boots it |
| [`02-guest-provision-ubuntu.sh`](02-guest-provision-ubuntu.sh) | Guest (inside the VM) | Installs everything below and applies hardening/UI tweaks |

Run `01-host-create-launch-vm.sh` on a **macOS or Linux** host — it's plain bash. This
repo doesn't cover Windows hosts.

This always targets the current Ubuntu LTS — right now that's **26.04 (Resolute
Raccoon)**. Don't point it at an interim release; when the next LTS ships, bump
`UBUNTU_VERSION` at the top of `01-host-create-launch-vm.sh`.

## Usage — step by step

**1. Create and install the VM, completely unattended (on the host):**

```bash
./01-host-create-launch-vm.sh
```

You'll be prompted once for a password for the account it creates (default username
`devops` — override with `INSTALL_USER`). From there it runs with no further input:

1. Downloads Ubuntu 26.04.1 Desktop (override with `UBUNTU_VERSION`) and verifies its
   checksum.
2. Creates a VM named `ubuntu-devops` (4 GB RAM / 2 CPUs / 40 GB disk — override with
   `VM_MEMORY_MB`, `VM_CPUS`, `VM_DISK_MB`, `VM_NAME`).
3. Runs `VBoxManage unattended install`, which feeds Ubuntu's installer the answers
   (user/password, hostname, locale, timezone) automatically — this is VirtualBox's
   built-in unattended-install feature, not a hand-rolled autoinstall file.
4. Boots the VM in a window so you can watch it install (no clicks needed) and
   installs VirtualBox Guest Additions along the way.

This takes roughly 10-20 minutes. When it finishes, the VM reboots into the desktop —
log in as the user you set.

If the VM powers off instead of rebooting, start it again with
`VBoxManage startvm ubuntu-devops`.

**2. Provision the desktop (inside the VM, as your normal user — not root):**

```bash
chmod +x 02-guest-provision-ubuntu.sh
./02-guest-provision-ubuntu.sh
```

(Drag-and-drop and shared clipboard are enabled on the VM, so you can copy this script
in directly from the host.)

Both scripts are safe to run more than once — already-installed tools are just skipped.

## What gets installed

**Cloud & DevOps CLIs**
- AWS CLI v2
- Google Cloud CLI (gcloud, gsutil, bq)
- Terraform (HashiCorp apt repo)
- OpenTofu (official install script)
- Docker Engine (`docker-ce`, `docker-ce-cli`, `containerd.io`, buildx + compose
  plugins) — your user is added to the `docker` group; log out/in (or `newgrp docker`)
  to pick it up
- kubectl, pinned to the `v1.31` stable channel (override with `K8S_CHANNEL`)

**Desktop apps**
- VS Code
- OnlyOffice Desktop Editors
- Kooha (screen recorder, via Flatpak/Flathub)
- OBS Studio (official PPA)
- Surfshark VPN (official installer — run `surfshark-vpn login` once afterward)
- VLC
- Google Chrome

## Secure Boot

`01-host-create-launch-vm.sh` builds the VM with **EFI firmware and Secure Boot
enabled** — it initializes the VM's UEFI variable store and enrolls the standard
Microsoft and Oracle keys:

```bash
VBoxManage modifyvm "$VM_NAME" --firmware efi64
VBoxManage modifynvram "$VM_NAME" inituefivarstore
VBoxManage modifynvram "$VM_NAME" enrollmssignatures
VBoxManage modifynvram "$VM_NAME" enrollorclpk
```

Ubuntu's bootloader (`shim` + `grub`) is signed by Microsoft's UEFI CA, so it boots
straight through this with no extra steps — you don't need to do anything for the OS
itself to start.

**What this means for kernel modules.** Anything built on the guest at install time
rather than shipped pre-signed — most importantly **VirtualBox Guest Additions**
(`vboxguest`, `vboxsf`, `vboxvideo`, installed via DKMS) — is *not* signed, and Secure
Boot will refuse to load it. If shared clipboard, drag-and-drop, or display
auto-resize aren't working after you log in for the first time, this is why. Fix it
with a one-time MOK (Machine Owner Key) enrollment:

1. Inside the VM, trigger a rebuild so it generates a MOK and prompts for an
   enrollment password: `sudo dpkg-reconfigure virtualbox-guest-dkms` (or just
   `sudo update-secureboot-policy --enroll-key` if that's not present).
2. Set a password when prompted, then reboot.
3. At the blue **"MOK Management"** screen, choose **Enroll MOK** → **Continue** →
   enter the password you set → **Reboot**.
4. Verify: `mokutil --sb-state` should show Secure Boot enabled with no pending
   enrollment, and `lsmod | grep vbox` should list the modules as loaded.

**If you'd rather not deal with this**, turn Secure Boot off for the VM — either
uncheck it in the VirtualBox GUI (Settings → System → Motherboard → Enable Secure
Boot) or skip the three `modifynvram` lines above before creating the VM. EFI firmware
without Secure Boot still boots Ubuntu fine and never triggers the MOK dance.

**Host-side Secure Boot** is a separate, unrelated thing — that's about your own
machine's security blocking VirtualBox itself from running, not the VM:

- **Linux host:** if Secure Boot is enabled on your machine, VirtualBox's own kernel
  modules (`vboxdrv` and friends) need to be signed and enrolled the same way — the
  script's preflight check warns you if this looks unresolved. Trigger MOK enrollment
  with `sudo dpkg-reconfigure virtualbox-dkms` (Debian/Ubuntu) and follow the same
  "Enroll MOK" steps above, or simplest of all, disable Secure Boot in your machine's
  UEFI settings if your organization's policy allows it.
- **macOS host:** Secure Boot in the UEFI/MOK sense doesn't apply, but there are two
  analogous gotchas the script's preflight check watches for:
  - On an **Intel Mac**, VirtualBox needs its kernel extension approved once in
    **System Settings → Privacy & Security** (look for "System software from
    developer 'Oracle America, Inc.' was blocked" and click Allow), and on T2-chip
    Macs you may additionally need to boot into Recovery → Startup Security Utility
    and allow reduced kext security.
  - On **Apple Silicon (M-series) Macs**, VirtualBox's x86_64 guest support is a
    limited technology preview, not a supported setup — these scripts download an
    x86_64 ISO, which may run very slowly or not boot at all. Use an Intel Mac, or a
    native ARM hypervisor (UTM, Parallels, VMware Fusion) instead.

## Hardening & UI

- **Firewall (ufw):** default deny incoming, default allow outgoing, rate-limited SSH,
  logging on.
- **Dock position:** moved from the left side to the bottom of the screen
  (`org.gnome.shell.extensions.dash-to-dock dock-position BOTTOM`).
- **Final step:** full `apt update && apt upgrade` plus `autoremove`/`autoclean`, run
  last so it picks up anything pulled in by the installs above.

A reboot at the end is recommended to finish applying the dock change and any
kernel/driver updates.
