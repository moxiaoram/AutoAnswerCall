#!/usr/bin/env python3
"""CI preflight: reject the two regressions reported for 2.0.5.
Source checks are deliberately independent of Theos installation, which CI
fetches later. This does NOT claim the final DEB builds or loads on a device.
"""
from pathlib import Path
import re
import sys
root=Path(__file__).resolve().parent.parent
mk=(root/'Makefile').read_text()
ci=(root/'.github/workflows/build.yml').read_text()
failures=[]

def check(ok, msg):
    print(('PASS' if ok else 'FAIL') + ': ' + msg)
    if not ok: failures.append(msg)

expected={'Foundation','UIKit','AVFoundation','CoreMedia','CoreAudio','CoreGraphics','ImageIO','Photos','QuartzCore','MobileCoreServices'}
found=set()
for line in mk.splitlines():
    if re.match(r'^\s*\$\(TWEAK_NAME\)_FRAMEWORKS\s*[+:?]?=',line):
        found.update(line.split('=',1)[1].split())
check(expected.issubset(found),'Theos _FRAMEWORKS declares required frameworks')
check('AVFAudio' in re.findall(r'^\s*\$\(TWEAK_NAME\)_WEAK_FRAMEWORKS\s*=\s*(.*)$',mk,re.M)[0].split() if re.search(r'^\s*\$\(TWEAK_NAME\)_WEAK_FRAMEWORKS\s*=',mk,re.M) else False,'AVFAudio uses weak-framework variable')
for row in re.findall(r'^\s*\$\(TWEAK_NAME\)_LDFLAGS\s*\+?=\s*(.+)$',mk,re.M):
    pieces=row.split()
    check(not (set(pieces)&(expected|{'AVFAudio'})), '_LDFLAGS has no bare framework names: '+row)
check('-Wl,-undefined,error' in mk,'strict undefined symbol check remains enabled')
check('dynamic_lookup' not in '\n'.join(l for l in mk.splitlines() if '_LDFLAGS' in l and not l.strip().startswith('#')),'dynamic_lookup is not passed to linker')
check(bool(re.search(r'brew install\s+.*\bldid\b',ci)), 'GitHub Actions installs ldid')
check('command -v ldid' in ci, 'GitHub Actions checks for ldid before compiling')
check('command -v dpkg-deb' in ci, 'GitHub Actions checks for packaging tool')
check('git clone --depth 1 --recursive https://github.com/roothide/theos.git' in ci, 'GitHub Actions uses RootHide Theos')
print(f'{len(failures)} preflight failure(s)')
sys.exit(1 if failures else 0)
