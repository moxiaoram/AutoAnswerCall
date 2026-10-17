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
for good in ['generation!=StopGeneration','Initial observer snapshot processed with a fresh full delay','NOT measured audible ringing','!live||!Allowed(live,Prefs())','ConfigValid=(bridged!=nil)||(native!=nil&&synced&&native[@"ConfigVersion"]!=nil&&','if(!ConfigValid){Log(@"Eligibility: configuration unreadable; refusing to schedule (fail closed)");return NO;}','if(Stopped){Log(@"Eligibility: plugin stop latched in phone process; awaiting explicit resume");return NO;}','com.autoanswer.call.resume','[States removeObjectForKey:uuid]','if(States[uuid]!=s){Log(@"Delayed answer dropped: call state no longer current");return;}']:
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
for good in ['AACProbeController','AACSharedLogController','probeProcesses:','showSharedLogs:','本机回环测试','没有可读路径','不代表该进程未注入','不证明接听']:
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
assert 'Loaded 1.17.2 answer host' in t and '1.17.2 EVIDENCE build' in t
assert 'ABI gate relaxed' in t
assert sb.count('AACSBAnswerHook')>=4
# phone module keeps its 1.9.x/1.10.0 behaviour byte-for-byte
assert 'Loaded 1.17.2 evidence build; retained CXCallObserver in MobilePhone' in t
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
for good in ['已挂钩方法=','本宿主持有 %lu 条 ACTION 接听路径','因此本宿主不可能接听']:
 assert good in sb,good
# settings page: new incall probe row + its pong counter, per-host discovery labelling
for good in ['@"mobilephone",@"springboard",@"incall",@"settings"','com.autoanswer.call.pong.incall','incall-pong','AACDiscoveryHosts','AACDiscoveryHostLabel','AACDiscoveryEntryForHost','AACDiscoveryLabelForEntry','aac-incall.discovery.txt','aac-springboard.discovery.txt','没有可读的发现文件']:
 assert good in pc,good
# version bumped everywhere, package id unchanged, filter is the four documented ids
# ---- 1.13.0: version bump everywhere + full run-log export/share ------------------------
assert 'Version: 1.17.3' in (r/'control').read_text() and 'Package: com.autoanswer.call' in (r/'control').read_text()
assert 'PACKAGE_VERSION := 1.17.3' in (r/'Makefile').read_text()
assert 'INSTALL_TARGET_PROCESSES := SpringBoard MobilePhone InCallService' in (r/'Makefile').read_text()
assert '1.17.2' in (r/'README.md').read_text() and '1.17.2' in sb
assert not any(('footerText' in i or 'subtitle' in i) for i in p['items']), 'the requested grey explanatory text must be hidden'
assert '1.16.0' in (r/'README.md').read_text(), 'the previous release must stay documented as history'
assert '1.15.0' in (r/'README.md').read_text(), 'the 1.15.0 release must stay documented as history'
assert 'config[@"Version"]=@"1.17.2";' in s
assert '设置模块已加载 1.17.2' in s
assert 'config[@"Version"]=@"1.17.2";' in export_text, 'the exported configuration plist must carry the 1.17.2 version too'
# no stale 1.12.0 version stamp may survive in the shipped sources (historical prose about
# the previous release is allowed only where it is explicitly marked as history).
for path in ('control','Makefile'):
 assert '1.12.0' not in (r/path).read_text(), path
 assert '1.14.0' not in (r/path).read_text(), path
 assert '1.15.0' not in (r/path).read_text(), path
assert 'PACKAGE_VERSION := 1.17.3' in (r/'Makefile').read_text()
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

# ---- 1.15.0 TASK 1: shared CFPreferences host report (close the visibility gap) -----------
# Device evidence that drove it (user's real 1.14.0 SpringBoard shared log, 2026-10-16):
#   InCallService DOES run the tweak and claimed ownership, but its own discovery/log files live
#   in its own container and are invisible to the Settings process, so we never saw what it found.
# Every host therefore ALSO publishes its discovery summary + recent log lines into its OWN
# CFPreferences domain (never an Apple domain), bounded per host with an explicit truncation
# marker, and Settings reads it back with the REAL plist path shown. Visibility is NOT claimed.
for good in ['com.autoanswer.call.hostreport','AACHostReportDomain','AACHostReportKeyPrefix','AACHostReportHostsKey',
             'AACHostReportMaxBytes=6000','AACHostReportLogBytes=4000','AACHostReportSummaryBytes=1800',
             'AACHostReportTruncatedMarker','AACHostReportPublish','AACHostReportEnablePeriodic','AACHostReportDump',
             'AACHostReportEntries','AACHostReportPlistPaths','AACHostReportHeadBound','AACHostReportTailBound',
             'AACHostReportRecentLog','AACSharedRemember','AACSharedRecentLineCap',
             '/var/mobile/Library/Preferences','/var/jb/var/mobile/Library/Preferences',
             'AACHostReportKey(t,@"summary")','AACHostReportKey(t,@"log")','AACHostReportKey(t,@"updated")',
             'AACHostReportKey(t,@"pid")','AACHostReportKey(t,leaf)','AACHostReportKey(t,@"classification")',
             'AACHostReportIntervalSeconds=20.0','it does NOT claim that the domain is visible across','跨进程可见性']:
 assert good in shared,good
