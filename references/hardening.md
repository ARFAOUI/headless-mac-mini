# Phase 8: hardening and cleanup

Ask the human before each of these.

## Disable SSH password login

Only after key login works for **every** account you need, verified in a fresh session.

```bash
sudo tee /etc/ssh/sshd_config.d/200-keys-only.conf >/dev/null <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
sudo sshd -t && sudo launchctl kickstart -k system/com.openssh.sshd
```

Keep your current session open, then test from a new terminal:

```bash
ssh -o BatchMode=yes mini true && echo key-ok
ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password mini true   # must fail
```

If keys stop working, Screen Sharing is the way back in.

## Remove the temporary sudoers file

```bash
sudo rm /etc/sudoers.d/zz-setup
sudo -k; sudo -n true 2>&1   # expect: a password is required
```

## Checklist

- [ ] Firewall on
- [ ] Password SSH off, root login off
- [ ] Temporary NOPASSWD sudoers removed
- [ ] Agent user is not in `admin`: `dseditgroup -o checkmember -m agent admin`
- [ ] Admin home is `700`
- [ ] No router port forwards to the Mac; remote access only through Tailscale/WireGuard
- [ ] Tailnet policy limits who can reach the Mac
- [ ] Automatic macOS security updates on: `sudo softwareupdate --schedule on`
- [ ] Smart plug or other way to power-cycle remotely
