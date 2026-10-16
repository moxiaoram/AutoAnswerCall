from pathlib import Path
import plistlib
import re
r=Path(__file__).resolve().parents[1];t=(r/'Tweak.x').read_text();s=(r/'Preferences/AACRootListController.m').read_text()
for bad in ['%hook','IOBluetooth','CTCall','hasOutgoing','CXCallUpdate','/var/jb','valueForKey:']:
 assert bad not in t,bad
for good in ['CXAnswerCallAction','requestTransaction:tx','callChanged:(CXCall *)call','Current(uuid)','Allowed(live,Prefs())','s[@"pending"]','method_getReturnType','method_getNumberOfArguments']:
 assert good in t,good
for good in ['asCopy:YES','NSFileCoordinator','startAccessingSecurityScopedResource','stopAccessingSecurityScopedResource','Limit+1','NSApplicationSupportDirectory','SETTINGS','PHONE']:
 assert good in s+t,good
p=plistlib.loads((r/'Preferences/Resources/Root.plist').read_bytes());mode=next(i for i in p['items'] if i.get('key')=='Mode');assert mode['default']==2 and mode['cell']=='PSLinkListCell' and mode['validValues']==[1,2]
# 1.10.0/1.12.0: the filter must ship the official, case-sensitive bundle ids exactly and
# must never carry the historical wrong-case phone id. The tweak may still accept the
# wrong-case id and the process names at runtime as compatibility fallbacks.
filter_text=(r/'AutoAnswerCall.plist').read_text()
assert 'com.apple.mobilephone' in filter_text, 'filter must carry the official lowercase phone id'
assert 'com.apple.springboard' in filter_text, 'filter must carry com.apple.springboard'
assert 'com.apple.InCallService' in filter_text, 'filter must carry com.apple.InCallService'
assert 'com.apple.incallservice' in filter_text, 'filter must carry the lowercase incallservice variant'
assert 'MobilePhone' not in filter_text, 'filter must not carry any wrong-case/MobilePhone identifier'
assert re.findall(r'"([^"]+)"',filter_text)==['com.apple.mobilephone','com.apple.springboard','com.apple.InCallService','com.apple.incallservice'],re.findall(r'"([^"]+)"',filter_text)
assert 'isEqualToString:@"com.apple.mobilephone"' in t and '[process isEqualToString:@"MobilePhone"]' in t
assert 'isEqualToString:@"com.apple.springboard"' in t and 'inSpringBoardProcess' in t
assert 'isEqualToString:@"com.apple.incallservice"' in t and '[process isEqualToString:@"InCallService"]' in t and 'inInCallServiceProcess' in t
delay=next(i for i in p['items'] if i.get('key')=='Delay');assert delay['cell']=='PSEditTextCell' and delay['get']=='readDelay:' and delay['set']=='setDelay:specifier:'
assert 'PSSliderCell' not in str(p)
for good in ['AACParseDelay(text.UTF8String','setBool:NO forKey:@"Enabled"','com.autoanswer.call.stop','allowsMultipleSelection=YES','NSUUID.UUID.UUIDString','dispatch_sync(dispatch_get_main_queue()','showAudioLibrary:']:
 assert good in s,good
for good in ['generation!=StopGeneration','Initial observer snapshot processed with a fresh full delay','NOT measured audible ringing','!live||!Allowed(live,Prefs())','ConfigValid=(p!=nil && synced && p[@"ConfigVersion"]!=nil)','if(!ConfigValid){Log(@"Eligibility: configuration unreadable; refusing to schedule (fail closed)");return NO;}','if(Stopped){Log(@"Eligibility: plugin stop latched in phone process; awaiting explicit resume");return NO;}','com.autoanswer.call.resume','[States removeObjectForKey:uuid]','if(States[uuid]!=s){Log(@"Delayed answer dropped: call state no longer current");return;}']:
 assert good in t,good
# The phone process must not infer enablement from an unreadable preference domain.
assert 'return v?[v boolValue]:YES;}' not in t
# Settings must publish the fail-closed marker and an explicit resume path.
assert 'forKey:@"ConfigVersion"' in s and 'resumePlugin:' in s
assert 'for(CXCall *call in Observer.calls)Changed(call)' not in t
lib=(r/'Preferences/AACAudioLibrary.h').read_text()
for good in ['audio-library.plist','SelectedAudioID','@"id"','@"path"','@"name"','@"size"','@"duration"','audio.plist','UITableViewCellAccessoryDetailButton','确认删除','isReadableFileAtPath','BOOL shared=NO','viewWillDisappear']:
 assert good in lib,good