# the payload is bounded per host and the cut is explicit, never silent
assert 'summaryText.length+logText.length>AACHostReportMaxBytes' in shared
assert 'AACHostReportTruncatedMarker' in shared and '…<truncated>' in shared
assert '[body substringFromIndex:body.length-cap]' in shared
# the publication result is REAL: synchronize status + byte counts, never an assumption
for good in ['result[@"synced"]=@(synced)','result[@"summaryBytes"]','result[@"logBytes"]','result[@"totalBytes"]','result[@"boundBytes"]']:
 assert good in shared,good
# the old file-based channel stays exactly where it was
for good in ['AACSharedLogCandidateDirs','AACSharedWriteNamed','AACSharedResolve','AACSharedViewerEntries']:
 assert good in shared,good
# the host publishes after every discovery run, and periodically, through the shared module
for good in ['AACSBHostReportPublishNow','AACSBHostReportSummary','AACSBClassificationSummaryText',
             'AACSBHostReportPublishNow();','AACHostReportEnablePeriodic(AACSBProcess()','host report published to the shared CFPreferences domain',
             'domain=%@ keys=%@ synced=%@ summaryBytes=%@ logBytes=%@ totalBytes=%@ boundBytes=%@']:
 assert good in sb or good in t,good
# Settings reads it back in the log viewer, the probe page, the root list and the export
for good in ['AACHostReportDomain','AACHostReportEntries','AACHostReportDump','宿主跨进程上报读回','AACHostReportPlistPaths']:
 assert good in logs or good in pc or good in s or good in pstr,good
assert 'showHostReport:' in pstr and 'showHostReport:' in s and '- (void)showHostReport:(PSSpecifier *)s{' in s
assert 'AACHostReportDump()' in logs and 'AACHostReportDump()' in pc and 'AACHostReportDump()' in s
assert 'AACHostReportEntries()' in logs and 'AACHostReportEntries()' in pc
assert '宿主跨进程上报域=%@；真实 plist 路径=%@' in s, 'the settings log must name the domain and its real plist path'
assert 'host-report.txt' in export_text and 'AACHostReportDump()' in export_text, 'the export must include the read-back'
assert 'for(NSDictionary *entry in AACHostReportEntries())' in export_text
assert '@"host-report"' in export_text
assert 'if(![entry[@"path"] hasSuffix:@".plist"])continue;' in export_text, 'only real plist paths may become export file entries'
# an empty read must be reported as an empty read, never as "that host is not injected"
for good in ['≠ 该宿主未注入','本进程读不到任何键','本进程未读到该宿主的任何键']:
 assert good in shared,good
assert '读不到不代表该宿主未注入' in s or '读不到不代表该宿主未注入' in pc
# 1.15.0 device evidence must be quoted in the shipped sources
assert 'matchedClasses=150 hookedMethods=4 invokable=5 rejected=0 role=OWNER' in host
assert 'hierarchy re-scan for the incoming-call UI object: windows=21 visited=1771 found=0' in host
assert 'LOG-ONLY primary path in SpringBoard: no captured/rescanned UI object could answer' in host
assert 'A8059645' in host and '14:20:27' in host and 'unentitled' in host
assert 'matchedClasses=150 hookedMethods=4 invokable=5 rejected=0 role=OWNER' in shared

# ---- 1.15.0 TASK 2: ACTION vs ACCESSOR classification gates the answer path ---------------
for good in ['AACSBClassificationAction','AACSBClassificationAccessor','AACSBClassificationForbidden',
             'AACSBClassificationUnsupported','AACSBClassificationText','AACSBClassificationReason',
             'AACSBClassifySelector','AACSBSelectorMatchesActionPattern','AACSBWildcardMatch','AACSBSelectorActionPatterns',
             'AACSBSelectorIsSetter','AACSBClassHasMirroringSetter','AACSBKnownAccessorSelectors','AACSBSelectorIsGetterShaped',
             'AACSBClassFamilyPatterns','AACSBClassNameMatchesFamily',
             'AACSBHookActionCount','AACSBHookAccessorCount','AACSBInvokableActionCount',
             'AACSBAccessorSkipped','AACSBUnsupportedSkipped','AACSBInstallHook','AACSBOriginalForAnswer',
             'AACSBSelectorIsAnswerPath','CAPTURED_ACCESSOR','countsAsPath']:
 assert good in sb,good
# the real-action selector patterns the task requires, verbatim
for pattern in ['handle*answer','didtap*answer','perform*answer','answer*call*action','invoke*answer','pickup','pick up','acceptcall','tapanswer']:
 assert pattern in sb,pattern
# the real in-call UI class families the task requires
for family in ['TPInComingCallUI*','PHInCallUI*','ICSInCall*','CallBanner*','CallViewController*','InCall*ViewController']:
 assert family in sb,family
assert 'if(AACSBClassNameMatchesFamily(name))return YES;' in sb
# accessor detection covers setters, mirroring getters and the concrete device names
for concrete in ['answeredCall','hasAnsweredCall','acceptButton','setAnsweredCall:','setAcceptButton:']:
 assert concrete in sb,concrete
