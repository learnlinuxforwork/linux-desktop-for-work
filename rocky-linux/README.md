# Rocky Linux

Sets up a Rocky Linux Workstation VM in VirtualBox and provisions it as a work
machine: cloud CLIs, container/IaC tooling, everyday desktop apps, a hardened
firewall, and a bottom-docked taskbar instead of the default GNOME layout.

This mirrors the [`canonical-ubuntu/`](../canonical-ubuntu/README.md) section — same
tool list, same two-script split — adapted for a `dnf`/`rpm` distro instead of
`apt`/`deb`.

Two scripts, because VM creation happens on the host and provisioning happens inside
the guest OS:

| Script | Runs on | Purpose |
|---|---|---|
| [`01-host-create-launch-vm.sh`](01-host-create-launch-vm.sh) | Host (has VirtualBox) | Downloads Rocky Linux to `~/iso`, creates the VM with Secure Boot enabled, installs it unattended |
| [`02-guest-provision-rocky.sh`](02-guest-provision-rocky.sh) | Guest (inside the VM) | Installs everything below and applies hardening/UI tweaks |

Run `01-host-create-launch-vm.sh` on a **macOS or Linux** host — it's plain bash. This
repo doesn't cover Windows hosts.

This always targets the current Rocky Linux major version — right now that's
**Rocky Linux 9**. Don't pin to an old point release; the script tracks Rocky's
"latest" convenience filename so it always grabs the current 9.x build. When Rocky
ships a new major version, bump `ROCKY_MAJOR` at the top of
`01-host-create-launch-vm.sh`.

## Usage — step by step

**1. Create and install the VM, completely unattended (on the host):**

```bash
./01-host-create-launch-vm.sh
```

You'll be prompted once for a password for the account it creates (default username
`devops` — override with `INSTALL_USER`). From there it runs with no further input:

1. Downloads the current Rocky Linux 9 DVD ISO into `~/iso` (override with
   `ROCKY_MAJOR` and `ISO_DIR`) and verifies its checksum — or, if you've already
   placed `Rocky-9-latest-x86_64-dvd.iso` in `~/iso` yourself, skips straight to using
   it.
2. Creates a VM named `rocky-devops` (4 GB RAM / 2 CPUs / 40 GB disk — override with
   `VM_MEMORY_MB`, `VM_CPUS`, `VM_DISK_MB`, `VM_NAME`).
3. Enables Secure Boot on the VM — EFI firmware, Microsoft + Oracle keys enrolled. See
   "Secure Boot" below for what that means once you're inside the VM.
4. Runs `VBoxManage unattended install`, which generates a kickstart file with the
   answers (user/password, hostname, locale, timezone) automatically — this is
   VirtualBox's built-in unattended-install feature, not a hand-written kickstart.
5. As a safety net, a post-install command explicitly installs the GNOME
   **Workstation** package group and sets the graphical boot target — the
   auto-generated kickstart's default package selection isn't guaranteed to include a
   desktop, so this guarantees you land on one regardless.
6. Boots the VM in a window so you can watch it install (no clicks needed) and
   installs VirtualBox Guest Additions along the way.

Because of the extra package group install, this takes roughly 20-30+ minutes. When
it finishes, the VM reboots into the desktop — log in as the user you set.

If the VM powers off instead of rebooting, start it again with
`VBoxManage startvm rocky-devops`.

If you land on a text login instead of a desktop (e.g. no network during install), log
in at the console and run:

```bash
sudo dnf groupinstall -y 'Workstation'
sudo systemctl set-default graphical.target
sudo reboot
```

**2. Provision the desktop (inside the VM, as your normal user — not root):**

```bash
chmod +x 02-guest-provision-rocky.sh
./02-guest-provision-rocky.sh
```

(Drag-and-drop and shared clipboard are enabled on the VM, so you can copy this script
in directly from the host.)

Both scripts are safe to run more than once — already-installed tools are just skipped.

## What gets installed

**Cloud & DevOps CLIs**
- AWS CLI v2
- Google Cloud CLI (gcloud, gsutil, bq)
- Terraform (HashiCorp yum repo)
- OpenTofu (official install script, rpm method)
- Docker Engine (`docker-ce`, `docker-ce-cli`, `containerd.io`, buildx + compose
  plugins) — your user is added to the `docker` group; log out/in (or `newgrp docker`)
  to pick it up
- kubectl, pinned to the `v1.31` stable channel (override with `K8S_CHANNEL`)

