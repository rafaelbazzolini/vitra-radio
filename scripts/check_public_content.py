#!/usr/bin/env python3
"""Check the committed tree, never local user preferences or excluded build caches."""
from pathlib import Path
import subprocess, sys, re
files = subprocess.check_output(['git', 'ls-files', '-z']).decode().split('\0')
errors = []
for name in filter(None, files):
    p = Path(name)
    if not p.is_file() or p.suffix in {'.png', '.jpg', '.icns', '.lock', '.ttf'}:
        continue
    if p.suffix in {'.jks', '.keystore', '.p12', '.mobileprovision'} or p.name in {'.env', 'key.properties', 'local.properties'}:
        errors.append(f'Private configuration tracked: {name}')
    try: text = p.read_text()
    except UnicodeDecodeError: continue
    # Detect user-specific filesystem paths; ignore only this check's own expressions.
    if name != 'scripts/check_public_content.py' and (re.search(r'/Users/[^/\s]+/(?:Library|Desenvolvimento|Desktop|Documents|Downloads)', text) or 'BEGIN PRIVATE KEY' in text):
        errors.append(f'Private path or private key: {name}')
if errors:
    print('\n'.join(errors)); sys.exit(1)
print('PUBLIC_CONTENT_OK: no tracked private configuration, private keys or user paths')