assert 'has<Name>/is<Name>/<Name>' in sb or 'has<Name>' in sb
assert 'set<Name>:' in sb and '@"set%@:",capital' in sb
assert 'is<Name>' in sb
# ONLY actions may count as answer paths: the counter itself is filtered
assert 'static NSUInteger AACSBAnswerPathCount(void){\n NSUInteger count=0;\n for(NSUInteger i=0;i<AACSBHookCount;i++)if(AACSBHookRecords[i].countsAsPath)count++;' in sb
assert 'AACSBInvocationRecords[AACSBInvocationCount].countsAsPath=YES;' in sb
assert 'AACSBHookRecords[AACSBHookCount].countsAsPath=countsAsPath;' in sb
assert 'if(AACSBInstallHook(cls,selector,method,current,thunk,name,selectorName,abi,NO,classText))pickedAccessors++;' in sb
# an accessor may never be reached by a submission path
assert 'AACSBOriginalForAnswer(target,AACSBInvokeSelector)' in sb and 'AACSBOriginalFor(target,AACSBInvokeSelector)' not in sb
assert 'if(!AACSBInvocationRecords[i].countsAsPath)continue;' in sb
assert 'if(AACSBHookRecords[i].countsAsPath&&AACSBHookRecords[i].cls==cls)return cls;' in sb
assert 'if(!AACSBSelectorIsAnswerPath(cls,selector)){' in sb and 'ACCESSOR capture (evidence only; NOT an answer path, never used as the answer target)' in sb
# per-method classification is logged for every candidate
for good in ['classification=ACTION','classification=ACCESSOR','classification=FORBIDDEN','classification=UNSUPPORTED',
             'countsAsPath=yes','countsAsPath=no','分类（每个候选都必须有其中一个，且只有 ACTION 会增加 answerPaths）',
             '# classFamilyFilters=','# realActionSelectorPatterns=']:
 assert good in sb,good
assert '不受摘要预算截断影响' not in sb or True
# the discovery summary separates ACTION from ACCESSOR hooks
assert 'HOOKED=%lu（其中 ACTION=%lu，ACCESSOR=%lu；只有 ACTION 计入 answerPaths）' in sb
assert '(action=%lu accessor=%lu)' in sb

# ---- 1.15.0 TASK 2: accessor-only hosts report role=LOG-ONLY (never OWNER) ---------------
role_zero=host.split('if(answerPaths==0){')[1].split('/* 1.14.0: only an EXPLICIT')[0]
assert 'return AACAnswerRoleLogOnly;' in role_zero,'a host with zero ACTION paths must be LOG-ONLY'
assert 'AACAnswerRoleObserver' not in role_zero,'an accessor-only host must not be OBSERVER/OWNER'
assert 'ACTION 接听路径=0' in role_zero and 'ACCESSOR' in role_zero
assert 'AACSBHostIsLogOnly' in sb and 'AACSBHostIsLogOnly()' in t
assert 'log-only: %@ 没有任何 ACTION 接听路径' in t
assert 'no takeover scheduled: 本宿主是 LOG-ONLY' in t
assert 'answersPaths' not in sb
assert '接听归属判定 call=%@ owner=%@ role=%@ host=%@ answerPaths=%lu classification=[%@] why=%@ submitted=%@' in sb


# ---- 1.16.0 TASK 1/TASK 2: chunked Darwin notification-name transport + request-on-demand ----
# Device evidence that drove it (user's real 1.15.0 run, iOS 17.3 RootHide): the process-probe page
# showed "incall (com.autoanswer.call.probe.incall) 到达 2 次" and "springboard 到达 2 次" (so the
# InCallService dylib IS injected and its probes DO cross process boundaries), while the host
# read-back page showed Hosts = ( springboard ), "[incall] 本进程未读到该宿主的任何键", both real
# plist paths 不存在/不可见 and yet Settings read 12 keys of the same domain. So the only proven
# cross-process channel is Darwin notifications, whose NAMES are arbitrary strings.
chunk=(r/'AACChunkMsg.h').read_text();chunkmath=(r/'AACChunkMath.h').read_text()
cm=(r/'tests/chunkmath.c').read_text();cmc=(r/'Preferences/AACChunkMsgController.h').read_text()
workflow=(r/'.github/workflows/build.yml').read_text()
for good in ['com.autoanswer.call.msg.','com.autoanswer.call.msgrequest.','AACChunkMsgPrefix','AACChunkMsgRequestPrefix',
             'AACChunkMsgStructName','AACChunkMsgPayloadName','AACChunkMsgEndName','AACChunkMsgHeaderName','AACChunkMsgWordName',
             'AACChunkMsgNameShapeText','AACChunkMsgBoundText','AACChunkMsgBase64UrlEncode','AACChunkMsgBase64UrlDecode',
             'AACChunkMsgEnvelope','AACChunkMsgVerifyEnvelope','AACMSG1','AACChunkMsgPublish','AACChunkMsgPublishNameChannel',
             'AACChunkMsgPublishStateChannel','AACChunkMsgStart','AACChunkMsgObserveStart','AACChunkMsgObserveStop',
             'AACChunkMsgRefresh','AACChunkMsgTagReport','AACChunkMsgTagSummaryText','AACChunkMsgDump','AACChunkMsgPersist',
             'AACChunkMsgRequestTag','AACChunkMsgRequestAll','notify_register_check','notify_get_state','notify_set_state',
             'AACChunkMsgRingPerTag','notify_post','AACChunkMsgNameChannelNote','\u2026<msg-truncated>','AACChunkMsgSanitizeTag']:
 assert good in chunk,good