assert 'removeItem' not in lib.split('- (BOOL)remove:(NSDictionary *)item{')[0].split('- (instancetype)init')[1].split('- (BOOL)save')[0]
system=(r/'Preferences/AACSystemControl.h').read_text()
for good in ['callAudioRoutingAutoAnswerEnabled','setCallAudioRoutingAutoAnswerEnabled:','method_getArgumentType','method_getReturnType','method_getNumberOfArguments','"B"','dlopen','objc_msgSend']:
 assert good in system,good
assert 'CFPreferences' not in system and 'notify_post' not in system
assert 'AACSystemRead' in s and 'AACSystemDisable' in s
assert 'prefs:root=ACCESSIBILITY&path=TOUCH_REACHABILITY_TITLE/CALL_AUDIO_ROUTING/callAudioRoutingAutoAnswer' in s
assert '/AutoAnswerCalls' not in s

# ---- 1.10.0 evidence build: shared log channel, per-process probe, SB inventory ----
shared=(r/'AACSharedLog.h').read_text();probe=(r/'AACProbe.h').read_text();inv=(r/'AACInventory.h').read_text()
logs=(r/'Preferences/AACLogViewerController.h').read_text();pc=(r/'Preferences/AACProbeController.h').read_text()
export_text=(r/'Preferences/AACLogExportController.h').read_text()
# candidate absolute paths, tried in order, plus the documented private fallback domain
for good in ['/var/mobile/Library/Application Support','/var/jb/var/mobile/Library/Application Support','NSApplicationSupportDirectory','NSTemporaryDirectory','/tmp/AutoAnswerCall','com.autoanswer.call.sharelog','@try','first one that is actually writable','NOT claimed']:
 assert good in shared,good
assert 'Log.' in shared and 'AACSharedPrefsAppend' in shared
assert 'writeToFile' in shared and 'fileHandleForWritingAtPath' in shared
# per-process Darwin notifications, distinct names, ~20s repeat, no payload assumption
for good in ['com.autoanswer.call.probe.','20.0','notify_post','dispatch_source_create','LastProbe.','carry no payload']:
 assert good in probe,good
assert 'AACProbeStart' in t and 'AACProbeStart(ProcessTag)' in t
assert 'com.autoanswer.call.probe.' in pc and 'probe.mobilephone' not in pc  # settings side builds names from the same prefix
# runtime inventory: real enumeration, bounded, no hooks
for good in ['objc_getClassList','class_copyMethodList','IncomingCall','CallAlert','CallToAction','CallController','InCallService','AnswerCall','CallPresentation','SBLockScreen','answer','accept','pick','dial','connect','AACInventoryMaxClasses=400','AACInventoryMaxSelectors=40','no hooks installed']:
 assert good in inv,good
assert 'AACSharedInventoryCapBytes=200000' in inv
assert 'AACRunInventory' in t and 'AACRunInventory(ProcessTag)' in t
assert '%hook' not in inv and '%hook' not in probe and '%hook' not in shared
# settings entry points and honest labels
for good in ['AACProbeController','AACSharedLogController','probeProcesses:','showSharedLogs:','本机回环测试','没有可读路径','不代表该进程未注入','不能证明接听可用']:
 assert good in s or good in pc or good in logs,good
actions=[i.get('action') for i in p['items'] if i.get('action')]
assert 'probeProcesses:' in actions and 'showSharedLogs:' in actions,actions
# 1.13.0: the two new log-share rows must exist in the shipped settings plist
assert 'shareAllLogs:' in actions and 'showLogExport:' in actions,actions
# no invented Apple preference domains/keys anywhere in the evidence code: the only
# CFPreferences domains used are our own, and no Apple accessor/key name is referenced.
for text in (shared,probe,inv):
 assert 'callAudioRouting' not in text
 assert 'com.apple.' not in text
 assert 'AXSettings' not in text
assert 'com.autoanswer.call.sharelog' in shared and 'com.autoanswer.call.probe' in shared

