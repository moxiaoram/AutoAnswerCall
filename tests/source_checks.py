from pathlib import Path
import plistlib
r=Path(__file__).resolve().parents[1];t=(r/'Tweak.x').read_text();s=(r/'Preferences/AACRootListController.m').read_text()
for bad in ['%hook','IOBluetooth','CTCall','hasOutgoing','CXCallUpdate','/var/jb','valueForKey:']:
 assert bad not in t,bad
for good in ['CXAnswerCallAction','requestTransaction:tx','callChanged:(CXCall *)call','Current(uuid)','Allowed(live,Prefs())','s[@"pending"]','method_getReturnType','method_getNumberOfArguments']:
 assert good in t,good
for good in ['asCopy:YES','NSFileCoordinator','startAccessingSecurityScopedResource','stopAccessingSecurityScopedResource','Limit+1','NSApplicationSupportDirectory','SETTINGS','PHONE']:
 assert good in s+t,good
p=plistlib.loads((r/'Preferences/Resources/Root.plist').read_bytes());mode=next(i for i in p['items'] if i.get('key')=='Mode');assert mode['default']==2 and mode['cell']=='PSLinkListCell' and mode['validValues']==[1,2]
assert 'com.apple.MobilePhone' in (r/'AutoAnswerCall.plist').read_text()
delay=next(i for i in p['items'] if i.get('key')=='Delay');assert delay['cell']=='PSEditTextCell' and delay['get']=='readDelay:' and delay['set']=='setDelay:specifier:'
assert 'PSSliderCell' not in str(p)
for good in ['AACParseDelay(text.UTF8String','setBool:NO forKey:@"Enabled"','com.autoanswer.call.stop','allowsMultipleSelection=YES','NSUUID.UUID.UUIDString','dispatch_sync(dispatch_get_main_queue()','showAudioLibrary:']:
 assert good in s,good
for good in ['generation!=StopGeneration','Initial observer snapshot is diagnostic only','NOT measured audible ringing','!live||!Allowed(live,Prefs())']:
 assert good in t,good
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
print('PASS: transactions, mode2 exclusions, finite seconds, stop generations, bounded multiselect import, library schema/migration/delete guards, native accessor ABI guards (static checks, NOT device runtime)')
