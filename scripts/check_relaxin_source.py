#!/usr/bin/env python3
"""Offline checks before GitHub Actions RootHide compilation (not a compile)."""
from pathlib import Path
import re
import sys
root = Path(__file__).resolve().parent.parent
failures = []
def check(ok, msg):
    print(('PASS' if ok else 'FAIL') + ' ' + msg)
    if not ok: failures.append(msg)

make = (root/'Makefile').read_text(encoding='utf8')
control = (root/'control').read_text(encoding='utf8')
plist = (root/'AwemeVision.plist').read_text(encoding='utf8')
workflow = (root/'.github/workflows/build.yml').read_text(encoding='utf8')
check('SCHEME ?= roothide' in make and 'THEOS_PACKAGE_SCHEME := roothide' in make,'RootHide-only build')
check(re.search(r'^ARCHS\s*=\s*arm64\s*$',make,re.M) is not None,'app dylib arm64')
check(re.search(r'^DEB_ARCH\s*=\s*iphoneos-arm64e\s*$',make,re.M) is not None,'RootHide deb architecture')
check('TARGET = iphone:clang:latest:17.3' in make,'iOS 17.3 deployment')
check('TWEAK_NAME = AwemeVision' in make,'independent tweak binary')
check('Package: com.local.awemevision.relaxin' in control and 'Version: 2.0.0' in control,'independent Debian identity')
check('Architecture: iphoneos-arm64e' in control,'Debian architecture')
check('Conflicts: com.huami.dyyy' in control and 'Provides: com.huami.dyyy' not in control,'prevent old/new concurrent injection; no old package identity')
check('firmware (>= 17.3)' in control and 'firmware (<< 17.4)' in control,'iOS 17.3 version range')
check('com.ss.iphone.ugc.Aweme' in plist and 'Aweme' in plist,'Douyin process filter')
check('theos-src: https://github.com/roothide/theos' in workflow and 'SCHEME=roothide' in workflow,'GitHub Actions rootHide theos')
check('scripts/verify_relaxin_deb.py' in workflow,'GitHub Actions real .deb validation')
rows = re.findall(r'^\s*AwemeVision_FILES\s*(?:\+?=)\s*(.*?)$',make,re.M)
if rows:
    files = list(dict.fromkeys(f for row in rows for f in row.split()))
    missing = [f for f in files if not (root/f).is_file()]
    check(not missing, f'configured {len(files)} source files exist'+(f' MISSING {missing}' if missing else ''))
else:
    check(False,'AwemeVision_FILES configured')
check('DYYY_FILES' not in make and 'DYYY_CFLAGS' not in make, 'no abandoned old Makefile build variables')

codefiles = list(root.glob('*.h')) + list(root.glob('*.m')) + list(root.glob('*.xm'))
source = '\n'.join(f.read_text(encoding='utf8') for f in codefiles)
for forbidden in ['DYYY_DEFAULT_ABTEST_URL', 'checkForRemoteConfigUpdate', 'DYYYCheckUpdate',
                  'DYYYRemoteConfigURL', 'DYYY_REMOTE_MODE_STRING', 'DYYY_REMOTE_CONFIG_FLAG_KEY',
                  'DYYY_REMOTE_CONFIG_CHANGED_NOTIFICATION', 'latest/download/ABTestDataPatch_A.json']:
    check(forbidden not in source, 'old remote updater absent: '+forbidden)
check('dataTaskWithURL:' not in (root/'DYYYABTestHook.xm').read_text(encoding='utf8'), 'ABTest hook does not fetch update URL')
check('2.0.0' in (root/'DYYYConstants.h').read_text(encoding='utf8'), 'settings show current version')
check(not (root/'DYYY.plist').exists(),'obsolete DYYY filter not packaged')

# Catch duplicate Cocoa Objective-C brackets from accidental text edits using cheap balance checks.
def bracket_count_ok(text):
    text = re.sub(r'/\*.*?\*/|//[^\n]*|@?"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'', '', text, flags=re.S)
    for opening,closing in [('(',')'),('{','}'),('[',']')]:
        count = 0
        for c in text:
            if c==opening: count+=1
            if c==closing:
                count-=1
                if count<0: return False
        if count: return False
    return True
for fname in ('DYYYABTestHook.xm','DYYYSettings.xm'):
    check(bracket_count_ok((root/fname).read_text(encoding='utf8')),f'balanced blocks in {fname}')
sys.exit(bool(failures))