# ---- 1.11.0: runtime discovery + dynamic hook answer path (now host-parameterised) ----
sb=(r/'AACSpringBoard.h').read_text()
pstr=(r/'Preferences/Resources/Root.plist').read_text()
for good in ['objc_getClassList','class_copyMethodList','method_getImplementation','method_setImplementation','method_getNumberOfArguments','method_getReturnType','AACSBAnswerHook','AACSBOriginalFor','AACSBInvoking','AACSBDepth','AACSBWeakTarget','AACSBStrongTarget','AACSBRescan','AACSBInvokeDiscovered','AACSBHookedIMPs','AACSBHookCap=24','AACSBClassCap=400','AACSBSelectorCap=12','AACSBRetryDiscoveryIfEmpty','AACSBWriteDiscoveryFile','AACSBStart','runtime-discovered','discovery.txt','仅日志','AACSBRecord','AACSBSelectorMatches']:
 assert good in sb,good
# candidate classes are discovered from the real runtime; the keyword list must stay broad
for good in ['IncomingCall','CallAlert','CallToAction','CallPresentation','InCall','SBInCall','LockScreenCall','AnswerCall','CallController','CallUI','answer','accept','pickup']:
 assert good in sb,good
# 1.13.0 RELAXED HOOK ABI GATE. The 1.12.0 gate ("zero explicit arguments AND a void return")
# is gone: a device test showed SpringBoard detecting the call while NOTHING was hooked, so the
# gate itself was the most likely reason no answer path existed. The accepted set is now "zero
# explicit arguments + ANY return type a fixed thunk can forward correctly", one thunk per
# return class, and argument-taking methods are registered as NSInvocation candidates instead
# of being hooked with a wrong ABI.
assert "if(arguments!=2){" not in sb and "if(returnType[0]!='v'){" not in sb, 'the narrow 1.12.0 gate must be gone'
for good in ['AACSBThunkForReturnType','AACSBAnswerHookBool','AACSBAnswerHookObject','AACSBAnswerHookInteger','AACSBAnswerHookDouble',
             '0args+void','0args+BOOL','0args+object','0args+integer','0args+float',
             'AACSBIsOurThunk','AACSBInvocationRecords','AACSBInvocationCount','AACSBInvocationKeys','AACSBInvocationCap=12',
             'AACSBInvocationArgumentSafe','AACSBMethodInvocationSafe','AACSBInvocationSelectorFor','AACSBInvokeByInvocation',
             'signatureWithObjCTypes','[invocation invoke]','INVOKABLE_BY_INVOCATION','INVOKED_BY_INVOCATION','CAPTURED','HOOKED ',
             'AACSBSelectorForbidden','AACSBClassMatchesGlobal','global-call-scan','AACSBGlobalClassCap=600','CFAbsoluteTimeGetCurrent',
             'AACSBAnswerHookFloat','0args+float32','0args+float64','AACSBSelectorIsARCUnsafe','AACSBSelectorFamilyPrefix','ARC 方法族',
             'rolledBack=','AACSBLogMethodOutcomes','answerPaths=%lu','AACSBAnswerPathCount']:
 assert good in sb,good
# the safety blacklist is real: no decline/reject/hang-up selector may ever be hooked or invoked
for keyword in ['decline','reject','hangup','hang up','endcall','end call','disconnect','sendtovoicemail']:
 assert keyword in sb,keyword
# a float return must not be forwarded through a double thunk, and ARC method families
# (init/new/copy/alloc) are never hooked because the caller assumes a +1 return there
assert 'static float AACSBAnswerHookFloat(id self,SEL _cmd){' in sb
assert "case 'f':if(abiText)*abiText=@\"0args+float32\";return (IMP)AACSBAnswerHookFloat;" in sb
assert "case 'd':if(abiText)*abiText=@\"0args+float64\";return (IMP)AACSBAnswerHookDouble;" in sb
for family in ['alloc','new','copy','mutableCopy','init']:
 assert '"%s"' % family in sb,family
