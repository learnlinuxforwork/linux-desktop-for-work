# Build Your Own Work-Ready Linux Desktop (Ubuntu & Rocky Linux, Fully Automated)

If you're learning Linux for DevOps or sysadmin work, one of the best things you can
do is stop treating your practice environment as a throwaway. In this lesson, you'll
build a real, reusable Linux desktop VM — the kind you'd actually use for cloud work,
day to day — and you'll build it in a way that's scripted, repeatable, and secure by
default.

We're using **VirtualBox** as the platform because it's free, it runs on both macOS
and Linux, and it gives us full command-line control over how a VM is created and
installed. No clicking through installer screens. No guessing what got installed.
Everything is defined in a script you can read top to bottom.

By the end of this lesson, you'll have a VM running **either Ubuntu Desktop LTS or
Rocky Linux Workstation** — your choice, or both — fully provisioned with the cloud
CLIs, DevOps tooling, and everyday apps you'd actually want on a work machine.

## What you'll practice in this lesson

This isn't just "run a script and watch it work." Along the way you'll get hands-on
with concepts that show up constantly in real DevOps and sysadmin work:

- **Unattended OS installation** — how `VBoxManage unattended install` feeds an
  installer its answers automatically, the same idea behind tools like cloud-init and
  kickstart that provision real servers.
- **UEFI Secure Boot** — what it actually does, why signed bootloaders matter, and
  what happens when you introduce an *unsigned* kernel module into a Secure Boot
  environment (spoiler: you'll fix this yourself, by hand, so it sticks).
- **Firewall hardening** — default-deny rules, rate-limited SSH, and the difference
  between `ufw` (Ubuntu) and `firewalld` (Rocky) for doing the same job.
- **Package management across two ecosystems** — the same tool, installed two
  different ways: `apt`/`deb` on Ubuntu, `dnf`/`rpm` on Rocky.
- **Secrets hygiene in scripts** — how to prompt for a password without ever putting
  it on the command line or leaving it sitting in a file.

## What gets installed

Both distros end up with the same working set — this is a real environment, not a
bare-bones demo:

**Cloud & DevOps CLIs**
AWS CLI v2 · Google Cloud CLI · Terraform · OpenTofu · Docker Engine · kubectl

**Desktop apps**
VS Code · OnlyOffice Desktop Editors · Kooha (screen recording) · OBS Studio ·
Surfshark VPN · VLC · Google Chrome

**Security & polish**
EFI firmware with Secure Boot enabled · hardened firewall (default-deny, rate-limited
SSH) · dock repositioned to the bottom of the screen · fully patched at the end

## Before you start

You need:

- A **macOS or Linux** host machine (this course doesn't cover Windows hosts — these
  are plain bash scripts).
- [VirtualBox](https://www.virtualbox.org/wiki/Downloads) installed.
- A little patience — Ubuntu takes roughly 10-20 minutes to install unattended, Rocky
  closer to 20-30, since it also installs a full desktop environment during setup.

## How it works, at a glance

Every distro in this repo follows the same two-script pattern, because VM creation
happens on your **host** machine and provisioning happens **inside the guest**:

![Setup flow diagram showing the host script downloading an ISO, creating a VM with Secure Boot enabled, and installing it unattended, followed by a guest script that installs tooling, hardens the firewall, and repositions the dock — for both Ubuntu and Rocky Linux](setup-flow.svg)

**On the host**, one script does the heavy lifting:

1. Downloads the ISO into a standard `~/iso` folder (skips the download entirely if
   you've already staged the file there yourself).
2. Creates the VM and sizes it (RAM, CPU, disk — all overridable).
3. Enables Secure Boot — EFI firmware, Microsoft and Oracle keys enrolled.
4. Runs the install completely unattended. You watch; you don't click.

**Inside the guest**, once you've logged in, a second script installs every tool
listed above, hardens the firewall, moves the dock, and finishes with a full system
update.

## Try it yourself

The full instructions, both scripts, and a section for each distro are in the course
repo:

**[github.com/learnlinuxforwork/linux-desktop-for-work](https://github.com/learnlinuxforwork/linux-desktop-for-work)**

Start with whichever distro matches what you're trying to learn — Ubuntu if you want
the `apt`/Debian family, Rocky if you want the `dnf`/RHEL family. Or do both, and
compare how the same job gets done two different ways. That comparison is where a lot
of the real learning happens.

## What's next

Once your desktop is up, don't just leave it idle — use it. Authenticate `aws` and
`gcloud` against real (or sandboxed) accounts, spin up a Terraform plan, pull a
container with Docker, point `kubectl` at a cluster. The whole point of building this
environment yourself is that you understand every piece of it, which means you're not
afraid to poke at it, break it, and rebuild it — which, unattended install being what
it is, takes you about twenty minutes.
