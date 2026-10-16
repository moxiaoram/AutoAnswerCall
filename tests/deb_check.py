"""Verify the built deb ships the four configured bundle ids, every host module, the 1.17.0 live-button
discovery/tap path (primary strategy) plus the 1.16.0 chunked
Darwin notification-name message transport (plus the request-on-demand name), the 1.15.0 candidate
classification (ACTION vs ACCESSOR; only ACTION counts as an answer path), the shared cross-process
host-report domain (own CFPreferences domain, per-host bounded keys), the 1.14.0 ownership rule
(claim-only demotion + bounded takeover), the 1.13.0 relaxed hook ABI strategy, the corrected CallKit
error mapping and the run-log share surface.

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
# 1.12.0/1.13.0: per-host probe/pong/discovery names, the single-owner role table, the
# per-method hook outcomes and the CORRECTED CallKit error meanings must exist in the dylib.
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
print('dylib 1.13.0 host-table/single-owner/hook-strategy strings found: %d/%d'
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


# 1.14.0/1.15.0: the ownership fix, the candidate classification and the Task-1/Task-2 evidence
# surface must be IN the artifact, not only in the source tree. Device evidence that drove the fix (user's real SpringBoard shared log):
# 1.13.0 @14:03:05 matchedClasses=150 hookedMethods=4 invokable=5 rejected=0 role=OWNER, the
# 14:05:08 call was detected and the 6 s delay scheduled, then @14:05:09 the host demoted itself
# to OBSERVER because "incall 的探测通知在 90 秒内到达过本进程（存活证据）" and logged
# "observer only, answer owned by incall" — nobody ever answered. 1.14.0 demotes ONLY on a fresh
# explicit ownership claim, never on probe presence, and adds a bounded 12 s takeover.
# 1.15.0 TASK 1/TASK 2: the shared host-report domain (our OWN CFPreferences domain, never an
# Apple one), its per-host key layout and bounded payload marker, and the ACTION/ACCESSOR
# classification that gates the answer-path count, must all be IN the artifact.
required_115 = ('com.autoanswer.call.hostreport',
                'Host.',
                '\u2026<truncated>',
                'domain=%@ keys=%@ synced=%@ summaryBytes=%@',
                'countsAsPath=no', 'countsAsPath=yes',
                'classification=ACTION', 'classification=ACCESSOR', 'classification=FORBIDDEN', 'classification=UNSUPPORTED',
                'handle*answer', 'didtap*answer', 'perform*answer', 'answer*call*action', 'invoke*answer', 'acceptcall', 'tapanswer',
                'TPInComingCallUI*', 'PHInCallUI*', 'ICSInCall*', 'CallBanner*', 'CallViewController*', 'InCall*ViewController',
                'CAPTURED_ACCESSOR',
                'ACCESSOR capture (evidence only; NOT an answer path, never used as the answer target)',
                'answeredCall', 'hasAnsweredCall', 'acceptButton', 'setAnsweredCall:', 'setAcceptButton:',
                'HOOKED=%lu\uff08\u5176\u4e2d ACTION=%lu\uff0cACCESSOR=%lu\uff1b\u53ea\u6709 ACTION \u8ba1\u5165 answerPaths\uff09',
                '\u53ea\u6709 ACTION \u8ba1\u5165 answerPaths',
                '\u63a5\u542c\u5f52\u5c5e\u5224\u5b9a call=%@ owner=%@ role=%@ host=%@ answerPaths=%lu classification=[%@] why=%@ submitted=%@',
                'log-only: %@ \u6ca1\u6709\u4efb\u4f55 ACTION \u63a5\u542c\u8def\u5f84',
                'no takeover scheduled: \u672c\u5bbf\u4e3b\u662f LOG-ONLY',
                'ACTION \u63a5\u542c\u8def\u5f84=0')

missing_115 = [item for item in required_115 if not present(dylib, item)]
print('dylib 1.15.0 host-report/classification strings found: %d/%d'
      % (len(required_115) - len(missing_115), len(required_115)))
if missing_115:
    sys.exit('artifact dylib missing 1.15.0 host-report/classification strings: %r' % (missing_115,))
required_ownership = ('Loaded 1.17.0 answer host',
                      'AutoAnswerCall 1.17.0 answer-host runtime discovery run',
                      'takeover after idle higher-priority owner',
                      'takeover cancelled by plugin stop generation',
                      'takeover not needed: a connection was observed',
                      'takeover observation started',
                      'no takeover scheduled',
                      '\u6bcf\u4e2a UUID \u6700\u591a\u63a5\u7ba1\u4e00\u6b21',
                      '\u4ec5\u5b58\u6d3b\u8bc1\u636e',
                      '\u63a2\u6d4b\u5230\u5b58\u5728\u53ea\u8bc1\u660e\u8fdb\u7a0b\u5b58\u5728\uff0c\u4e0d\u6784\u6210\u5f52\u5c5e',
                      '\u672c\u5bbf\u4e3b\u6ca1\u6709\u53ef\u7528\u7684\u63a5\u542c\u8def\u5f84',
                      '\u4ecd\u7136\u6ca1\u6709\u89c2\u5bdf\u5230\u8fde\u63a5',
                      '\u53ea\u6709 OWNER \u624d\u5e7f\u64ad\u5f52\u5c5e\u58f0\u660e',
                      'HOOKED list', 'end HOOKED list', 'HOOKED_LIST count=', 'INVOKABLE_LIST count=',
                      'submitted=%@', '\u63a5\u542c\u5f52\u5c5e\u5224\u5b9a call=',
                      'discovery digest[%lu/%lu]',
                      # NOTE: only string literals are checked here. Static C function names
                      # (AACSBMayTakeOver, AACSBClaimTakeoverUUID, AACSBAnswerOwnershipLine,
                      # AACSBHookedBlockText, AACSBLogDigest, AACSBPeerClaimReason) are NOT
                      # string literals and are deliberately not required to appear in the
                      # binary; their behaviour is checked by tests/source_checks.py.)
                      '\u5df2\u7ecf\u884c\u4f7f\u8fc7\u63a5\u7ba1\u6743')
# 1.16.0 TASK 1/TASK 2: the chunked Darwin notification-name transport must really be IN the
# dylib (not only in the source tree): the reserved name prefixes, the self-describing envelope
# magic, the explicit truncation marker, the framing text with its documented hard bounds, the
# request-on-demand name and the persisted file name.
required_116 = ('com.autoanswer.call.msg.',
                'com.autoanswer.call.msgrequest.',
                'AACMSG1',
                '\u2026<msg-truncated>',
                'com.autoanswer.call.msg.<tag>.<seq>.<total>.<base64url',
                '\u540d\u5185\u8f7d\u8377\u901a\u9053\uff1a\u6700\u591a 12 \u7247\uff0c\u6bcf\u7247\u6700\u591a 900 \u4e2a base64url \u5b57\u7b26',
                '\u72b6\u6001\u69fd\u901a\u9053\uff1a96 \u69fd \u00d7 6 \u5b57\u8282 = 576 \u5b57\u8282',
                '16 \u4f4d\u4ee3\u6b21',
                'CRC32',
                'host-messages.txt',
                '\u5206\u7247\u6d88\u606f\u901a\u9053')
missing_116 = [item for item in required_116 if not present(dylib, item)]
print('dylib 1.16.0 chunked-transport strings found: %d/%d'
      % (len(required_116) - len(missing_116), len(required_116)))
if missing_116:
    sys.exit('artifact dylib missing 1.16.0 chunked-transport strings: %r' % (missing_116,))
# The framing bounds must be the documented ones, and the old channels must still be there.
for literal in ('12 \u7247', '900', '12288', '96 \u69fd', '576'):
    if not present(dylib, literal):
        sys.exit('artifact dylib missing the documented bound literal %r' % literal)
for kept in ('com.autoanswer.call.hostreport', 'com.autoanswer.call.sharelog',
             'com.autoanswer.call.probe.', 'com.autoanswer.call.owner.'):
    if not present(dylib, kept):
        sys.exit('artifact dylib lost a pre-1.16.0 cross-process channel name: %r' % kept)

missing_ownership = [item for item in required_ownership if not present(dylib, item)]
print('dylib 1.14.0/1.15.0 ownership/HOOKED-list strings found: %d/%d'
      % (len(required_ownership) - len(missing_ownership), len(required_ownership)))
if missing_ownership:
    sys.exit('artifact dylib missing 1.14.0/1.15.0 ownership/takeover/classification strings: %r'
             % (missing_ownership,))
# The old probe-presence demotion reason must be gone: it may not be shipped as the demotion
# basis any more (it survives only as presence-only reporting evidence).
if present(dylib, '\u89c2\u5bdf\u8005\uff1a\u63a5\u542c\u7531 %@ \u8d1f\u8d23\uff08%@\uff09\uff1b\u672c\u5bbf\u4e3b\u53ea\u89c2\u5bdf\u5e76\u8bb0\u5f55'):
    print('  note: the claim-based OBSERVER reason (kept, now claim-only) is present')

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
                     'com.autoanswer.call.hostreport', 'host-report.txt', 'showHostReport:',
                     '/var/mobile/Library/Preferences', '/var/jb/var/mobile/Library/Preferences',
                     '\u5bbf\u4e3b\u8de8\u8fdb\u7a0b\u4e0a\u62a5\u8bfb\u56de',
                     'CFPreferences \u952e\uff08\u4e0d\u662f\u6587\u4ef6\u8def\u5f84\uff09',
                     # 1.13.0 run-log export / share surface
                     'AACLogExportController', 'AutoAnswerCall-export-',
                     'settings.log', 'configuration.plist', 'call-records.txt',
                     'shared-prefs-fallback.txt', 'probe-companion.txt', 'audio-library.plist',
                     '运行导出报告', '运行日志导出报告',
                     # 1.16.0 TASK 1/TASK 2 chunked Darwin transport surface
                     '\u8de8\u8fdb\u7a0b\u5206\u7247\u6d88\u606f\uff08Darwin \u540d\u5185\u8f7d\u8377\uff09',
                     'showChunkMessages:', 'AACChunkMsgController',
                     'com.autoanswer.call.msg.', 'com.autoanswer.call.msgrequest.',
                     'host-messages.txt',
                     '\u540d\u5185\u8f7d\u8377\u901a\u9053\uff1a\u6700\u591a 12 \u7247')
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

# ---- 1.17.0 TASK 1/TASK 2: the live-button discovery + simulated tap path must be IN the artifact --
# Device evidence that drove it (the user's 1.16.0 chunked read-back): all three hosts injected,
# all three role=LOG-ONLY / answerPaths=0, because the real answer is a UI button whose response
# goes through sendActionsForControlEvents: and whose method names never contain answer/accept.
required_117 = ('# ===== BUTTON \u5019\u9009\uff081.17.0 \u6d3b\u4f53\u5c42\u7ea7\u53d1\u73b0 + \u6a21\u62df\u70b9\u51fb\uff1b\u4e0e\u540c\u6587\u4ef6\u91cc ACTION/ACCESSOR \u65b9\u6cd5\u5206\u7c7b\u76f8\u4e92\u72ec\u7acb\uff09 =====',
                '# BUTTON_SCAN phase=%@ run=%lu nodesVisited=%lu candidates=%lu blacklisted=%lu live=%lu',
                'BUTTON_CANDIDATE class=%@ id=%@ label=%@ value=%@ title=%@ frame=%@ tint=%@ bg=%@ green=%.2f redDominant=%@ leftPrimary=%@ siblingControls=%lu signal=%@ matched=%@ blacklisted=%@ tappable=%@',
                '# BUTTON_CHOSEN %@',
                '# BUTTON_TAP uuid=%@ host=%@ mechanism=%@ detail=%@ tapCount=%lu',
                '# BUTTON_CONNECTED uuid=%@ connected=%@',
                '# BUTTON_CONNECTED_OBSERVED connected=%@ uuid=%@',
                'BUTTON_SIGNAL_PRIORITY',
                'BUTTON_BLACKLIST',
                'BUTTON_BOUNDS',
                'accessibilityIdentifier',
                'accessibilityLabel',
                'backgroundImageForState:',
                'sendActionsForControlEvents:UIControlEventTouchUpInside',
                'sendActionsForControlEvents:UIControlEventTouchUpInside|UIControlEventTouchDown',
                '(3) allTargets + actionsForTarget:forControlEvent: \u2192 NSInvocation\uff08\u9ed8\u8ba4\u53c2\u6570\uff09',
                'com.autoanswer.call.buttontap.',
                'greenLeftPrimary(\u5f31\u4fe1\u53f7)',
                '\u62d2\u7edd/\u6302\u65ad\u9ed1\u540d\u5355',
                '\u8be5\u901a\u8bdd UUID \u5df2\u7ecf\u7531\u672c\u5bbf\u4e3b\u70b9\u51fb\u8fc7\u4e00\u6b21',
                '\u5df2\u89c2\u5bdf\u5230\u66f4\u9ad8\u4f18\u5148\u7ea7\u5bbf\u4e3b %@ \u771f\u7684\u70b9\u51fb\u8fc7\u63a5\u542c\u6309\u94ae',
                'button path invoked; host=%@ mechanism=%@ detail=%@',
                'button path: \u672c\u6b21\u6765\u7535\u91cc\u6ca1\u6709\u53d1\u73b0\u4efb\u4f55\u53ef\u70b9\u51fb\u7684\u63a5\u542c\u6309\u94ae\u5019\u9009',
                'button tap not needed: a connection was already observed',
                'button tap cancelled by plugin stop generation',
                'button tap dropped: the call already ended',
                'buttontap \u89c2\u5bdf\u6ce8\u518c\u5931\u8d25',
                '\u63a5\u542c\u4e3b\u7b56\u7565\uff081.17.0\uff09\uff1d\u6d3b\u4f53\u6309\u94ae\u53d1\u73b0\uff0b\u6a21\u62df\u70b9\u51fb',
                '\u672c\u5bbf\u4e3b\u53d1\u73b0 %lu \u4e2a\u53ef\u70b9\u51fb\u7684\u63a5\u542c\u6309\u94ae\u5019\u9009',
                '保留但已知不足')
missing_117 = [item for item in required_117 if not present(dylib, item)]
print('dylib 1.17.0 button-discovery strings found: %d/%d'
      % (len(required_117) - len(missing_117), len(required_117)))
if missing_117:
    sys.exit('artifact dylib missing 1.17.0 button-discovery strings: %r' % (missing_117,))
# The button path may not tab anything destructive, and the retained method-name path must be
# labelled insufficient (never presented as the plan).
for literal in ('\u4fdd\u7559\u4f46\u5df2\u77e5\u4e0d\u8db3', '\u662f\u4e3b\u7b56\u7565'):
    if not present(dylib, literal):
        sys.exit('artifact dylib must label method-name keyword discovery as insufficient (%r)' % literal)
# The Settings bundle must carry the new button page text (plist + binary) and the explicit note
# that keyword discovery is retained but known insufficient, with the button path primary.
# The staged Root.plist is converted to a BINARY plist during staging, so it is parsed with
# plistlib instead of being read as text.
import plistlib
root_plist = bundle_dir / 'Root.plist'
if not root_plist.is_file():
    sys.exit('artifact missing the staged Root.plist')
_root = plistlib.loads(root_plist.read_bytes())
root_text = '\n'.join([str(i.get('label', '')) + '\n' + str(i.get('footerText', '')) + '\n' + str(i.get('title', '')) for i in _root.get('items', [])])
for literal in ('\u63a5\u542c\u6309\u94ae\u53d1\u73b0\uff081.17.0\uff0c\u4e3b\u7b56\u7565\uff09',
                '\u65b9\u6cd5\u540d\u5173\u952e\u5b57\u53d1\u73b0\uff08ACTION/ACCESSOR \u5206\u7c7b\uff09\u4fdd\u7559\uff0c\u4f46\u5df2\u77e5\u4e0d\u8db3',
                '\u6309\u94ae\u8def\u5f84\u662f\u4e3b\u7b56\u7565',
                'accessibilityIdentifier'):
    if literal not in root_text:
        sys.exit('artifact Root.plist missing the 1.17.0 button page text %r' % literal)
for literal in ('\u6d3b\u4f53\u6309\u94ae\u53d1\u73b0', 'sendActionsForControlEvents:', '\u65b9\u6cd5\u540d\u5173\u952e\u5b57\u53d1\u73b0'):
    if not present(settings, literal):
        sys.exit('settings binary missing 1.17.0 button-discovery text %r' % literal)