assert "NSString *forbidden=AACSBForbiddenKeyword(selectorName);" in sb and "拒绝/挂断类关键字" in sb
# MSHookMessageEx is the INTENDED mechanism now (ElleKit / substrate compat, resolved with
# dlsym so no private header has to exist), with method_setImplementation as the fallback that
# keeps the same saved-original-IMP contract. The previous test forbade this symbol; the
# assertion is inverted because the hook is now meant to go through it.
assert 'MSHookMessageEx' in sb and 'dlsym(RTLD_DEFAULT,"MSHookMessageEx")' in sb
assert 'method_setImplementation(method,thunk)' in sb
assert 'AACMSHookMessageExFn' in sb and 'hookFn(cls,selector,thunk,&original)' in sb
assert 'substrate.h' not in sb, 'the prototype must be declared locally, never through a private header'
# the invocation path is bounded and cannot silently call something dangerous
assert '显式参数数量=%u 超过可安全构造默认值的上限 3' in sb
assert '方法不存在' in sb or '方法无法用 NSInvocation 安全调用' in sb
assert 'AACSBInvokeByInvocation' in sb and 'AACSBInvoking,1)' in sb
# never hook the same method/IMP twice
assert 'AACSBHookedKeys' in sb and 'AACSBHookedIMPs' in sb and '绝不重复挂钩' in sb
# recursion guard + original IMP per (class,selector) + direct original-IMP invocation
assert 'AACSBInvoking' in sb and 'AACSBOriginalFor' in sb and 'recursion guard' in sb
# the answer path may not depend on any hardcoded private class name
# (MSHookMessageEx and substrate.h are handled above: the symbol name is required, the
# private header is still forbidden because the prototype is declared locally.)
for bad in ['NSClassFromString','SBIncomingCallViewController','SBCallAlertViewController','IncomingCallViewController','SBInCallPresentationManager','SBLockScreenCallController','%hook','substrate.h','IOKit','CTCall','hasOutgoing']:
 assert bad not in sb,bad
# policy/answer wiring in Tweak.x
for good in ['SubmitBlock','if(SubmitBlock){SubmitBlock(uuid,s);}else{','RegisterControls();','AACSBStart(env)','AnswerHostStart(answerHost)','AACSBRetryDiscoveryIfEmpty()','AACSBEnv *env=[AACSBEnv new]','LOG-ONLY primary path','已调用运行时发现的 UI 接听方法（尚未确认接通）','未发现可调用的 UI 接听路径','AACSBLogMethodOutcomes()']:
 assert good in t,good
assert 'Loaded 1.14.0 answer host' in t and '1.14.0 EVIDENCE build' in t
assert 'ABI gate relaxed' in t
assert sb.count('AACSBAnswerHook')>=4
# phone module keeps its 1.9.x/1.10.0 behaviour byte-for-byte
assert 'Loaded 1.14.0 evidence build; retained CXCallObserver in MobilePhone' in t
assert 'inPhoneProcess' in t and 'ProcessTag=@"mobilephone";' in t
# settings side shows the runtime-discovered result and never invents one
for good in ['AACDiscoveryEntry','aac-springboard.discovery.txt','runtime-discovered','AACCountOccurrences','没有可读的发现文件','showDiscovery:']:
 assert good in pc or good in s or good in pstr,good
assert 'showDiscovery:' in pstr and 'showDiscovery:' in s

# ---- 1.12.0: host table, per-host probe/pong/discovery names, single-owner answer rule ----
host=(r/'AACAnswerHost.h').read_text()
# the host table itself, one entry per host, with all five documented fields
for good in ['AACAnswerHostTable','@"tag"','@"bundle"','@"altBundle"','@"process"','@"probe"','@"pong"','@"discovery"','@"priority"','@"answer"',
             'AACAnswerHostByTag','AACAnswerHostsAnswerCapable','AACAnswerHostsHigherPriority','AACAnswerHostTagForBundle',
             'AACAnswerHostDiscoveryName','AACAnswerProbeNames','AACAnswerOwnerClaimNames','AACAnswerOwnerClaimName',
             'AACAnswerHostRoleForTag','AACAnswerPresenceFreshSeconds','AACAnswerHostSeenProbe','AACAnswerHostSeenOwnerClaim',
             'AACAnswerRoleOwner','AACAnswerRoleObserver','AACAnswerRoleLogOnly','com.autoanswer.call.owner.',
             'AACAnswerPresenceText','AACAnswerPostOwnerClaim','AACAnswerPeerPresenceReason']:
 assert good in host,good
# exact per-host names: SpringBoard keeps its 1.11.0 names, InCallService gets its own
for good in ['com.apple.InCallService','com.apple.incallservice','com.apple.mobilephone','com.apple.springboard','MobilePhone','SpringBoard','InCallService',
             'com.autoanswer.call.probe.incall','com.autoanswer.call.pong.incall','aac-incall.discovery.txt',
             'com.autoanswer.call.probe.springboard','com.autoanswer.call.pong.springboard','aac-springboard.discovery.txt',
             'com.autoanswer.call.probe.mobilephone','com.autoanswer.call.probe.settings']:
 assert good in host,good
