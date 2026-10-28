#!/usr/bin/env python3
"""Audit setting-key plumbing. This is static only, not an iOS runtime test."""
from pathlib import Path
import re,sys,json
root=Path(__file__).resolve().parent.parent
settings=(root/'DYYYSettings.xm').read_text()
ids=sorted(set(re.findall(r'@"identifier"\s*:\s*@"(DYYY\w+)"',settings)))
if len(ids)<200: raise SystemExit('FAIL: settings catalog unexpectedly truncated')
# Pages and support files are not proof of runtime support.
ui_files={'DYYYSettings.xm','DYYYSettingViewController.m','DYYYSystemSettingsViewController.m','DYYYSettingsHelper.m'}
implementations={p.name:p.read_text(errors='replace') for p in root.iterdir() if p.suffix in ('.m','.xm') and p.name not in ui_files}
missing=[]
ui_only=[]
by_key={}
for key in ids:
    linked=[name for name,text in implementations.items() if key in text]
    if not linked: ui_only.append(key)
    by_key[key]=linked
# Some entries are navigation-only, not runtime implementation toggles.
navigation={'DYYYDoubleTapMenuSettings','DYYYEntrance','DYYYHideTopBarBadge'}
missing=[x for x in ui_only if x not in navigation]
main=(root/'DYYY.xm').read_text()
make=(root/'Makefile').read_text()
checks={
 'settings_identifiers':len(ids),
 'non_ui_implementations':len(ids)-len(ui_only),
 'ui_only_entries':ui_only,
 'default_hooks_enabled': 'AWEMEVISION_STARTUP ?= full' in make and '#if !AWEMEVISION_COMPAT_BOOT' in main and '    %init;' in main,
 'strict_linking': '-Wl,-undefined,error' in make and '-Wl,-undefined,dynamic_lookup' not in make,
 'startup_not_agreement_gated':'if (DYYYGetBool(@"DYYYUserAgreementAccepted")) {' not in main[main.index('%ctor {'):],
 'gesture_hook_installed':'    %init(DYYYSettingsGesture);' in main,
 'sticker_group_is_preference_independent': 'DYYYForceDownloadEmotion") ||' not in main[main.index('%ctor {'):],
 'full_build_sources':len(re.findall(r'^\s*\$\(TWEAK_NAME\)_FILES\s*\+?=',make,re.M)),
}
(root/'SETTING_BINDINGS_AUDIT.json').write_text(json.dumps({'checks':checks,'keys':by_key},ensure_ascii=False,indent=2)+'\n')
for k,v in checks.items(): print(f'{k}: {v}')
if missing or not all(checks[k] for k in ('default_hooks_enabled','strict_linking','startup_not_agreement_gated','gesture_hook_installed','sticker_group_is_preference_independent')):
 print('FAIL: unaccounted setting keys or hook installation regression:',missing)
 sys.exit(1)
print('PASS: all non-navigation setting identifiers have non-UI source references (NOT proof of runtime behavior)')
