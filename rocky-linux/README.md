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
| [`01-host-create-launch-vm.sh`](01-host-create-launch-vm.sh) | Host (has VirtualBox) | Downloads Rocky Linux, verifies its checksum, creates the VM, installs it unattended |
| [`02-guest-provision-rocky.sh`](02-guest-provision-rocky.sh) | Guest (inside the VM) | Installs everything below and applies hardening/UI tweaks |

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

1. Downloads the current Rocky Linux 9 DVD ISO (override with `ROCKY_MAJOR`) and
   verifies its checksum.
2. Creates a VM named `rocky-devops` (4 GB RAM / 2 CPUs / 40 GB disk — override with
   `VM_MEMORY_MB`, `VM_CPUS`, `VM_DISK_MB`, `VM_NAME`).
3. Runs `VBoxManage unattended install`, which generates a kickstart file with the
   answers (user/password, hostname, locale, timezone) automatically — this is
   VirtualBox's built-in unattended-install feature, not a hand-written kickstart.
4. As a safety net, a post-install command explicitly installs the GNOME
   **Workstation** package group and sets the graphical boot target — the
   auto-generated kickstart's default package selection isn't guaranteed to include a
   desktop, so this guarantees you land on one regardless.
5. Boots the VM in a window so you can watch it install (no clicks needed) and
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