# ownership is a deterministic role table: InCallService > SpringBoard > log-only
assert 'InCallService(2) > SpringBoard(1) > 仅日志(0)' in host
assert host.index('@"tag":@"incall"')<host.index('@"tag":@"springboard"'),'the incall host must be listed as the higher-priority host first'
# every other host records this exact observer-only sentence instead of answering
assert 'observer only, answer owned by' in host
# the host module must not hardcode a private class name either
for bad in ['NSClassFromString','SBIncomingCallViewController','SBCallAlertViewController','IncomingCallViewController','%hook','substrate.h','MSHookMessageEx','mayPerformAction']:
 assert bad not in host,bad
# the host-parameterised answer module takes its names from the host table
for good in ['AACSBEnvShared.host','AACSBHostDiscoveryFile','AACSBShouldAnswer','AACSBClaimAnswerUUID','AACSBHostProbeArrived','AACSBRecomputeRole','AACSBHostRoleText','AACSBHostOwnerTagText','AACSBRole','AACSBHostTag','# host=','# role=','# roleReason=','# observedHostPresence=','HOOKED_TOTAL','HOOK_SUMMARY','HOOK_ENTRY','CONCLUSIVE']:
 assert good in sb,good
assert 'AACAnswerHostsAnswerCapable' in sb or 'AACAnswerHostRoleForTag' in sb
# Tweak.x: InCallService is a real module, not a copy-paste promise
for good in ['AnswerHostStart(NSDictionary *host)','AACAnswerHostTagForBundle(bundle,process)','inInCallServiceProcess','answerHost=inInCallServiceProcess?AACAnswerHostByTag(@"incall")','AACSBShouldAnswer(&ownership)','AACSBClaimAnswerUUID(uuid.UUIDString)','observer only, answer owned by %@','duplicate answer submission refused','"observerOnly"','AACSBHostOwnerTagText()']:
 assert good in t,good
# single-owner rule: the ownership gate runs BEFORE any answer submission, the observer
# branch returns without submitting, and there is exactly ONE public-transaction attempt
# (never more weight on a path proven ineffective on this device).
# 1.14.0: the ownership gate still runs BEFORE any submission. The submission body is now the
# PerformAnswer block (so the bounded takeover path can reuse it), which is DEFINED earlier in
# the file but can only be REACHED through SubmitBlock's gate: the non-owner branch returns
# without calling it, and the owner branch calls it exactly once. Textual order is therefore
# asserted through the call sites, not through the definition.
assert t.index('AACSBShouldAnswer(&ownership)')<t.index('PerformAnswer(uuid,state,NO)')
assert t.count('PerformAnswer(uuid,state,')==2, 'the submission body must have exactly two call sites: owner + bounded takeover'
assert 'PerformAnswer(uuid,state,YES)' in t and 'PerformAnswer(uuid,state,NO)' in t
observer_branch=t.split('if(!AACSBShouldAnswer(&ownership)){')[1].split('PerformAnswer(uuid,state,NO)')[0]
assert 'return;' in observer_branch and 'CXAnswerCallAction' not in observer_branch
assert observer_branch.count('PerformAnswer(uuid,state,YES)')==1, 'the takeover is the only submission reachable from the observer branch'
assert t.count('secondary unverified diagnostic attempt')==1
# exactly two: the unchanged phone module (1.9.x path) and the single diagnostic attempt
assert t.count('requestTransaction:tx')==2
# 1.13.0: the CallKit error mapping is CORRECTED. Apple's CXErrorCodeRequestTransactionError
# order is unknown(0), unentitled(1), unknownCallProvider(2), emptyTransaction(3),
# unknownCallUUID(4), callUUIDAlreadyExists(5), invalidAction(6), maximumCallGroupsReached(7),
# so code 1 means UNENTITLED ("The app doesn't have the entitlement to perform the actions in
# the requested transaction") and NOT unknownCallUUID. The 1.12.0 table was wrong.
for good in ['CallKitErrorMeaning','com.apple.CallKit.error.requesttransaction','com.apple.CallKit.error.incomingcall',
             'code 0 = unknown','code 1 = unentitled','code 2 = unknownCallProvider','code 3 = emptyTransaction',
             'code 4 = unknownCallUUID','code 5 = callUUIDAlreadyExists','code 6 = invalidAction','code 7 = maximumCallGroupsReached',
             "doesn't have the entitlement",'不猜测含义','含义：']:
 assert good in t,good
