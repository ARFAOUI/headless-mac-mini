# Phase 5: non-admin agent user and auto-login

## Why

Autonomous agents often run with permission prompts disabled and read untrusted content (web
pages, repos, issues). That content can try to steer them (prompt injection). The agent can do
whatever its account can do.

| Running as | A hijacked agent can |
|---|---|
| Admin | `sudo` (instantly, if NOPASSWD is still on), change firewall, sshd, Tailscale, read the admin's SSH keys, tokens, Keychain |
| Standard user | Touch its own home folder. No `sudo`, no system settings, no admin secrets |

Costs: the agent user cannot `brew install` (do it as admin), and only one user can auto-login.
On a dedicated, VLAN-isolated box the gain is smaller but still worth it for unattended runs.

## Steps

`scripts/create-agent-user.sh` does all of this. Manually:

1. **Lock the admin home.** macOS creates homes as `drwxr-x---` with group `staff`, and every
   standard user is in `staff`, so the agent could read the admin's dotfiles.
   ```bash
   sudo chmod 700 /Users/<admin>
   ```
2. **Generate a password and keep it in the admin Mac's Keychain**, not in a file. Auto-login
   needs a password even though nobody will type it.
   ```bash
   PW=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)
   security add-generic-password -U -s mini-agent -a agent -w "$PW"
   # read back later: security find-generic-password -s mini-agent -a agent -w
   ```
3. **Create the user** (standard by default) and its home:
   ```bash
   sudo sysadminctl -addUser agent -fullName "Agent" -password "$PW" -home /Users/agent
   sudo createhomedir -c -u agent
   sudo chmod 700 /Users/agent       # new homes are 750 too
   ```
4. **Allow it over SSH** (Remote Login is admin-only by default):
   ```bash
   sudo dseditgroup -o edit -a agent -t user com.apple.access_ssh
   ```
5. **Give it its own key** (generate on the main Mac, install into `/Users/agent/.ssh/authorized_keys`,
   owner `agent:staff`, modes 700/600) and an alias `mini-agent` in `~/.ssh/config`.
6. **Auto-login as agent.**
   ```bash
   sudo sysadminctl -autologin set -userName agent -password "$PW"
   ```
   **Gotcha:** this can fail with `SACSetAutoLoginPassword error:22` while still switching
   `autoLoginUser`. The machine would then stop at the login screen after a reboot. Check
   `sudo ls -l /etc/kcpassword`: if its timestamp did not change, write it yourself with
   `scripts/write-kcpassword.py` (feed the password on stdin, never as an argument).
7. **Agent environment**, as the agent user:
   ```bash
   cat > ~/.zprofile <<'EOF'
   eval "$(/opt/homebrew/bin/brew shellenv)"
   export PATH="$HOME/.local/bin:$PATH"
   EOF
   curl -fsSL https://claude.ai/install.sh | bash
   ```
8. **Reboot and verify.**
   ```bash
   ssh mini 'sudo shutdown -r now'
   # wait, then:
   ssh mini 'stat -f %Su /dev/console; tailscale status | head -1'   # expect: agent, and an IP
   ssh mini-agent 'whoami; sudo -n true; ls /Users/<admin>'         # expect: agent, sudo refused, permission denied
   ```

`/etc/kcpassword` is only lightly obfuscated, not encrypted. Anyone with root on the box can
recover the agent password. That is acceptable because the agent user is not an admin.