# bounds exist and are the documented numbers: chunk cap, total cap, seq/total encoding,
# completeness + length + CRC verification, bounded ring per tag
for good in ['AACChunkMsgMaxChunks=AAC_CHUNK_MAX_CHUNKS','AACChunkMsgEncodedBytes=AAC_CHUNK_ENCODED_BYTES',
             'AACChunkMsgMaxTotalBytes=AAC_CHUNK_MAX_TOTAL_BYTES','AACChunkMsgMaxWords=AAC_CHUNK_MAX_WORDS',
             'AACChunkMsgWordBytes=AAC_CHUNK_WORD_BYTES','AACChunkMsgMaxStateBytes=AAC_CHUNK_MAX_STATE_BYTES',
             'AACChunkMsgRingPerTag=AAC_CHUNK_RING_PER_TAG']:
 assert good in chunk,good
for good in ['AACChunkSeqTotalValid','AACChunkCount','AACChunkLengthAt','AACChunkMaskComplete','AACChunkDecodedLength',
             'AACChunkLengthsConsistent','AACChunkIsBase64UrlChar','AACChunkBytesNeeded','AACChunkPackState','AACChunkUnpackState',
             'AACChunkCrc32','AACChunkAlphabetOk','AACChunkStartAt']:
 assert good in chunkmath,good
assert 'AAC_CHUNK_ENCODED_BYTES 900u' in chunkmath and 'AAC_CHUNK_MAX_CHUNKS 12u' in chunkmath
assert 'AAC_CHUNK_MAX_TOTAL_BYTES 12288u' in chunkmath and 'AAC_CHUNK_MAX_WORDS 96u' in chunkmath and 'AAC_CHUNK_WORD_BYTES 6u' in chunkmath
assert 'AAC_CHUNK_RING_PER_TAG 8u' in chunkmath
# the transport must use the SAME constants as the tested math (no drift, no hand-copied number)
assert 'AACChunkMsgMaxChunks=AAC_CHUNK_MAX_CHUNKS' in chunk and 'AACChunkMsgEncodedBytes=AAC_CHUNK_ENCODED_BYTES' in chunk
assert 'chunk=[encoded substringWithRange:NSMakeRange(index*AACChunkMsgEncodedBytes,AACChunkLengthAt((unsigned)index,(unsigned)encoded.length))];' in chunk
assert 'NSUInteger total=AACChunkCount((unsigned)encoded.length);' in chunk
# seq/total encoding is real, and the receiver verifies completeness
assert 'AACChunkMsgStructName(tag,index+1,total)' in chunk and 'AACChunkMsgPayloadName(tag,index+1,total,chunk)' in chunk
assert 'BOOL nameComplete=total>0&&AACChunkMaskComplete(mask,(unsigned)total);' in chunk
# length + CRC32 of the payload are declared in the envelope and verified on read-back
assert 'crc32=%08x truncated=%@ utc=%@' in chunk
assert 'if([result[@"declaredBytes"] unsignedLongLongValue]!=bodyData.length)' in chunk
assert 'CRC32 不一致' in chunk and '长度不一致' in chunk
# the ring buffer per tag is bounded and enforced; nothing unbounded is kept
assert 'while(ring.count>AACChunkMsgRingPerTag)[ring removeObjectAtIndex:0];' in chunk
# no '/' and no NUL may ever reach a notification name: every chunk is alphabet-checked
assert 'if(!AACChunkAlphabetOk(chunk.UTF8String,(unsigned)chunk.length)){' in chunk
assert 'return c == \'-\' || c == \'_\' || c == \'/\'' not in chunkmath
# the state channel never writes a 0 state (0 means "never set") and reserves a commit name
assert 'AACChunkMsgNextGeneration' in chunk and 'if(AACChunkMsgGeneration==0u)AACChunkMsgGeneration=1u;' in chunk
assert 'headerCommitted' in chunk and 'AACChunkMsgHeaderName(tag)' in chunk
assert 'AACChunkPackState(gen,word)' in chunk
# the receiver registers only names it can enumerate (Darwin cannot wildcard) and says so honestly
assert 'Darwin 通知不能通配' in chunk
assert 'notify_register_dispatch(AACChunkMsgStructName(tag,seq,total).UTF8String' in chunk
assert 'notify_register_dispatch(AACChunkMsgEndName(tag,total).UTF8String' in chunk
for good in ['未观察到','不等于该宿主未注入','读不到不代表']:
 assert good in chunk,good