assert 'code 1 = unknownCallUUID' not in t, 'the wrong 1.12.0 mapping must be gone'
assert 'code 1 = unentitled' in t
# the public transaction path is labelled unusable by Apple's own documentation, not by our guess
assert 'asynchronously performed by the telephony provider' in t
assert 'CXAnswerCallAction' in t and 'performed by a CallKit provider' in t
assert 'asking the telephony provider to perform the actions' in t
# each answer host proves its own discovery result so the next device test is conclusive
for good in ['已挂钩方法=','本宿主已挂钩运行时发现到的接听方法','因此本宿主不可能接听']:
 assert good in sb,good
# settings page: new incall probe row + its pong counter, per-host discovery labelling
for good in ['@"mobilephone",@"springboard",@"incall",@"settings"','com.autoanswer.call.pong.incall','incall-pong','AACDiscoveryHosts','AACDiscoveryHostLabel','AACDiscoveryEntryForHost','AACDiscoveryLabelForEntry','aac-incall.discovery.txt','aac-springboard.discovery.txt','没有可读的发现文件']:
 assert good in pc,good
# version bumped everywhere, package id unchanged, filter is the four documented ids
# ---- 1.13.0: version bump everywhere + full run-log export/share ------------------------
assert 'Version: 1.14.0' in (r/'control').read_text() and 'Package: com.autoanswer.call' in (r/'control').read_text()
assert 'PACKAGE_VERSION := 1.14.0' in (r/'Makefile').read_text()
assert 'INSTALL_TARGET_PROCESSES := SpringBoard MobilePhone InCallService' in (r/'Makefile').read_text()
assert '1.14.0' in (r/'README.md').read_text() and '1.14.0' in pstr and '1.14.0' in pc and '1.14.0' in sb
assert 'config[@"Version"]=@"1.14.0";' in s
assert '设置模块已加载 1.14.0' in s
assert 'config[@"Version"]=@"1.14.0";' in export_text, 'the exported configuration plist must carry the 1.14.0 version too'
# no stale 1.12.0 version stamp may survive in the shipped sources (historical prose about
# the previous release is allowed only where it is explicitly marked as history).
for path in ('control','Makefile'):
 assert '1.12.0' not in (r/path).read_text(), path
assert 'PACKAGE_VERSION := 1.14.0' in (r/'Makefile').read_text()
# --- run-log export / share (Task 2) ---
for good in ['shareAllLogs:','showLogExport:','AACLogExportController','运行日志分享']:
 assert good in s or good in pstr,good
for good in ['AACExportHosts','AACExportDiscoveryFiles','aac-incall.discovery.txt','aac-springboard.discovery.txt',
             'AACSharedFileLeaf(host,@"log")','AACSharedFileLeaf(host,@"txt")',
             'AACExportLocalDir','AACExportPrepare','configuration.plist','call-records.txt','shared-prefs-fallback.txt',
             'probe-companion.txt','settings.log','audio-library.plist','AACExportGather','AACExportEntry','AACExportCopy',
             '运行导出报告.txt','AutoAnswerCall-export-','UIActivityViewController','initWithActivityItems:items',
             'accessoryButtonTappedForRowWithIndexPath','AACLogText','未创建','不做任何虚构','AACSharedPrefsDump','AACSharedProbeCompanionDump','AACReadRecords']:
 assert good in export_text,good
# the export must report found/missing counts and never invent an entry or a credential
assert '存在 %lu 项，缺失 %lu 项' in export_text
assert 'found' in export_text and 'missing' in export_text
for forbidden in ['password','passwd','apiKey','secret','token']:
 assert forbidden not in export_text,forbidden
assert 'com.apple.' not in export_text, 'the export must only read our own domain'
assert 'callAudioRouting' not in export_text
# the entries are enumerated per host and per candidate directory, i.e. no file is hardcoded away
assert 'AACSharedLogCandidateDirs()' in export_text and 'for(NSString *host in AACExportHosts())' in export_text
assert 'AACExportHosts(void){return @[@"incall",@"springboard",@"mobilephone",@"settings"];}' in export_text
assert 'UIActivityViewController' in export_text and 'copyItemAtPath' in export_text

