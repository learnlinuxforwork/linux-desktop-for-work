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

## Usage

**1. Create and boot the VM (on the host):**

```bash
./01-host-create-launch-vm.sh
```

Downloads Ubuntu 24.04 Desktop (override with `UBUNTU_VERSION`), creates a VM named
`ubuntu-devops` (4 GB RAM / 2 CPUs / 40 GB disk — override with `VM_MEMORY_MB`,
`VM_CPUS`, `VM_DISK_MB`, `VM_NAME`), attaches the ISO, and boots it.

The Ubuntu installer itself is still interactive — VirtualBox has no unattended-install
button. Walk through it, and on the "Updates and other software" screen choose
**Minimal Installation** (not Normal) to keep the base OS lean. Reboot when it's done
and log in.

**2. Provision the desktop (inside the VM, as your normal user — not root):**

```bash
chmod +x 02-guest-provision-ubuntu.sh
./02-guest-provision-ubuntu.sh
```

Both scripts are idempotent — safe to re-run; already-installed tools are skipped.

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