**Desktop apps**
- VS Code (Microsoft's official yum repo)
- OnlyOffice Desktop Editors (official rpm)
- Kooha (screen recorder, via Flatpak/Flathub)
- OBS Studio (via Flatpak/Flathub — not in Rocky's own repos, and Flathub is the
  source Rocky/RHEL users are pointed to)
- Surfshark VPN (via Snap — Surfshark doesn't publish an rpm repo; their own support
  docs point RHEL/Fedora users at Snap, so this script installs snapd via EPEL first.
  Run `sudo snap install surfshark` again after your first login if it fails right
  after snapd is enabled, then log in to the app)
- VLC (via RPM Fusion — not in Rocky's own repos due to licensing)
- Google Chrome (official rpm)

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

Rocky's bootloader (`shim` + `grub2`) is signed by Microsoft's UEFI CA, same as
Ubuntu's, so it boots straight through this with no extra steps — you don't need to
do anything for the OS itself to start.

**What this means for kernel modules.** Anything built on the guest at install time
rather than shipped pre-signed — most importantly **VirtualBox Guest Additions**
(`vboxguest`, `vboxsf`, `vboxvideo`) — is *not* signed, and Secure Boot will refuse to
load it. If shared clipboard, drag-and-drop, or display auto-resize aren't working
after you log in for the first time, this is why. Rocky doesn't have a one-line
`dpkg-reconfigure`-style fix for this the way Debian/Ubuntu does, so it's a manual
signing procedure:

```bash
# 1. Generate a signing key (once)
sudo mkdir -p /root/module-signing && cd /root/module-signing
sudo openssl req -new -x509 -newkey rsa:2048 -keyout MOK.priv -outform DER \
  -out MOK.der -nodes -days 36500 -subj "/CN=VirtualBox Guest Additions signing key/"

# 2. Enroll it — sets a one-time password, then reboot
sudo mokutil --import MOK.der
sudo reboot
```

At the blue **"MOK Management"** screen, choose **Enroll MOK** → **Continue** →
enter the password you set → **Reboot**. Then sign and load the modules:

```bash
sudo dnf install -y kernel-devel-$(uname -r)
for mod in vboxguest vboxsf vboxvideo; do
  sudo /usr/src/kernels/$(uname -r)/scripts/sign-file sha256 \
    /root/module-signing/MOK.priv /root/module-signing/MOK.der \
    "/lib/modules/$(uname -r)/misc/${mod}.ko" 2>/dev/null
  sudo modprobe "$mod"
done
mokutil --sb-state   # should show Secure Boot enabled, no pending enrollment
lsmod | grep vbox    # should list the modules as loaded
```

**If you'd rather not deal with this**, turn Secure Boot off for the VM — either
uncheck it in the VirtualBox GUI (Settings → System → Motherboard → Enable Secure
Boot) or skip the three `modifynvram` lines above before creating the VM. EFI firmware
without Secure Boot still boots Rocky fine and never triggers the MOK dance.

**Host-side Secure Boot** is a separate, unrelated thing — that's about your own
machine's security blocking VirtualBox itself from running, not the VM:

- **Linux host:** if Secure Boot is enabled on your machine, VirtualBox's own kernel
  modules (`vboxdrv` and friends) need to be signed and enrolled the same way — the
  script's preflight check warns you if this looks unresolved. On a Fedora/RHEL-family
  host, try `sudo /sbin/vboxconfig` to trigger a rebuild (it will prompt for MOK
  enrollment if needed), or fall back to the same manual `openssl`/`mokutil`/
  `sign-file` procedure above, applied to `vboxdrv.ko` instead. Simplest of all:
  disable Secure Boot in your machine's UEFI settings if your organization's policy
  allows it.
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

- **Firewall (firewalld):** default zone `public`, the default unlimited SSH allow is
  replaced with a rate-limited rule (10/minute), logging on for denied traffic.
- **Dock position:** the `dash-to-dock` GNOME extension is installed and moved from
  the left side to the bottom of the screen
  (`org.gnome.shell.extensions.dash-to-dock dock-position BOTTOM`) — Rocky's default
  GNOME layout doesn't ship a persistent dock at all, so this is what adds one.
- **Final step:** `dnf upgrade` plus `autoremove`, run last so it picks up anything
  pulled in by the installs above.

A reboot at the end is recommended to finish applying the dock change and any
kernel/driver updates.
