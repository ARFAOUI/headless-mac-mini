# Phase 0: first boot checklist (at the keyboard, once)

You need a display, keyboard and mouse exactly once. Hand this list to the human.

## Setup Assistant

- [ ] Create the **admin** account. Use a password you will remember; you will type it a few
      more times over SSH.
- [ ] **Skip the Apple ID** (optional, you can add it later). An Apple ID is not needed for a server.
- [ ] **Do not enable FileVault.** With FileVault on, the disk is locked after every reboot until
      someone types a password at the keyboard. A headless box would then sit at a pre-boot
      screen after every power cut.
      Tradeoff: the disk is not encrypted at rest. Only store things you would be OK losing if
      the box were stolen, or accept the risk.
- [ ] Skip Siri, Screen Time, analytics.

## System Settings

- [ ] **General > Sharing > Remote Login**: on. Note "Allow access for": the default is
      administrators only. (Phase 5 adds the agent user to it.)
- [ ] **General > Sharing > Screen Sharing**: on. This is your fallback when SSH is broken.
- [ ] **Energy** (or Battery > Options on some versions):
  - [ ] Prevent automatic sleeping when the display is off: on
  - [ ] Start up automatically after a power failure: on
  - [ ] Wake for network access: on
- [ ] **Users & Groups > Automatically log in as**: the admin user, for now. This is what makes
      user-level services start after a reboot. Phase 5 switches it to the agent user.
- [ ] **Network**: plug in Ethernet if you can. Wi-Fi works but is less reliable, and if you plan
      a VLAN, a wired switch port is far easier to put on a VLAN than a new SSID.
- [ ] **Software Update**: install pending updates now, while you are at the keyboard.

## Write down

- [ ] Admin username
- [ ] Ethernet **and** Wi-Fi MAC addresses (System Settings > Network > Details > Hardware).
      Use these for a DHCP reservation on your router instead of a static IP on the Mac.
      Note: macOS may use a *private (randomized)* Wi-Fi address. The Ethernet MAC is stable.
- [ ] The IP it currently has

## Optional hardware

- **HDMI dummy plug** (~10 EUR): only if agents will drive a GUI (browser automation, computer
  use, Screen Sharing at a real resolution). Pure CLI agents do not need it.
- **Smart plug**: lets you power-cycle a frozen box remotely. Combined with "start up after power
  failure" this is your last-resort reboot button.

Unplug the display. Everything else happens over SSH.
