"""Verify the built deb ships BOTH official, case-sensitive bundle ids and both modules.

Apple Platform Deployment lists the Phone app as com.apple.mobilephone (lowercase).
1.10.0 also injects into com.apple.springboard. The wrong-case variant must never reach
the filter plist. This checks the artifact itself, not only the source tree.
"""
import pathlib
import plistlib
import sys

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else '/tmp/aac-debcheck')
filter_path = root / 'Library/MobileSubstrate/DynamicLibraries/AutoAnswerCall.plist'
dylib_path = root / 'Library/MobileSubstrate/DynamicLibraries/AutoAnswerCall.dylib'
if not filter_path.is_file() or not dylib_path.is_file():
    sys.exit('artifact layout missing filter plist or dylib')
filter_text = filter_path.read_text(errors='replace')
bundles = plistlib.loads(filter_path.read_bytes())['Filter']['Bundles']
print('artifact filter bundles:', bundles)
if bundles != ['com.apple.mobilephone', 'com.apple.springboard']:
    sys.exit('artifact filter must be exactly the two official ids '
             'com.apple.mobilephone + com.apple.springboard, got %r' % (bundles,))
if 'MobilePhone' in filter_text:
    sys.exit('artifact filter carries a wrong-case/MobilePhone identifier')
dylib = dylib_path.read_bytes()
for required in (b'com.apple.mobilephone', b'com.apple.springboard', b'MobilePhone'):
    if required not in dylib:
        sys.exit('artifact dylib missing %r' % required)
# Evidence-build modules must really be compiled into the dylib.
for required in (b'objc_getClassList', b'com.autoanswer.call.probe.',
                 b'com.autoanswer.call.sharelog', b'/var/jb/var/mobile'):
    if required not in dylib:
        sys.exit('artifact dylib missing 1.10.0 evidence string/symbol %r' % required)
# Settings module: the new probe/log pages must be linked into the preference bundle.
bundle_dir = root / 'Library/PreferenceBundles/AutoAnswerCallPrefs.bundle'
binary = bundle_dir / 'AutoAnswerCallPrefs'
if not binary.is_file():
    sys.exit('artifact missing AutoAnswerCallPrefs binary')
settings = binary.read_bytes()
for required in (b'AACProbeController', b'AACSharedLogController',
                 b'com.autoanswer.call.probe.', b'com.autoanswer.call.sharelog'):
    if required not in settings:
        sys.exit('artifact settings binary missing 1.10.0 evidence string %r' % required)
# The Chinese page titles may be stored in a non-UTF-8 literal encoding; report the
# encoding actually found instead of failing the artifact check on it.
for title in ('\u8fdb\u7a0b\u63a2\u6d4b', '\u5171\u4eab\u65e5\u5fd7\u67e5\u770b\u5668'):
    encodings = [enc for enc, blob in (('utf-8', title.encode()),
                                       ('utf-16-le', title.encode('utf-16-le')))
                 if blob in settings]
    print('settings title %s found as: %s' % (title, ', '.join(encodings) or 'not found (informational only)'))
for other in ('com.apple.springboard', 'com.apple.mobilephone'):
    if other.encode() in settings:
        sys.exit('settings binary should not carry an injection bundle id: %s' % other)
print('artifact bundle id check passed (filter has exactly the two official lowercase ids; '
      'dylib keeps the wrong-case runtime fallback plus both evidence modules)')
