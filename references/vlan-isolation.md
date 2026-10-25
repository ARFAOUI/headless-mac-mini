# Phase 6 (optional): isolate the Mac on its own VLAN

Goal: the Mac has full internet, **only the admin's machine** can reach it, and it cannot reach
anything else on the LAN. Written for UniFi (UCG/UDM/UDR, classic LAN_IN rules), but the rule
logic carries over to OPNsense, pfSense, MikroTik and others.

## Decide how it joins the VLAN

| Option | Notes |
|---|---|
| **Ethernet to a switch port** (recommended) | Set that port's native/untagged network to the new VLAN. Nothing to configure on the Mac. Most reliable. |
| New SSID mapped to the VLAN | Works, but the Mac has to rejoin Wi-Fi (SSH drops during the switch), and you broadcast one more network name. |
| Firewall rules only, stay on an existing VLAN | **Not isolation.** Devices on the same subnet talk directly at layer 2 without passing through the router firewall. |

After it is wired, **turn its Wi-Fi off** (`sudo networksetup -setairportpower en1 off`, check the
device name with `networksetup -listallhardwareports`). Do it right after the port moves to the
VLAN. While the Mac is on both, macOS may keep the **default route on Wi-Fi**: your SSH reaches it
over Ethernet, the replies leave over Wi-Fi, the router drops them, and SSH times out while ping
still works. Run the Wi-Fi-off command over the Wi-Fi address (the session will drop, that is
expected), then wait up to a minute for the route to settle on Ethernet.

## Moving the switch port (UniFi)

Set a port override on the switch device (`PUT rest/device/<switch-id>` with `port_overrides`):

```json
{"port_idx": 7, "name": "mini", "forward": "customize",
 "native_networkconf_id": "<isolated-network-id>", "tagged_vlan_mgmt": "block_all"}
```

`port_overrides` replaces the whole list: include existing overrides for other ports. The Mac
renews DHCP on the new VLAN within about a minute.

## Make the admin's IP stable

The allow rule matches the admin machine by IP. Give it a DHCP reservation. On a Mac with
**Private Wi-Fi Address = Rotating**, the MAC changes and so does the IP: set it to Fixed (or Off)
for the home network, or the allow rule silently stops matching.

## Order: rules first, then the network

Create the firewall rules **before** the VLAN exists, so there is no window where the new subnet
is wide open. Address-based rules (by CIDR) can be created before the network.

UniFi legacy firewall **allows inter-VLAN traffic by default**, so an explicit block is required.

| # | Ruleset | Action | Source | Destination | Why |
|---|---|---|---|---|---|
| 1 | LAN_IN | accept | (existing) established/related | any | Lets replies flow back. Usually already present at the top. |
| 2 | LAN_IN | accept | `<admin-ip>/32` | `<vlan-cidr>` | The one machine allowed in |
| 3 | LAN_IN | drop | any | `<vlan-cidr>` | Everyone else out |
| 4 | LAN_IN | drop | `<vlan-cidr>` | RFC1918 group | The Mac cannot start connections into the LAN |

Internet is untouched: LAN_IN only covers traffic between internal networks.

**LAN_IN does not cover the gateway itself.** Traffic addressed to the router (its UI on 443, SSH
on 22, on *any* of its interface IPs, e.g. 192.168.1.1 or 192.168.10.1) goes through LAN_LOCAL.
Without the rules below, the isolated Mac can still open your router's login page:

| # | Ruleset | Action | Source | Destination | Why |
|---|---|---|---|---|---|
| 5 | LAN_LOCAL | accept | `<vlan-cidr>` | gateway, tcp/udp 53 | DNS |
| 6 | LAN_LOCAL | accept | `<vlan-cidr>` | gateway, udp 67 | DHCP renewals |
| 7 | LAN_LOCAL | drop | `<vlan-cidr>` | gateway, all | No router UI/SSH from the isolated Mac |

Rule indexes must sit **above** any broad "allow trusted to X" rule. On UniFi OS the custom rule
index range starts at 20000.

## Create the network

- VLAN ID: e.g. 40, subnet e.g. 192.168.40.1/24 (UniFi API wants the gateway form `x.x.x.1/24`)
- DHCP on
- **mDNS off**, so it does not advertise into or discover your other VLANs
- Optional: add it to IDS/IPS monitored networks

## Reserve the Mac's IP

Pre-create a DHCP reservation for the Mac's **Ethernet** MAC on the new network, even before it is
plugged in. Then update the SSH aliases to the new IP.

## UniFi API notes (scripting this)

- Log in via `POST /api/auth/login`, then use `/proxy/network/api/s/<site>/...`
- Networks: `rest/networkconf`, rules: `rest/firewallrule`, groups: `rest/firewallgroup`,
  clients and reservations: `rest/user` (`use_fixedip`, `network_id`, `fixed_ip`)
- Back up `networkconf`, `firewallrule` and `user` to JSON before writing
- If the controller sits behind a local VPN on your Mac, bind requests to the LAN interface's
  source IP, or the VPN may route the traffic away

## Intrusion prevention can lock you out

If IDS/IPS runs in blocking mode on your main network, **many new SSH connections in a short time
look like an SSH scan** (Suricata `emerging-scan`) and the router blocks your machine's SSH to the
Mac, usually for a few minutes. Symptom: SSH times out, ping and Screen Sharing still work. On
UniFi it shows in the system log as `THREAT_BLOCKED_KNOWN_SOURCE_CLIENT`
(`POST /proxy/network/v2/api/site/default/system-log/all`).

Avoid it rather than weakening IPS:
- Use SSH connection sharing for the Mac's aliases (see `ssh-access.md`), so scripts reuse one
  connection.
- Never loop `nc` or `ssh` probes. When waiting for the Mac, probe once a minute.
- If blocked: wait, or unblock the entry in the router's threat log. An IPS allow-list entry for
  your machine works too, but it switches inspection off for that host.

## Verify

From the admin machine: `nc -z <mac-ip> 22` succeeds. From any other LAN device: it times out.
From the Mac: `curl -I https://example.com` works, `nc -z <some-lan-ip> 80` times out.

Remember the tailnet bypasses all of this (see `tailscale.md`).