print('PASS: transactions, mode2 exclusions, finite seconds, stop generations, bounded multiselect import, library schema/migration/delete guards, native accessor ABI guards, 1.10.0 evidence channel (per-process probe, bounded inventory, per-path log reporting) plus the 1.11.0/1.12.0 answer-host module, the 1.13.0 relaxed hook ABI gate (MSHookMessageEx + per-return-type thunks + bounded NSInvocation candidates for argument-taking methods, per-method HOOKED/INVOKABLE_BY_INVOCATION/CAPTURED/INVOKED_BY_INVOCATION/SKIPPED reporting), the corrected CallKit error mapping (code 1 = unentitled) and the full run-log export/share surface (host table InCallService+SpringBoard+MobilePhone, per-host probe/pong/discovery names, broad runtime candidate classes, ABI-proven dynamic hooks, per-method original IMP, recursion guard, weak capture + hierarchy re-scan, deterministic single-owner role table with a per-UUID submission guard, decoded CallKit error meanings, explicit observer/log-only fallbacks) and the 1.14.0 ownership fix (demotion ONLY on a fresh explicit higher-priority ownership claim inside a bounded 90 s window; peer probe presence can never demote and is reported as presence-only evidence; a host that holds answer paths and sees no claim stays OWNER and really submits; bounded 12 s takeover after an idle higher-priority owner, at most once per call UUID and still behind the same per-UUID single-submission claim; durable reason strings for every OWNER/OBSERVER decision; one explicit 接听归属判定/owner/why/submitted line per incoming call; compact always-visible HOOKED list block with class+selector+mechanism and the invokable-by-invocation candidates, written first into the log and the discovery file; discovery digest now emitted in bounded chunks with a 6000-char budget instead of one truncated line) - static checks only, NOT device runtime')

# ---- 1.14.0 TASK 1: ownership demotion only on an explicit ownership claim -------------
# Device evidence this fixes (user's real SpringBoard shared log, 2026-10-16): the 1.13.0 run
# at 14:03:05 reported matchedClasses=150 hookedMethods=4 invokable=5 rejected=0 role=OWNER and
# detected the 14:05:08 call, then at 14:05:09 demoted ITSELF to OBSERVER with the reason
# "(incall 的探测通知在 90 秒内到达过本进程（存活证据）)" and logged "observer only, answer owned
# by incall" — InCallService never submitted anything, so nobody answered. A probe proves only
# that the peer process exists.
# The demotion loop must use the CLAIM helper exclusively. Asserted structurally: the role
# decision contains exactly two loops over higher-priority peers, the FIRST (demotion) uses only
# AACAnswerPeerClaimReason, the second is reporting-only presence.
role_fn=host.split('static inline AACAnswerRole AACAnswerHostRoleForTag')[1].split('/* Human-readable presence snapshot')[0]
assert 'AACAnswerPeerClaimReason' in role_fn,'the role decision must consult the explicit ownership claim'
peer_loops=role_fn.split('for(NSDictionary *peer in AACAnswerHostsHigherPriority(tag)){')
assert len(peer_loops)==3,'expected exactly two peer loops: the claim (demotion) loop and the presence (reporting) loop'
assert 'AACAnswerPeerClaimReason' in peer_loops[1] and 'AACAnswerPeerPresenceReason' not in peer_loops[1], \
    'the demotion loop must consult the claim only: probe presence must NEVER be able to demote'
assert 'AACAnswerRoleObserver' in peer_loops[1],'the claim loop with a fresh higher-priority claim returns OBSERVER'
assert 'AACAnswerPeerPresenceReason' in peer_loops[2] and 'AACAnswerRoleObserver' not in peer_loops[2], \
    'the presence loop only enriches the OWNER reason, it never demotes'
assert 'AACAnswerHigherPriorityOwnerClaimed' in host and 'AACAnswerTakeoverReasonText' in host
for good in ['AACAnswerClaimFreshSeconds=90.0','AACAnswerTakeoverIdleSeconds=12.0','AACAnswerPeerClaimReason','AACAnswerPeerPresenceReason',
             'REPORTING/PRESENCE helper only','may never be used to','demote a host that holds answer paths','AACAnswerHostRoleForTag(NSString *tag,NSUInteger answerPaths']:
 assert good in host,good
