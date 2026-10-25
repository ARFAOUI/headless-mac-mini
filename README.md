# Headless Mac mini

A [Claude Code](https://claude.com/claude-code) skill (and a plain checklist for humans) for
turning a Mac mini into an **always-on, headless machine** on your home network: something you
never plug a screen into again, that comes back by itself after a power cut, that you reach over
**SSH** at home and over **Tailscale** from anywhere, and that runs autonomous AI agents under a
**separate non-admin user**. Optionally, it sits on **its own VLAN** so that only your machine
can talk to it.

Everything in here was done for real on an M4 Mac mini running macOS 26, and every gotcha below
is one we actually hit.

```
            internet
               |
        router / firewall  <-- optional: Mac mini on its own VLAN,
               |                only your laptop may connect in
     +---------+---------+
     |                   |
 your laptop  --SSH-->  Mac mini (headless)
     |                   |   admin user: you
     +--- Tailscale -----+   agent user: no sudo, auto-login, runs the agents
        (from anywhere)
```

## What you end up with

- `ssh mini` from your laptop with a key, no prompts (so agents on your laptop can use it too)
- `ssh mini-agent` as a standard user that cannot `sudo` or read your files
- Reboots unattended: no FileVault prompt, auto-login, launchd jobs start, Tailscale reconnects
- Never sleeps, restarts after power failure, firewall on
- Remote access through Tailscale only, no ports forwarded on the router
- Optional: isolated VLAN, internet allowed, LAN blocked both ways except for your laptop

## Using it as a Claude Code skill

```bash
git clone https://github.com/ARFAOUI/headless-mac-mini ~/.claude/skills/headless-mac-mini
```

Then in Claude Code: *"set up my new Mac mini as a headless agent host"*. Claude walks the
phases in `SKILL.md`, runs what it can over SSH, and hands you the few commands that need a
password typed by a human.

## Using it by hand

Follow the phases in order. Each links to the exact commands.

| # | Phase | Where |
|---|---|---|
| 0 | First boot checklist, once, at the keyboard | [first-boot-checklist.md](references/first-boot-checklist.md) |
| 1 | Local SSH with a key and an alias | [ssh-access.md](references/ssh-access.md) |
| 2 | Audit what is there | [`scripts/audit.sh`](scripts/audit.sh) |
| 3 | Power, firewall, Command Line Tools, Homebrew, Node, Claude Code | [bootstrap.md](references/bootstrap.md), [`scripts/bootstrap.sh`](scripts/bootstrap.sh) |
| 4 | Tailscale remote access | [tailscale.md](references/tailscale.md) |
| 5 | Non-admin agent user + auto-login | [agent-user.md](references/agent-user.md), [`scripts/create-agent-user.sh`](scripts/create-agent-user.sh) |
| 6 | VLAN isolation (optional, UniFi examples) | [vlan-isolation.md](references/vlan-isolation.md) |
| 7 | Jobs that survive reboots | [`templates/agent.plist`](templates/agent.plist) |
| 8 | Hardening + cleanup | [hardening.md](references/hardening.md) |
| | macOS updates and major upgrades over SSH | [macos-updates.md](references/macos-updates.md) |

### Quick start

```bash
# on your laptop, after the first-boot checklist
ssh-keygen -t ed25519 -N "" -f ~/.ssh/mini_ed25519
cat ~/.ssh/mini_ed25519.pub | ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no \
  you@<mini-ip> 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys'
# add a "Host mini" block to ~/.ssh/config (see ssh-access.md), then:

ssh mini 'bash -s' < scripts/audit.sh          # see what needs fixing
# temporary passwordless sudo, once (you type the password):
ssh -t mini 'echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/zz-setup >/dev/null && sudo chmod 440 /etc/sudoers.d/zz-setup'
ssh mini 'bash -s' < scripts/bootstrap.sh      # settings + toolchain + Tailscale (prints a login URL)
scripts/create-agent-user.sh mini <mini-ip>    # agent user, its key, auto-login
ssh mini 'sudo shutdown -r now'                # then re-run audit.sh: console user should be "agent"
ssh mini 'sudo rm /etc/sudoers.d/zz-setup'     # do not forget
```

## Gotchas this saves you from

| Symptom | Cause | Fix |
|---|---|---|
| `Too many authentication failures` before any password prompt | ssh offers every key in your agent first | `-o PreferredAuthentications=password -o PubkeyAuthentication=no` |
| `ssh -v` says `Server accepts key` then `Permission denied` | Your private key has a passphrase and the agent is empty | A dedicated key without a passphrase for this host |
| Password prompts fail inside Claude Code's `!` prompt | It is not an interactive terminal | Run those commands in a real Terminal window |
| Standard user gets `Connection closed` over SSH | Remote Login only admits the `admin` group by default | `dseditgroup -o edit -a <user> -t user com.apple.access_ssh` |
| `sysadminctl -autologin set` prints `SACSetAutoLoginPassword error:22` | Auto-login user switched, but the password file did not | [`scripts/write-kcpassword.py`](scripts/write-kcpassword.py) |
| A new user can read your dotfiles | macOS homes are `750`, group `staff`, and everyone is in `staff` | `chmod 700` every home |
| `xcode-select --install` does nothing over SSH | It opens a GUI dialog | Install the package through `softwareupdate` (bootstrap.md) |
| Tailscale app stops when nobody is logged in | The GUI app runs per user | Homebrew `tailscale` as a system service |
| `mini.local` stops resolving after the VLAN move | mDNS does not cross VLANs | Use a DHCP reservation and the IP |
| Other devices still reach the Mac after "isolating" it with rules | Same subnet traffic never hits the router | Its own VLAN, not just rules |
| Allow rule for your laptop randomly stops working | Rotating private Wi-Fi address, new IP | Set Private Wi-Fi Address to Fixed + DHCP reservation |
| `softwareupdate --download` ends with `Failed to authenticate` | Apple silicon: preparing the update needs the volume owner's password | Download is fine; install with `--user <admin> --stdinpass` |
| Major upgrade queues "for post-logout install" and never restarts | It waits for the auto-logged-in console user to log out | `sudo launchctl bootout gui/<uid>` of the console user (macos-updates.md) |
| `shutdown -r` after queueing comes back on the old version | A plain restart does not run a queued install | Do not kick it; re-run the install or use `startosinstall` |
| VLAN rules do not apply to Tailscale traffic | WireGuard tunnels go end-to-end | Restrict it in the tailnet policy (tailscale.md) |

## Deliberate tradeoffs

- **FileVault off.** Required for unattended reboots. The disk is not encrypted at rest; keep
  secrets you cannot afford to lose off this machine, or accept the risk.
- **Auto-login.** `/etc/kcpassword` is obfuscated, not encrypted. It holds the password of a user
  with no admin rights, which limits what it is worth.
- **Agent user without passphrase key.** The key is only accepted by one machine that only your
  laptop can reach.

## Requirements

- A Mac (Apple silicon tested; Intel should work), macOS 14 or newer
- A display and keyboard for about 15 minutes, once
- For phase 6: a router that does VLANs (examples use UniFi; the rule logic is generic)

## License

MIT
