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

## Conventions

- Scripts are idempotent — safe to re-run after interruption or to pick up new tools.
- Host-side steps (creating/booting a VM) and guest-side steps (provisioning the OS
  inside it) are kept in separate scripts, since they run in different places.
- Nothing is installed beyond what's documented in each section's README — no bundled
  extras.
