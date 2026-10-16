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
# 1.10.0: the filter must ship BOTH official, case-sensitive bundle ids and must never
# carry the historical wrong-case phone id. The tweak may still accept the wrong-case id
# and the process name at runtime as compatibility fallbacks.
filter_text=(r/'AutoAnswerCall.plist').read_text()
assert 'com.apple.mobilephone' in filter_text, 'filter must carry the official lowercase phone id'
assert 'com.apple.springboard' in filter_text, 'filter must carry com.apple.springboard'
assert 'MobilePhone' not in filter_text, 'filter must not carry any wrong-case/MobilePhone identifier'
assert re.findall(r'"([^"]+)"',filter_text)==['com.apple.mobilephone','com.apple.springboard'],re.findall(r'"([^"]+)"',filter_text)
assert 'isEqualToString:@"com.apple.mobilephone"' in t and '[process isEqualToString:@"MobilePhone"]' in t
assert 'isEqualToString:@"com.apple.springboard"' in t and 'inSpringBoardProcess' in t
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
# SpringBoard runtime inventory: real enumeration, bounded, no hooks
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
# no invented Apple preference domains/keys anywhere in the new evidence code: the only
# CFPreferences domains used are our own, and no Apple accessor/key name is referenced.
for text in (shared,probe,inv):
 assert 'callAudioRouting' not in text
 assert 'com.apple.' not in text
 assert 'AXSettings' not in text
assert 'com.autoanswer.call.sharelog' in shared and 'com.autoanswer.call.probe' in shared

# ---- 1.11.0: SpringBoard runtime discovery + dynamic hook answer path ----
sb=(r/'AACSpringBoard.h').read_text()
pstr=(r/'Preferences/Resources/Root.plist').read_text()
for good in ['objc_getClassList','class_copyMethodList','method_getImplementation','method_setImplementation','method_getNumberOfArguments','method_getReturnType','AACSBAnswerHook','AACSBOriginalFor','AACSBInvoking','AACSBDepth','AACSBWeakTarget','AACSBStrongTarget','AACSBRescan','AACSBInvokeDiscovered','AACSBHookedIMPs','AACSBHookCap=24','AACSBClassCap=400','AACSBSelectorCap=12','AACSBRetryDiscoveryIfEmpty','AACSBWriteDiscoveryFile','AACSBStart','runtime-discovered','discovery.txt','仅日志','AACSBRecord','AACSBSelectorMatches']:
 assert good in sb,good
# candidate classes are discovered from the real runtime; the keyword list must stay broad
for good in ['IncomingCall','CallAlert','CallToAction','CallPresentation','InCall','SBInCall','LockScreenCall','AnswerCall','CallController','CallUI','answer','accept','pickup']:
 assert good in sb,good
# ABI is proven before hooking: exactly (self,_cmd) and a void return, so the fixed-signature
# interposer is safe; nothing else is ever hooked.
assert "if(arguments!=2){" in sb and "if(returnType[0]!='v'){" in sb
# never hook the same method/IMP twice
assert 'AACSBHookedKeys' in sb and 'AACSBHookedIMPs' in sb and '绝不重复挂钩' in sb
# recursion guard + original IMP per (class,selector) + direct original-IMP invocation
assert 'AACSBInvoking' in sb and 'AACSBOriginalFor' in sb and 'recursion guard' in sb
# the answer path may not depend on any hardcoded private class name
for bad in ['NSClassFromString','SBIncomingCallViewController','SBCallAlertViewController','IncomingCallViewController','SBInCallPresentationManager','SBLockScreenCallController','%hook','substrate.h','MSHookMessageEx']:
 assert bad not in sb,bad
# policy/answer wiring in Tweak.x
for good in ['SubmitBlock','if(SubmitBlock){SubmitBlock(uuid,s);}else{','RegisterControls();','AACSBStart(env)','SpringBoardStart(ProcessTag)','AACSBRetryDiscoveryIfEmpty()','AACSBEnv *env=[AACSBEnv new]','com.autoanswer.call.pong.springboard','LOG-ONLY primary path','已调用运行时发现的 UI 接听方法（尚未确认接通）','未发现可调用的 UI 接听路径']:
 assert good in t,good
assert sb.count('AACSBAnswerHook')>=4
# phone module keeps its 1.9.x/1.10.0 behaviour byte-for-byte
assert 'Loaded 1.11.0 evidence build; retained CXCallObserver in MobilePhone' in t
assert 'inPhoneProcess' in t and 'ProcessTag=@"mobilephone";' in t
# settings side shows the runtime-discovered result and never invents one
for good in ['AACDiscoveryEntry','aac-springboard.discovery.txt','runtime-discovered','AACCountOccurrences','没有可读的发现文件','showDiscovery:']:
 assert good in pc or good in s or good in pstr,good
assert 'showDiscovery:' in pstr and 'showDiscovery:' in s
# version bumped everywhere, package id unchanged, filter untouched
assert 'Version: 1.11.0' in (r/'control').read_text() and 'Package: com.autoanswer.call' in (r/'control').read_text()
assert 'PACKAGE_VERSION := 1.11.0' in (r/'Makefile').read_text()
assert 'SpringBoard MobilePhone' in (r/'Makefile').read_text()
assert '1.11.0' in (r/'README.md').read_text() and '1.11.0' in pstr
assert 'config[@"Version"]=@"1.11.0";' in s

print('PASS: transactions, mode2 exclusions, finite seconds, stop generations, bounded multiselect import, library schema/migration/delete guards, native accessor ABI guards, 1.10.0 evidence channel (two-bundle filter, per-process probe, bounded SB inventory, per-path log reporting) plus 1.11.0 SpringBoard runtime discovery (broad candidate classes, ABI-proven dynamic hooks, per-method original IMP, recursion guard, weak capture + hierarchy re-scan, explicit log-only fallback) - static checks only, NOT device runtime')
