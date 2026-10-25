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
  "acls": [
    // only the admin's own devices may reach the agent host, and only SSH + Screen Sharing
    { "action": "accept", "src": ["autogroup:member"], "dst": ["tag:agent-host:22,5900"] }
    // no rule lets tag:agent-host start connections to anything, so it cannot reach other devices
  ]
}
```

Then tag the Mac: `sudo tailscale up --advertise-tags=tag:agent-host`. Also make sure no device
on the tailnet is a **subnet router** for your home LAN, or the Mac could reach the LAN through it.