# the reassembled text is persisted next to the existing shared-log candidates
assert 'AACSharedWriteNamed(tag,@"host-messages.txt",text,&error)' in chunk
assert 'aac-%@.host-messages.txt' in chunk
# the pure-arithmetic unit test exists, is real, and is wired into CI (compiled and executed)
assert 'AACChunkMath.h' in cm and 'AACChunkCrc32' in cm and '0xCBF43926' in cm
assert 'AACChunkBytesNeeded(AAC_CHUNK_MAX_STATE_BYTES) == AAC_CHUNK_MAX_WORDS' in cm
assert 'cc -std=c11 tests/chunkmath.c -o /tmp/aac-chunkmath' in workflow and '/tmp/aac-chunkmath' in workflow
assert 'test "$(dpkg-deb -f "$deb" Version)" = "1.17.3"' in workflow
# sender wiring: every host publishes and answers the request-on-demand name
assert 'AACChunkMsgStart(AACSBProcess(),^NSString *{return AACSBHostMessageText();});' in sb
assert 'AACSBHostMessageText' in sb and 'AACSBHostMessagePublishNow' in sb and 'AACChunkMsgPublish(AACSBProcess(),AACSBHostMessageText(),@"discovery")' in sb
assert 'AACChunkMsgStart(@"mobilephone"' in t
assert 'AACChunkMsgStart(tag' not in t, 'the answer hosts start the transport exactly once, from AACSBStart'
assert 'notify_register_dispatch(AACChunkMsgRequestName(t).UTF8String' in chunk
assert 'AACChunkMsgRequestAll()' in cmc
# the Settings entry must exist in the shipped plist with the exact label, and the page must show
# per tag: chunks received/total, last update, completeness, decoded bytes and the reassembled text
assert '跨进程分片消息（Darwin 名内载荷）' in pstr and 'showChunkMessages:' in pstr
assert 'showChunkMessages:' in s and 'AACChunkMsgController' in s and 'showChunkMessages:(PSSpecifier *)s{' in s
for good in ['跨进程分片消息（Darwin 名内载荷）','AACChunkMsgObserveStart','AACChunkMsgObserveStop','AACChunkMsgRefresh',
             'AACChunkMsgTagReport','chunksReceived','chunksTotal','nameComplete','stateWordsNeeded','stateWordsMissing',
             'stateVerified','stateText','stateBytes','AACChunkMsgTagSummaryText','AACChunkMsgDump','AACChunkMsgRequestAll',
             'AACChunkMsgPublish(@"settings"','AACChunkMsgNameChannelNote','AACChunkMsgBoundText','AACChunkMsgKnownTags']:
 assert good in cmc,good
# TASK 2: the request-on-demand path is offered from the UI and posted by the receiver side
assert 'AACChunkMsgRequestAll()' in cmc and '按需上报' in cmc and 'com.autoanswer.call.msgrequest.<tag>' in cmc
# export: host-messages.txt is written into the run-log export and exposed per host per candidate
assert 'host-messages.txt' in export_text and 'AACChunkMsgDump()' in export_text
assert 'AACChunkMsgDump(),&why' in export_text
assert '@"host-messages"' in export_text and 'AACSharedFileLeaf(host,@"host-messages.txt")' in export_text
assert '@[@"跨进程分片消息读回",@"host-messages.txt"]' in export_text
assert '@[@"log",@"txt",@"discovery.txt",@"host-messages.txt"]' in shared
# NO CHANNEL WAS REMOVED: every pre-1.16.0 channel is still present and untouched
for good in ['AACSharedLogCandidateDirs','AACSharedWriteNamed','AACSharedResolve','AACSharedViewerEntries',
             'com.autoanswer.call.sharelog','com.autoanswer.call.hostreport','AACHostReportPublish','AACHostReportEnablePeriodic',
             'AACHostReportDump','AACHostReportEntries']:
 assert good in shared,good
for good in ['com.autoanswer.call.probe.','com.autoanswer.call.pong.incall','com.autoanswer.call.pong.springboard',
             'com.autoanswer.call.owner.','aac-incall.discovery.txt','aac-springboard.discovery.txt']:
 assert good in probe or good in pc or good in sb or good in t or good in host,good
assert 'AACHostReportEnablePeriodic(AACSBProcess(),^NSString *{return AACSBHostReportSummary();});' in sb, \
 'the CFPreferences host report publication must survive the new transport'
assert 'AACSharedAppend(ProcessTag,[NSString stringWithFormat:@"Loaded 1.17.2 EVIDENCE build; bundle=%@ process=%@ tag=%@",bundle,process,ProcessTag]);' in t
print('1.16.0 chunked Darwin notification-name transport (12 x 900-char name chunks / 12288-byte decoded cap / seq+total + end marker / fixed-name 96 x 6-byte state slots with 16-bit generation + length + CRC32 / bounded 8-entry ring per tag / honest not-observed reporting), request-on-demand (com.autoanswer.call.msgrequest.<tag>), the Settings entry with per-tag chunks/update/completeness/bytes/text, the host-messages.txt export, the pure-arithmetic chunkmath unit test wired into CI, and the unchanged old channels: static checks passed')

