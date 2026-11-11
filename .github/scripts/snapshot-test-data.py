#!/usr/bin/env python3
"""Record metadata and hashes of known default app data for CI comparison."""
import hashlib
import json
from pathlib import Path

home = Path.home()
paths = [home / 'Library/Application Support/desktop-pet',
         home / 'Library/Application Support/DesktopPet',
         home / 'Library/Preferences/com.bssm-oss.desktop-pet.plist']
result = {}
for root in paths:
    entries = [root] + (sorted(root.rglob('*')) if root.is_dir() else [])
    for path in entries:
        key = str(path.relative_to(home))
        if path.is_symlink():
            result[key] = {'symlink': str(path.readlink())}
        elif path.is_file():
            result[key] = {'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
        elif path.is_dir():
            result[key] = {'directory': True}
        else:
            result[key] = {'missing': True}
print(json.dumps(result, indent=2, sort_keys=True))
