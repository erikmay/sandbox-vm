#!/usr/bin/env python3
"""Render preseed.cfg and late.sh for one machine and pack them as an initrd overlay.

Usage: render.py HOSTNAME DISK ADMIN_HASH_FILE LUKS_FILE PUBKEY_FILE OUTDIR
  ADMIN_HASH_FILE: output of `openssl passwd -6 -stdin` (SHA-512 crypt of the admin password)
  LUKS_FILE:       the LUKS passphrase, no trailing newline
Writes OUTDIR/preseed.cfg and OUTDIR/late.sh (mode 600). The outputs contain secrets:
shred them after building the initrd. Never commit them.
"""
import os
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
host, disk, hashf, luksf, pubf, outdir = sys.argv[1:7]
admin_hash = Path(hashf).read_text().strip()
luks = Path(luksf).read_text().strip()
pub = " ".join(Path(pubf).read_text().split()[:3])

pre = (here / "preseed.cfg.tpl").read_text()
for k, v in {"__HOSTNAME__": host, "__DISK__": disk, "__ADMIN_HASH__": admin_hash, "__LUKS__": luks}.items():
    pre = pre.replace(k, v)
late = (here / "late.sh").read_text().replace("__PUBKEY__", pub).replace("__ADMIN_HASH__", admin_hash)
for text in (pre, late):
    assert "__" not in text.replace("$", ""), "unreplaced placeholder"

os.umask(0o077)
out = Path(outdir)
out.mkdir(parents=True, exist_ok=True)
(out / "preseed.cfg").write_text(pre)
(out / "late.sh").write_text(late)
print(f"wrote {out}/preseed.cfg and {out}/late.sh")