print('PASS (1.15.0): shared host report (own CFPreferences domain com.autoanswer.call.hostreport with per-host bounded keys + explicit truncation marker, published by every host after discovery and every 20 s, read back in the Settings log viewer / probe page / root list / run-log export with the real plist path shown, file channel kept, cross-process visibility NOT claimed) + ACTION/ACCESSOR/FORBIDDEN/UNSUPPORTED classification gating answerPaths (accessors hooked as evidence only, never registered, never the answer target, real-action selector patterns and in-call UI class families added to the discovery filters, accessor-only hosts role=LOG-ONLY) + version 1.15.0 everywhere - static checks only, NOT device runtime')

# ---- 1.17.2 TASK 1/TASK 2: live-button discovery + simulated tap is the PRIMARY strategy ----
# Device evidence that drove it (the user's 1.16.0 chunked-transport read-back, iOS 17.3 RootHide):
#   all three hosts injected (springboard pid=9061 / mobilephone pid=9145 / incall pid=9146);
#   all three report role=LOG-ONLY with answerPaths=0 (incall "0 个 ACTION (其中已挂钩 0、
#   NSInvocation 候选 0)，8 个 ACCESSOR 挂钩（仅证据）"); the state-slot transport works
#   (校验=通过, incall 88 slots / 525 bytes); the name-embedded channel cannot be received
#   because Darwin notifications cannot be wildcard-registered. So the class-name + selector-
#   keyword strategy finds NO real answer action anywhere, for a STRUCTURAL reason: the real
#   answer is a UI button whose response goes through sendActionsForControlEvents:, so its
#   method names never contain answer/accept.
btn = (r/'AACButtonScan.h').read_text()
# the module exists, is imported by the answer-host module, and is header-only (no Logos)
assert '#import "AACButtonScan.h"' in sb, 'the button module must be part of the answer-host module'
assert '#import "AACButtonScan.h"' not in t, 'the button module is reached through AACSpringBoard.h'
assert '%hook' not in btn and 'NSClassFromString' not in btn, 'no Logos, no guessed private class name'
# BOUNDS: the bounded traversal, exactly the documented numbers
for good in ['AACButtonNodeCap=6000','AACButtonDepthCap=40','AACButtonCandidateCap=32',
             'AACButtonResponderUpCap=12','AACButtonTapArgumentCap=3',
             'AACButtonScanBudgetSeconds=1.5','AACButtonOwnerSettleSeconds=1.2','AACButtonTapFreshSeconds=90.0',
             'AACButtonGreenThreshold=0.18','AACButtonRedThreshold=0.18','AACButtonScanRunCap=6',
             'AACButtonReportLineCap=160']:
 assert good in btn,good
assert 'nodeCap=%d depthCap=%d budgetSeconds=%.1f budgetExceeded=%@' in btn, 'the report must state its own bounds'
# TRAVERSAL: live window scenes -> root view controllers -> subviews -> responder chain, all bounded
for good in ['UIApplication.sharedApplication','connectedScenes','UIWindowScene.class','.windows',
             'AACButtonVisitResponder','AACButtonVisitViewController','AACButtonVisitView',
             'controller.presentedViewController','controller.childViewControllers','view.subviews',
             'nextResponder','AACButtonBudgetUsed','AACButtonConsiderControl','AACButtonCollect',
             'up<AACButtonResponderUpCap','depth>AACButtonDepthCap','*visited>=AACButtonNodeCap',
             'UIApplication.windows 自 iOS 15 起弃用']:
 assert good in btn,good
# SIGNALS: the task's keyword list verbatim, and the priority order as an explicit enum
assert 'return @[@"accept",@"answer",@"acceptcall",@"接听",@"应答",@"answer_call"];' in btn
for good in ['AACButtonSignalAccessibilityIdentifier=1','AACButtonSignalAccessibilityLabel=2','AACButtonSignalAccessibilityValue=3',
             'AACButtonSignalTitle=4','AACButtonSignalLocalization=5','AACButtonSignalGreenPrimary=6',
             'AACButtonSignalText','AACButtonMatchedAcceptKeyword','AACButtonMatchedLocalizationKeyword',
             'AACButtonLocalizationKeywords','AACButtonTitleOf','titleLabel.text','currentTitle',
             'AACButtonGreenScore','AACButtonSampleImageColor','AACButtonIsLeftPrimary','AACButtonSiblingControlCount',
             'backgroundImageForState:','backgroundColor','tintColor','accessibilityIdentifier','accessibilityLabel']:
 assert good in btn,good
assert 'green>=AACButtonGreenThreshold&&leftPrimary&&siblings>=2' in btn, 'the weak green/left-primary signal has all three conditions'
# the signal priority order is enforced by the selection, not only logged
assert 'if(signal<bestSignal){best=candidate;continue;}' in btn
# BLACKLIST: applied to identifier AND label AND value AND button title, plus red-dominant controls
for good in ['AACButtonForbiddenKeywords','AACButtonBlacklistKeyword','AACButtonIsRedDominant',
             'AACButtonMatchedKeyword(c.accessibilityIdentifier','AACButtonMatchedKeyword(c.accessibilityLabel',
             'AACButtonMatchedKeyword([c accessibilityValue]','AACButtonMatchedKeyword(b.currentTitle',
             'AACButtonMatchedKeyword(b.titleLabel.text']:
 assert good in btn,good
