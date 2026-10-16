"""Verify the built deb ships the four configured bundle ids, every host module, the 1.13.0
relaxed hook ABI strategy, the corrected CallKit error mapping and the run-log share surface.

Apple Platform Deployment lists the Phone app as com.apple.mobilephone (lowercase). 1.13.0
injects into com.apple.mobilephone, com.apple.springboard, com.apple.InCallService and
com.apple.incallservice; the two InCall spellings only cover case differences for the same
modern host that presents the in-call UI. The wrong-case com.apple.MobilePhone must never
reach the filter plist. Both answer hosts discover the real incoming-call UI classes at
runtime (no hardcoded private class name) and only one of them may answer. This checks the
artifact itself, not only the source tree.
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
expected = ['com.apple.mobilephone', 'com.apple.springboard',
            'com.apple.InCallService', 'com.apple.incallservice']
if bundles != expected:
    sys.exit('artifact filter must be exactly %r (four ids: phone + springboard + the two '
             'InCall case spellings), got %r' % (expected, bundles))
if 'MobilePhone' in filter_text:
    sys.exit('artifact filter carries a wrong-case/MobilePhone identifier')
dylib = dylib_path.read_bytes()


def present(blob, text):
    """ObjC string literals that contain non-ASCII text are stored in the target's wide
    encoding (UTF-16), so every check accepts UTF-8 and both UTF-16 byte orders and
    reports which one actually matched."""
    found = [enc for enc in ('utf-8', 'utf-16-le', 'utf-16-be') if text.encode(enc) in blob]
    if found:
        print('  found %r as %s' % (text, ', '.join(found)))
    return bool(found)


# Bundle ids and the runtime fallbacks: the lowercase phone rule holds for the filter, the
# wrong-case id survives only as a runtime compatibility string.
for required in ('com.apple.mobilephone', 'com.apple.springboard', 'MobilePhone',
                 'com.apple.InCallService', 'com.apple.incallservice', 'InCallService'):
    if not present(dylib, required):
        sys.exit('artifact dylib missing bundle/process fallback string %r' % required)
# Evidence-build modules must really be compiled into the dylib.
for required in ('objc_getClassList', 'com.autoanswer.call.probe.',
                 'com.autoanswer.call.sharelog', '/var/jb/var/mobile'):
    if not present(dylib, required):
        sys.exit('artifact dylib missing 1.10.0 evidence string/symbol %r' % required)
# 1.11.0/1.12.0: the runtime discovery/hook answer path and the host table must really be
# compiled into the dylib, and it must not carry a hardcoded guessed private class name.
# 1.13.0: the hook is installed through MSHookMessageEx (ElleKit / substrate compat, resolved
# with dlsym), with method_setImplementation as the documented fallback that keeps the same
# saved-original-IMP contract. The previous artifact check FORBADE MSHookMessageEx; that
# assertion is now inverted on purpose, because it is the intended hooking primitive of this
# version and its symbol name is expected to be present as the dlsym string.
required_discovery = ('method_setImplementation', 'class_copyMethodList', 'discovery.txt',
                      'runtime-discovered', 'AACSBEnv',
                      'LOG-ONLY primary path',
                      'answer-ish method invoked through our dynamic hook',
                      'MSHookMessageEx', 'ElleKit/substrate',
                      'INVOKABLE_BY_INVOCATION', 'INVOKED_BY_INVOCATION', 'CAPTURED',
                      'answerPaths=', 'invokableSkipped=', 'globalPassScanned=',
                      'global-call-scan', '0args+BOOL', '0args+object')
missing_discovery = [item for item in required_discovery if not present(dylib, item)]
print('dylib runtime discovery strings found: %d/%d'
      % (len(required_discovery) - len(missing_discovery), len(required_discovery)))
if missing_discovery:
    sys.exit('artifact dylib missing discovery/hook strings: %r' % (missing_discovery,))
# 1.12.0: per-host probe/pong/discovery names, the single-owner role table and the decoded
# CallKit error meanings must exist in the dylib.
required_host = ('com.autoanswer.call.probe.incall', 'com.autoanswer.call.pong.incall',
                 'aac-incall.discovery.txt',
                 'com.autoanswer.call.probe.springboard', 'com.autoanswer.call.pong.springboard',
                 'aac-springboard.discovery.txt',
                 'com.autoanswer.call.owner.',
                 'InCallService(2) > SpringBoard(1)',
                 'observer only, answer owned by',
                 'HOOK_SUMMARY', 'HOOK_ENTRY', 'INVOKE_SUMMARY', 'INVOKE_ENTRY', 'CONCLUSIVE',
                 'HOOKED_TOTAL',
                 'com.apple.CallKit.error.requesttransaction', 'unknownCallUUID',
                 # 1.13.0: the corrected mapping — code 1 is unentitled, not unknownCallUUID
                 'code 1 = unentitled', 'code 4 = unknownCallUUID')
missing_host = [item for item in required_host if not present(dylib, item)]
print('dylib 1.12.0 host-table/single-owner strings found: %d/%d'
      % (len(required_host) - len(missing_host), len(required_host)))
if missing_host:
    sys.exit('artifact dylib missing host-table/single-owner strings: %r' % (missing_host,))
# MSHookMessageEx is deliberately NOT forbidden any more (see above). The remaining entries are
# guessed private class names / dynamic class lookup, which would mean the answer path is not
# runtime-discovered.
for forbidden in (b'SBIncomingCallViewController', b'SBCallAlertViewController',
                  b'IncomingCallViewController', b'NSClassFromString'):
    if forbidden in dylib:
        sys.exit('artifact dylib must not hardcode %r: the answer path is runtime-discovered'
                 % forbidden)

# Settings module: the probe/log pages and the per-host discovery labels must be linked
# into the preference bundle.
bundle_dir = root / 'Library/PreferenceBundles/AutoAnswerCallPrefs.bundle'
binary = bundle_dir / 'AutoAnswerCallPrefs'
if not binary.is_file():
    sys.exit('artifact missing AutoAnswerCallPrefs binary')
settings = binary.read_bytes()
required_settings = ('AACProbeController', 'AACSharedLogController',
                     'com.autoanswer.call.probe.', 'com.autoanswer.call.sharelog',
                     'aac-incall.discovery.txt', 'aac-springboard.discovery.txt',
                     'com.autoanswer.call.pong.incall', 'com.autoanswer.call.pong.springboard',
                     'runtime-discovered', 'InCallService',
                     # 1.13.0 run-log export / share surface
                     'AACLogExportController', 'AutoAnswerCall-export-',
                     'settings.log', 'configuration.plist', 'call-records.txt',
                     'shared-prefs-fallback.txt', 'probe-companion.txt', 'audio-library.plist',
                     '运行导出报告', '运行日志导出报告')
missing_settings = [item for item in required_settings if not present(settings, item)]
print('settings binary evidence strings found: %d/%d'
      % (len(required_settings) - len(missing_settings), len(required_settings)))
if missing_settings:
    sys.exit('artifact settings binary missing evidence strings: %r' % (missing_settings,))
# The Chinese page titles may be stored in a non-UTF-8 literal encoding; report the
# encoding actually found instead of failing the artifact check on it.
for title in ('\u8fdb\u7a0b\u63a2\u6d4b', '\u5171\u4eab\u65e5\u5fd7\u67e5\u770b\u5668'):
    encodings = [enc for enc, blob in (('utf-8', title.encode()),
                                       ('utf-16-le', title.encode('utf-16-le')))
                 if blob in settings]
    print('settings title %s found as: %s' % (title, ', '.join(encodings) or 'not found (informational only)'))
for other in ('com.apple.springboard', 'com.apple.mobilephone'):
    if present(settings, other):
        sys.exit('settings binary should not carry an injection bundle id: %s' % other)
print('artifact bundle id check passed (filter has exactly the four configured ids; the '
      'dylib keeps the wrong-case runtime fallback, the evidence modules, the '
      'host-parameterised InCallService+SpringBoard runtime-discovered answer path with its '
      'single-owner rule, the 1.13.0 relaxed hook ABI strategy (MSHookMessageEx + per-return-'
      'type thunks + bounded NSInvocation candidates) with per-method outcome reporting, the '
      'corrected CallKit error mapping, the run-log export/share surface, and hardcodes no '
      'private class name)')
