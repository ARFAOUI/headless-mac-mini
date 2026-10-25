#!/usr/bin/env python3
"""Write /etc/kcpassword (macOS auto-login password) from a password read on stdin.

Use when `sysadminctl -autologin set` fails (e.g. SACSetAutoLoginPassword error:22).
Run as root on the Mac:  printf '%s\n' "$PW" | sudo python3 write-kcpassword.py
Also set the user:       sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser <user>

The file is XOR-obfuscated with Apple's fixed key, not encrypted. Root can recover the password.
"""
import os
import sys

KEY = [0x7D, 0x89, 0x52, 0x23, 0xD2, 0xBC, 0xDD, 0xEA, 0xA3, 0xB9, 0x1F]

pw = sys.stdin.readline().rstrip("\n").encode()
if not pw:
    sys.exit("empty password on stdin")
# always NUL-terminated, padded to a multiple of 12 bytes
padded = pw + bytes((len(pw) // 12 + 1) * 12 - len(pw))
data = bytes(b ^ KEY[i % len(KEY)] for i, b in enumerate(padded))

fd = os.open("/etc/kcpassword", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
os.write(fd, data)
os.close(fd)
os.chown("/etc/kcpassword", 0, 0)
print(f"/etc/kcpassword written ({len(data)} bytes)")