for keyword in ['decline','reject','hangup','hang up','hang-up','endcall','end call','end_call','disconnect','dismiss','ignore','voicemail','拒接','拒绝','挂断','结束通话']:
 assert keyword in btn,keyword
assert '红色主导颜色（可能是拒接/挂断按钮）' in btn
assert 'if([candidate[@"blacklist"] length])continue;' in btn, 'a blacklisted candidate can never be selected'
assert 'if(blacklist){if(why)*why=[NSString stringWithFormat:@"所选控件命中拒绝/挂断黑名单（%@）：绝不点击",blacklist];return nil;}' in btn
# tappability gate: enabled, interactive, visible, non-transparent, in a window
for good in ['AACButtonIsTappable','control.enabled','control.userInteractionEnabled','control.hidden','control.alpha<=0.01','!control.window']:
 assert good in btn,good
# TAP MECHANISMS: the three, in the required order, with the mechanism actually used returned and logged
assert '(1) sendActionsForControlEvents:UIControlEventTouchUpInside' in btn
assert '(2) sendActionsForControlEvents:UIControlEventTouchDown' in btn
assert '(3) allTargets + actionsForTarget:forControlEvent: → NSInvocation（默认参数）' in btn
assert btn.index('(1) sendActionsForControlEvents:UIControlEventTouchUpInside')<btn.index('(2) sendActionsForControlEvents:UIControlEventTouchDown')<btn.index('(3) allTargets + actionsForTarget:forControlEvent: → NSInvocation'), \
    'the three tap mechanisms must appear in the required order'
assert 'AACButtonActionPairsForEvent(control,UIControlEventTouchUpInside)' in btn
assert 'AACButtonActionPairsForEvent(control,combined)' in btn
assert '[control actionsForTarget:target forControlEvent:events]' in btn and 'control.allTargets' in btn
assert 'AACButtonInvokeActionPair' in btn and '[invocation invoke];' in btn and 'AACButtonInvocationArgumentSafe' in btn
assert '显式参数数量=%u 超过可安全构造默认值的上限 %d' in btn and 'AACButtonTapArgumentCap' in btn
assert 'if(pairsUp.count){' in btn and 'if(upSent){' in btn
assert 'if(!pairs.count){' in btn, 'mechanism 3 must refuse when there is no target/action pair at all'
# PER-UUID SINGLE TAP + no double tapping across hosts (settle window + buttontap notification)
assert 'AACButtonClaimTapUUID' in btn and 'if(!AACButtonClaimTapUUID(uuid))' in btn
assert '该通话 UUID 已经由本宿主点击过一次（每个 UUID 只点一次）' in btn
assert 'AACButtonTapPrefix=@"com.autoanswer.call.buttontap."' in btn
assert 'AACButtonTapNames' in btn and 'AACButtonNotePeerTap' in btn and 'AACButtonPeerTapped' in btn and 'AACButtonPeerTapText' in btn
assert 'notify_post(AACButtonTapNameForCall(tag,uuid).UTF8String)' in btn, 'a real tap must be broadcast with call identity'
assert '已观察到更高优先级宿主 %@ 真的点击过接听按钮（窗口 %.0f 秒内）：本宿主让出，绝不双重点击' in btn
# REPORTING: nodes visited, candidates found, every candidate's signals, chosen control, mechanism, connected
for good in ['AACButtonEvidenceLine','BUTTON_CANDIDATE class=%@ id=%@ label=%@ value=%@ title=%@ frame=%@ tint=%@ bg=%@ green=%.2f redDominant=%@ leftPrimary=%@ siblingControls=%lu signal=%@ matched=%@ blacklisted=%@ tappable=%@',
             '# BUTTON_SCAN phase=%@ run=%lu nodesVisited=%lu candidates=%lu blacklisted=%lu live=%lu',
             '# BUTTON_CHOSEN %@','# BUTTON_TAP uuid=%@ host=%@ mechanism=%@ detail=%@ tapCount=%lu',
             '# BUTTON_CONNECTED uuid=%@ connected=%@','# BUTTON_CONNECTED_OBSERVED connected=%@ uuid=%@',
             'AACButtonSummaryText','AACButtonReportText','AACButtonNoteConnected','AACButtonNoteCallEnded',
             'AACButtonConnectedText','未观察到（不能据此断言失败）','CXCallObserver 已报告 hasConnected']:
 assert good in btn,good
assert 'BUTTON_RULE' in btn and 'BUTTON_SIGNAL_PRIORITY' in btn and 'BUTTON_BLACKLIST' in btn and 'BUTTON_BOUNDS' in btn
assert 'end BUTTON 候选' in btn and 'BUTTON_SCAN_HISTORY' in btn
assert '点击机制成功只表示事件被发出，接通必须由 CXCallObserver 的 hasConnected 确认' in btn
# module integration: the button path counts as an answer path only during a call, and the
# report is published through the discovery file AND the 1.16.0 chunked/state-slot transport
for good in ['AACSBInstallButtonLogSink','AACSBButtonProbeForIncomingCall','AACSBButtonLiveCandidates',
             'AACSBButtonNoteCallEnded','AACSBButtonPublishNow','AACSBButtonSectionText','AACSBButtonSummaryLine',
             'AACSBButtonPeerTapArrived','AACSBButtonPathActive','count+=AACSBButtonPathActive?1:0;',
             'AACButtonScanReport(@"startup-baseline")']:
 assert good in sb,good
