# Linux Desktop For Work

Scripted, repeatable configurations for setting up Linux desktop VMs for work — cloud
CLIs, dev tooling, and hardened defaults, ready to run in VirtualBox (or adapted for
bare metal).

Each distro/environment gets its own top-level directory with its own README covering
what it installs and how to run it.

## Sections

- [`canonical-ubuntu/`](canonical-ubuntu/README.md) — Ubuntu Desktop LTS in VirtualBox,
  provisioned with AWS/GCP CLIs, container & IaC tooling, VS Code, and everyday desktop
  apps, plus firewall hardening and a bottom-docked taskbar.
- [`rocky-linux/`](rocky-linux/README.md) — Rocky Linux Workstation in VirtualBox, with
  the same tooling and hardening as the Ubuntu section, adapted for a `dnf`-based distro.

## Conventions

- Scripts are safe to run more than once — re-running after an interruption, or to pick up new tools, won't break anything.
- Host-side steps (creating/booting a VM) and guest-side steps (provisioning the OS
  inside it) are kept in separate scripts, since they run in different places.
- Nothing is installed beyond what's documented in each section's README — no bundled
  extras.
- Always target the current LTS (Ubuntu) or current major release (Rocky) — never an
  interim/non-LTS release. When a new one ships, bump the version at the top of the
  relevant host script instead of leaving an old one pinned.
- VM installs are fully unattended via `VBoxManage unattended install` — no clicking
  through an installer. See each section's README for the exact steps.
