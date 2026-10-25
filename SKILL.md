---
name: headless-mac-mini
description: Set up a Mac mini (or any Mac) as an always-on headless host on a home/office LAN, administered over SSH, reachable remotely through Tailscale, optionally isolated on its own VLAN, with a non-admin user for running autonomous AI agents. Trigger when the user wants to set up a headless Mac, a Mac mini server, an always-on agent box, "run Claude Code agents on a Mac mini", SSH into a new Mac, auto-login after reboot, Tailscale on a Mac, or isolate a Mac on a VLAN.
---

# Headless Mac mini setup

You are helping turn a Mac into an always-on machine that nobody sits in front of. The human does
a short one-time setup at the keyboard; you do everything else over SSH.

Work through the phases in order. Each phase has a reference file with the exact commands and the
gotchas that break it. **Read the reference before running the phase.**

| Phase | Who | Reference |
|---|---|---|
| 0. First boot checklist | Human, at the keyboard | `references/first-boot-checklist.md` |
| 1. Local SSH access (keys, alias) | Human runs 1-2 commands, then you | `references/ssh-access.md` |
| 2. Audit the machine | You | `scripts/audit.sh` |
| 3. System settings + toolchain | You (needs sudo) | `references/bootstrap.md`, `scripts/bootstrap.sh` |
| 4. Tailscale remote access | You + human signs in once | `references/tailscale.md` |
| 5. Non-admin agent user + auto-login | You | `references/agent-user.md`, `scripts/create-agent-user.sh` |
| 6. VLAN isolation (optional) | You, on the router | `references/vlan-isolation.md` |
| 7. Services that survive reboot | You | `templates/agent.plist` |
| 8. Hardening + cleanup | You, ask first | `references/hardening.md` |
| Any time: macOS updates | You + human types the owner password | `references/macos-updates.md` |

## Rules

- **Ask before anything hard to undo**: account creation, disabling password login, firewall or
  router changes, rebooting a machine that is already running work.
- **You cannot type passwords.** Commands you run are non-interactive. Anything that prompts
  (ssh password, sudo, key passphrase) must be run by the human in a real Terminal window. In
  Claude Code, the `! command` prompt is **not** interactive either: a password prompt there just
  fails. Hand the human one exact copy-paste command and wait.
- **Prefer a temporary NOPASSWD sudoers file** over asking for the password for every step, and
  **always delete it at the end** (phase 8). Track that you created it.
- **Verify, do not assume.** After every change, open a *new* SSH connection and check that you
  still get in. After phase 5, reboot once and confirm the console user and Tailscale come back.
- **Major macOS upgrades over SSH**: never "kick" a queued install with `shutdown -r`, always
  pass `--agree-to-license`, and read `references/macos-updates.md` first.
- **Never put real IPs, MACs, emails or passwords in anything you publish.** Store generated
  passwords in the admin's macOS Keychain (`security add-generic-password`), never in files.

## Done means

- `ssh <alias>` works with a key, no prompt, from the admin's main machine.
- `ssh <agent-alias>` works as a non-admin user who cannot `sudo` or read the admin's home.
- The machine reboots unattended, logs in the agent user, and Tailscale is connected.
- Sleep is off, restart after power failure is on, firewall is on, FileVault is off (by choice).
- (Optional) It sits on its own VLAN; only the admin's machine can reach it; it has internet.
- The temporary sudoers file is gone.
