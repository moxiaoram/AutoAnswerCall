#!/usr/bin/env python3
"""Static regression checks, NOT a substitute for Theos build or device test."""
from pathlib import Path
import zipfile, base64, math, collections
r=Path(__file__).resolve().parents[1]
manager=(r/'DYYYManager.m').read_text()
menu=(r/'DYYYLongPressPanel.xm').read_text()
settings=(r/'DYYYSettings.xm').read_text()
make=(r/'Makefile').read_text()
expect={
 'native model bitrate variants': all(x in manager for x in ('@"bitrateModels"','@"manualBitrateModels"','@"playAddr"','@"playURL"','@"h264URL"')),
 'dynamic safe KVC': 'AVSafeVideoValue' in manager and '@catch (NSException' in manager,
 'URL validation': 'NSURLComponents componentsWithString:text' in manager and 'parts.host.length' in manager,
 'download retry bound': 'index >= 5' in manager and 'AVTryDownloadVideo(choices, index + 1, audioURL)' in manager,
 'HTTP error rejection': all(x in manager for x in ('status < 200','status >= 300','application/json','text/html','finalizeDownloadWithID:downloadIDForTask')),
 'segment playlist skipped': all(x in manager for x in ('@"m3u8"','@"mpd"')),
 'copy current model first': 'AVVideoCandidates(aweme).count' in manager and 'resolveAndCopyVideoAddressForAweme:' in manager,
 'direct / legacy panel actions': menu.count('resolveAndCopyVideoAddressForAweme:') == 3,
 'optional API setting': '默认从视频模型直接提取地址，无需接口' in settings,
 'safe share link encoding': '[queryAllowed removeCharactersInString:@"&=+#?"]' in manager,
 'strict linkage': '-Wl,-undefined,error' in make and '-Wl,-undefined,dynamic_lookup' not in make,
 'rootHide / arm64': 'THEOS_PACKAGE_SCHEME := roothide' in make and 'ARCHS = arm64' in make,
 'real version': 'Version: 2.0.19' in (r/'control').read_text() and '2.0.19' in (r/'DYYYConstants.h').read_text(),
}
for k,v in expect.items(): print(('PASS' if v else 'FAIL')+': '+k)
print(f"{sum(expect.values())}/{len(expect)} checks passed (source only)")
if not all(expect.values()): raise SystemExit(1)
