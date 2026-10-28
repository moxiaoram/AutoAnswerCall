#!/usr/bin/env python3
"""Static source regression checks vs last known injected 1.7 release.
Checks do NOT prove device injection or successful linking; GitHub Actions compiles later.
"""
from pathlib import Path
import re
import sys
root=Path(__file__).resolve().parent.parent
checks=[]
def assert_check(ok,description):
    checks.append(bool(ok))
    print(f'{"PASS" if ok else "FAIL"} {description}')

make=(root/'Makefile').read_text()
control=(root/'control').read_text()
ci=(root/'.github/workflows/build.yml').read_text()
main=(root/'DYYY.xm').read_text()
probe=(root/'DYYYInjectionProbe.m').read_text()
for name in ('DYYY','AwemeVision'):
    plist=(root/f'{name}.plist').read_text()
    assert_check('com.ss.iphone.ugc.Aweme' in plist,f'{name} targets actual Douyin bundle ID')
    assert_check('Executables' not in plist and 'Classes' not in plist,f'{name} uses legacy Bundles-only filter')

assert_check('Package: com.local.awemevision.relaxin' in control,'new independent Debian identity')
assert_check('Version: 2.0.3' in control,'new version')
assert_check('Architecture: iphoneos-arm64e' in control,'RootHide package arch')
assert_check('Conflicts: com.huami.dyyy' in control,'do not load legacy package simultaneously')
assert_check('Provides: com.huami.dyyy' not in control,'do not impersonate old updates')
assert_check('firmware (>= 17.3)' in control,'iOS 17.3 minimum')
assert_check('SCHEME ?= roothide' in make and 'THEOS_PACKAGE_SCHEME := roothide' in make,'RootHide enforced')
assert_check('ARCHS = arm64' in make and 'DEB_ARCH = iphoneos-arm64e' in make,'dylib arch and DEB arch separate')
assert_check('-Wl,-undefined,error' in make and '-Wl,-undefined,dynamic_lookup' not in make,'strict linking: never emit dynamic_lookup imports')
assert_check('if (DYYYGetBool(@"DYYYUserAgreementAccepted")) {' not in main[main.index('%ctor {'):], 'hooks not gated on agreement at startup')
assert_check('    %init(DYYYSettingsGesture);' in main and 'if (!DYYYGetBool(@"DYYYDisableSettingsGesture")) {\n        %init' not in main,'settings gesture hook remains installed when toggled off')
assert_check('TARGET = iphone:clang:latest:17.3' in make,'iOS 17.3 deployment target')
assert_check('LEGACY_LOADER_NAME ?= 1' in make and 'TWEAK_NAME = DYYY' in make,'known-good 1.7 loader basename default')
assert_check('AWEMEVISION_STARTUP ?= full' in make and 'AWEMEVISION_COMPAT_BOOT' in make,'shipping startup enables default feature hooks')
assert_check('#if !AWEMEVISION_COMPAT_BOOT' in main and '%init;' in main,'default feature hook group installed in FULL; compat is diagnostic only')
assert_check('    %init(AutoPlay);' in main and '    %init(DYYYSettingsGesture);' in main,'explicit named Hook groups preserved')
assert_check('AwemeVision-early-load-2.0.3.log' in probe and 'O_WRONLY | O_CREAT | O_APPEND' in probe,'early constructor breadcrumb independent of UIKit')
assert_check('AwemeVision-injection-2.0.3.txt' in probe,'main-queue injection marker')
assert_check('https://github.com/roothide/theos.git' in ci and 'https://github.com/theos/sdks.git' in ci,'RootHide Theos and SDK from Git clones')
assert_check('beerpiss/theos-action' not in ci,'avoid previous exit 128 action')
assert_check('perl "$THEOS/bin/logos.pl" DYYY.xm' in ci,'Logos preprocessing test')
assert_check('gmake clean SCHEME=roothide' in ci and 'AWEMEVISION_STARTUP="$AWEMEVISION_STARTUP"' in ci,'clean CI builds chosen mode')
assert_check('python3 scripts/verify_relaxin_deb.py packages/*.deb' in ci,'inspect real DEB')
assert_check('AWEMEVISION_STARTUP' in ci and 'LEGACY_LOADER_NAME' in ci and 'PROBE_ONLY' in ci,'CI exposes 3 build switches')
assert_check('DYYYCommentInputContainerViewGroup' in main and '%init(CommentInputContainerView = ' not in main,'Swift Logos group init fix retained')
assert_check('[[AWELongPressPanelManager shareInstance]' not in (root/'DYYYGridLongPressPanel.m').read_text(),'dynamic long-press manager fix retained')
header=(root/'AwemeHeaders.h').read_text()
for cls in ('AWELongPressPanelTableViewController','AWEModernLongPressPanelTableViewController'):
    m=re.search(r'@interface\s+'+cls+r'\s*:\s*UIViewController(.*?)@end',header,re.S)
    assert_check(m is not None and 'NSArray *dataArray' in m.group(1),f'{cls} dataArray declared')

# Both compile targets expand from the same GNU make source list.
rows=re.findall(r'^\s*\$\(TWEAK_NAME\)_FILES\s*\+?=\s*(.*?)$',make,re.M)
files={f for row in rows for f in row.split()}
assert_check(len(files)>25 and all((root/f).exists() for f in files),'all current tweak sources exist')
assert_check('AwemeVision_LDFLAGS' not in make and 'AwemeVision_FILES' not in make,'generic target vars prevent stale dylib naming')
allcode='\n'.join(f.read_text() for ext in ('*.xm','*.m','*.h') for f in root.glob(ext))
for forbidden in ['DYYY_DEFAULT_ABTEST_URL','checkForRemoteConfigUpdate','DYYYRemoteConfigURL','latest/download/ABTestDataPatch_A.json']:
    assert_check(forbidden not in allcode,f'old remote update disabled: {forbidden}')
assert_check((root/'DYYYConstants.h').read_text().find('2.0.3')!=-1,'settings report v2.0.3')
print(f'\n{sum(checks)}/{len(checks)} checks passed (static only)')
sys.exit(0 if all(checks) else 1)
