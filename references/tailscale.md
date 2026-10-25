# Phase 4: Tailscale remote access

Use Tailscale (or your existing WireGuard) for access from outside the house. **Never forward
port 22 on the router.**

## Install as a system service (works with nobody logged in)

The Mac App Store / standalone Tailscale app runs per user and needs a GUI session. On a headless
box use the Homebrew formula, which runs `tailscaled` as a root launchd daemon at boot:

```bash
brew install tailscale
sudo brew services start tailscale
sudo tailscale up --hostname=mini
```

`tailscale up` prints a login URL. The human opens it and signs in. Then:

```bash
tailscale status        # shows the 100.x.y.z address
```

Regular `sshd` works over the tailnet: `ssh <user>@mini` (MagicDNS) or `ssh <user>@100.x.y.z`.
Tailscale SSH (`--ssh`) is an alternative but replaces key handling with Tailscale's identity;
pick one.

**The client machine has to be on the tailnet too.** If `ssh` to the 100.x address times out,
check that the admin's laptop or phone has Tailscale installed and signed in.

## Tailscale bypasses your router firewall

Traffic between tailnet devices is end-to-end WireGuard. It never passes through your VLAN rules.
If you isolated the Mac on a VLAN so that only one machine can reach it, the tailnet is a second
door. Lock it in the tailnet policy (admin console > Access controls). Example:

```jsonc
{
  "tagOwners": { "tag:agent-host": ["autogroup:admin"] },
  "grants": [
    // your own devices keep full access to each other (replaces the default allow-all rule)
    {"src": ["autogroup:member"], "dst": ["autogroup:self"], "ip": ["*"]},
    // your devices may reach the agent host on SSH and Screen Sharing only
    {"src": ["autogroup:member"], "dst": ["tag:agent-host"], "ip": ["tcp:22", "tcp:5900"]},
    // no rule has tag:agent-host as a source, so it cannot start connections to anything
  ],
  // keep the default "ssh" section if you use Tailscale SSH on your own devices
}
```

Delete or comment out the default `{"src": ["*"], "dst": ["*"], "ip": ["*"]}` rule, or the
restriction does nothing. `autogroup:self` (not `autogroup:member`) is the valid destination for
"my own devices".

**The policy only applies once the Mac carries the tag.** Until then it is one of "your own
devices" and keeps full access. Tag it either way:
- Admin console > Machines > the Mac's menu > **Edit ACL tags** > `tag:agent-host`. No sudo
  needed on the Mac.
- Or on the Mac: `sudo tailscale up --hostname=mini --advertise-tags=tag:agent-host`.

Tagging moves ownership from your user to the tag and **turns off key expiry**, which is what you
want for a machine nobody logs into.

Verify from both sides (pick a port that is open on your laptop, e.g. one `lsof -iTCP -sTCP:LISTEN`
shows on `*`):

```bash
ssh mini-ts 'echo ok'                                  # laptop -> Mac: works
ssh mini-ts 'nc -z -G 5 <laptop-100.x-ip> <port>'      # Mac -> laptop: must fail
nc -z <laptop-100.x-ip> <port>                         # control: the port is open
```

Also make sure no device
on the tailnet is a **subnet router** for your home LAN, or the Mac could reach the LAN through it.
