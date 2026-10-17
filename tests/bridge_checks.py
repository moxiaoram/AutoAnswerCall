"""Release-time source regressions for the Settings/host configuration bridge and local playback.
Not a substitute for actual RootHide sandbox, call, and audio-uplink testing.
"""
from pathlib import Path
import plistlib
r=Path(__file__).resolve().parents[1]
t=(r/'Tweak.x').read_text()
bridge=(r/'AACConfigBridge.h').read_text()
life=(r/'AACCallLifecycle.h').read_text()
settings=(r/'Preferences/AACRootListController.m').read_text()
audio=(r/'Preferences/AACAudioLibrary.h').read_text()
plist=plistlib.loads((r/'Preferences/Resources/Root.plist').read_bytes())
assert 'runtime-config.plist' in bridge and 'AACBridgeRead' in bridge
assert 'AACBridgePublish' in bridge and 'ConfigVersion' in bridge
assert 'writeToFile:AACBridgeConfigPath() atomically:YES' in bridge
assert 'saved[@"AudioPath"]=destination' in bridge
assert 'data.length!=size' in bridge and 'size>5*1024*1024' in bridge
assert 'ConfigValid=(bridged!=nil)' in t and 'if(!ConfigValid)' in t
assert 'CONFIG_DIAG host=%@' in t and 'audioReadable=%d' in t
assert 'AACBridgePublishSettings()' in settings and 'AACBridgePublishSettings()' in audio
for key in ('Enabled','Mode','Whitelist','PlayAudio'):
 item=next(item for item in plist['items'] if item.get('key')==key)
 assert item.get('get')=='readSharedValue:' and item.get('set')=='setSharedValue:specifier:'
assert 'NSString *bridgeError=AACBridgePublishSettings();' in settings
assert 'if(![state[@"buttonTapped"] boolValue])state[@"audioSuppressed"]=@YES' in life
assert '[state[@"connectedObserved"] boolValue]' in life and '![state[@"audioPlayed"] boolValue]' in life
assert 'state[@"ownershipConfirmed"]' not in life
assert 's[@"audioPlayed"]=@YES;' in t
assert 'if(alreadyConnected)return;' in t
assert 'if([PlayerCallUUID isEqual:uuid]){' in t
assert 'LOCAL output only, never claims caller/uplink delivery' in t
assert 'AUDIO_TEST result=' in t and 'isReadableFileAtPath' in t
assert not any('footerText' in item or 'subtitle' in item for item in plist['items'])
print('PASS: configuration bridge, settings synchronization, audio copy/readback, one-shot local playback gating, honest no-uplink diagnostics')
