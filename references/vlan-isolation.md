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
device name with `networksetup -listallhardwareports`). Otherwise it stays connected to both.

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

Internet is untouched: LAN_IN only covers traffic between internal networks. DNS and DHCP to the
gateway hit LAN_LOCAL, not LAN_IN, so they keep working.

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

## Verify

From the admin machine: `nc -z <mac-ip> 22` succeeds. From any other LAN device: it times out.
From the Mac: `curl -I https://example.com` works, `nc -z <some-lan-ip> 80` times out.

Remember the tailnet bypasses all of this (see `tailscale.md`).