assert 'BOOL selfDiscoveredHooks' not in host,'the role decision now takes the real answer-path count, not a boolean'
assert 'only an EXPLICIT, fresh, higher-priority ownership claim demotes us' in host
assert '探测到存在只证明进程存在，不构成归属' in host
assert 'takeover after idle higher-priority owner' in host
# the claim is the ONLY admission criterion, and a claim is only ever posted by an OWNER host
assert 'com.autoanswer.call.owner.' in host and 'AACAnswerOwnerClaimName(tag)' in host
assert 'PROBE PRESENCE' in host.upper() and 'ROOT CAUSE' in host.upper()
assert 'matchedClasses=150 hookedMethods=4 invokable=5 rejected=0' in host,'the 1.13.0 device evidence must be quoted in the source'
assert 'observer only, answer owned by incall' in host,'the demotion line from the device log must be quoted in the source'
# module side: the role is recomputed with the answer-path count, probe arrival cannot demote,
# and a claim is broadcast only when this host decided it is OWNER
assert 'AACAnswerHostRoleForTag(AACSBHost()[@"tag"],AACSBAnswerPathCount(),&reason,&owner)' in sb
assert '只有 OWNER 才广播归属声明' in sb and '未广播接听归属声明' in sb
for good in ['AACSBHigherPriorityOwnerClaimed','AACSBMayTakeOver','AACSBClaimTakeoverUUID','AACSBHasTakenOverUUID',
             '每个 UUID 最多接管一次','本宿主没有可用的接听路径（HOOKED/INVOKABLE 都是 0）：接管了也无法提交',
             'AACSBClaimReasonText','AACSBAnswerOwnershipLine','接听归属判定 call=%@']:
 assert good in sb,good
# TASK 1 takeover wiring: bounded (12 s), once per UUID, cancelled by the stop generation, and
# skipped as soon as a connection appears; it reuses the SAME submission body so the per-UUID
# single-submission claim still guards it.
for good in ['AACSBHigherPriorityOwnerClaimed(&claimOwner,&claimReason)','AACSBMayTakeOver(uuid.UUIDString,YES,&takeoverReason)',
             'takeover after idle higher-priority owner','takeover cancelled by plugin stop generation',
             'takeover dropped: call state no longer current','takeover dropped: the call UUID is no longer observed',
             'takeover not needed: a connection was observed','takeover dropped: the call already ended',
             'takeover observation started','每个 UUID 最多一次']:
 assert good in t,good
assert 'AACSBClaimAnswerUUID' in sb and 'AACSBClaimAnswerUUID(uuid.UUIDString)' in t
# never two submissions for the same UUID from this host: both the normal path and the takeover
# path go through the same single-submission claim, and the takeover itself is claimed once
submit_sites=t.count('PerformAnswer(uuid,state,')
assert submit_sites==2 and 'if(!AACSBClaimAnswerUUID(uuid.UUIDString)){' in t
assert t.count('if(!AACSBClaimAnswerUUID(uuid.UUIDString)){')==1,'exactly one single-submission gate'
# TASK 2 per-call line: which host owns the answer, why, and whether a submission happened
assert t.count('AACSBAnswerOwnershipLine(')>=4,'the ownership line must be logged at detection, before/at submission and on the observer path'
assert 'submitted=%@' in sb and 'submitted?@"yes":@"no"' in sb
assert '来电检测时的判定' in t and '提交前的判定' in t
# ---- 1.14.0 TASK 2: compact HOOKED list + bounded multi-chunk digest --------------------
for good in ['AACSBHookedBlockText','HOOKED list','HOOKED_LIST count=','INVOKABLE_LIST count=','end HOOKED list',
             'AACSBLogDigest','AACSBLogDigestTotalCap=6000','AACSBLogDigestChunkCap=1600','AACSBListBlockMaxEntries=24']:
 assert good in sb,good
assert 'digest=text.length>4000' not in sb,'the single truncated 4000-char digest line must be gone'
assert 'AACSBLogDigest(text)' in sb
# the HOOKED list is FIRST in the file and logged line by line (each line is far under the
# 2000-char per-line shared-log cap that silently truncated the old digest)
assert 'NSString *text=[hookedBlock stringByAppendingFormat:@"\\n%@\\n",body]' in sb
assert 'for(NSString *blockLine in [hookedBlock componentsSeparatedByString:@"\\n"])AACSBLog(blockLine);' in sb
assert '共享日志单行' in sb or '每行 <=2000 字符' in sb
# the invokable-by-invocation candidates are part of the compact block too
assert 'AACSBInvokableSelectors[i]' in sb
print('1.14.0 ownership/takeover/HOOKED-list static checks passed')