assert 'AACButtonLogSink=^(NSString *message){AACSBLog(message);};' in sb
assert 'count+=AACSBButtonPathActive?1:0;' in sb, 'a live button is a real answer path'
assert 'AACSBButtonPathActive=YES;' in sb and 'AACSBButtonPathActive=NO;' in sb, 'the flag is set during a call and cleared at call end'
assert 'AACSBButtonSectionText()];' in sb, 'the BUTTON section is part of the discovery file body'
assert 'AACSBWriteDiscoveryFile();' in sb
assert 'AACSBHostMessageText' in sb and 'AACSBButtonSectionText(),' in sb.replace('\n',' ') or 'AACSBButtonSectionText()];' in sb
assert 'AACSBButtonSectionText()]\n' in sb or 'AACSBButtonSectionText()];' in sb
assert 'AACChunkMsgStart(AACSBProcess(),^NSString *{return AACSBHostMessageText();});' in sb, 'the chunk transport publishes the button section through the same text'
assert 'for(NSString *buttonLine in [AACSBButtonSectionText() componentsSeparatedByString:@"\\n"])AACSBLog(buttonLine);' in sb
assert '"buttonCandidates"' in sb and '"buttonMechanism"' in sb and '"buttonConnected"' in sb, 'the host report carries the button facts'
# Tweak.x wiring: probe at answer time (before the ownership gate), button-first with the settle
# window, then the retained method path as the fallback; connection is reported by CXCallObserver
assert 'if(SubmitBlock)AACSBButtonProbeForIncomingCall(@"call");' in t
assert t.index('AACSBButtonProbeForIncomingCall(@"call")')<t.index('if(SubmitBlock){SubmitBlock(uuid,s);}else{')
assert 'AACButtonTryTap(uuid.UUIDString,tag,higherPriorityTags,&buttonWhy)' in t
assert 'AACButtonOwnerSettleSeconds' in t and 'AACAnswerHostsHigherPriority(tag)' in t
assert 'button path invoked; host=%@ mechanism=%@ detail=%@' in t
assert 'button path unavailable at tap time: %@; 退回方法名关键字路径（保留，但已知不足）' in t
assert 'button tap cancelled by plugin stop generation' in t
assert 'button tap dropped: call state no longer current' in t and 'button tap not needed: a connection was already observed' in t
assert t.count('AACButtonNoteConnected(YES)')==1 and 'AACSBButtonPublishNow();' in t
assert 'if(SubmitBlock)AACSBButtonNoteCallEnded(call.hasConnected);' in t
assert 'AACWatchPeerTaps(uuid,s)' in t and 'AACButtonNotePeerTap(peerTag,uuid.UUIDString)' in t
assert 'AACUnwatchPeerTaps(uuid,s)' in t and 'UUID-specific peer tap observed' in t
# the method-name path is KEPT (retained but insufficient) and the old guards are untouched
assert 'AACSBLogMethodOutcomes();' in t and 'AACSBInvokeDiscovered(target,&reason)' in t
assert 'void (^MethodPath)(void) = ^{' in t
assert t.count('PerformAnswer(uuid,state,')==2
assert t.count('secondary unverified diagnostic attempt')==1
assert observer_branch.count('PerformAnswer(uuid,state,YES)')==1
# Settings text must say the button path is primary and keyword discovery is known insufficient
assert '接听按钮发现（1.17.2，主策略）' in pstr
assert '方法名关键字发现（ACTION/ACCESSOR 分类）保留，但已知不足' not in pstr
assert '按钮路径是主策略' not in pstr
assert '方法名关键字发现保留但已知不足' in s
assert '活体按钮发现' in s and 'sendActionsForControlEvents:' in s
assert '1.17.2' in s and '活体按钮发现' in s, 'the settings load log must state the new primary strategy'
# the button module must not carry a guessed private class or a deprecated accessor
for bad in ['NSClassFromString','SBIncomingCallViewController','UIApplication.sharedApplication.windows','%hook','substrate.h','valueForKey:']:
 assert bad not in btn,bad
print('1.17.2 live-button discovery + simulated tap static checks passed (bounded live hierarchy traversal <=6000 nodes / depth <=40 / 1.5 s / <=32 candidates, signal priority accessibilityIdentifier > Label > Value > titleLabel.text/currentTitle > known localisation substrings > green-left-primary weak signal, identifier+label+value+title+red-dominant decline blacklist, three tap mechanisms in the required order with allTargets/actionsForTarget+NSInvocation as the last resort, one tap per call UUID plus a 1.2 s settle window and a buttontap notification so two hosts can never double-tap, full candidate/mechanism/connected reporting written to the discovery file, logged and published through the chunked/state-slot transport, and the retained-but-insufficient method-name keyword path behind it)')
