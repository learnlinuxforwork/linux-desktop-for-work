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

## Hardening & UI

- **Firewall (ufw):** default deny incoming, default allow outgoing, rate-limited SSH,
  logging on.
- **Dock position:** moved from the left side to the bottom of the screen
  (`org.gnome.shell.extensions.dash-to-dock dock-position BOTTOM`).
- **Final step:** full `apt update && apt upgrade` plus `autoremove`/`autoclean`, run
  last so it picks up anything pulled in by the installs above.

A reboot at the end is recommended to finish applying the dock change and any
kernel/driver updates.
