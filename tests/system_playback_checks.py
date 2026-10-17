"""Structural regressions for 1.17.6 system-answer/local-playback compatibility.
Does not claim compiled iOS binary, real-call success, or uplink injection.
"""
from pathlib import Path
import plistlib
root=Path(__file__).resolve().parents[1]
src=(root/'Tweak.x').read_text()
bridge=(root/'AACConfigBridge.h').read_text()
settings=(root/'Preferences/AACRootListController.m').read_text()
plist=plistlib.loads((root/'Preferences/Resources/Root.plist').read_bytes())
workflow=(root/'.github/workflows/build.yml').read_text()

assert not any(i.get('key')=='SystemAnswerPlaybackTest' for i in plist['items'])
assert any(i.get('key')=='PlayAudio' and '停止按钮' in i.get('label','') for i in plist['items'])
assert not any('footerText' in p or 'subtitle' in p for p in plist['items'])
assert '@"SystemAnswerPlaybackTest"' in settings
assert '@"SystemAnswerPlaybackTest"' in (root/'Preferences/AACLogExportController.h').read_text()
assert 'SystemAnswerPlaybackTest is a legacy key' in settings
assert 'for(NSString *key in @[@"Enabled",@"Mode",@"Delay",@"Whitelist",@"PlayAudio",@"SystemAnswerPlaybackTest",@"AudioPath"' in settings
assert 'for(NSString *k in @[@"Enabled",@"Mode",@"Delay",@"Whitelist",@"PlayAudio",@"SystemAnswerPlaybackTest"])' in bridge
assert 'if(!saved[@"SystemAnswerPlaybackTest"])saved[@"SystemAnswerPlaybackTest"]=@NO;' in bridge
assert '[readback[@"SystemAnswerPlaybackTest"] isEqual:saved[@"SystemAnswerPlaybackTest"]]' in bridge

# The ringing event has to be seen and policy-approved for system-mode playback.
assert 's[@"systemTestSeen"]=@YES;' in src
assert 's[@"systemTestEligible"]=@(eligible);' in src
assert 'BOOL eligible=Allowed(call,incomingPrefs);' in src
assert 'if([s[@"systemTestSeen"] boolValue])return;' in src
assert 'if(call.hasConnected){ObserveConnection(uuid,s);return;}' in src
assert 'systemTestActive&&testEligible&&[p[@"PlayAudio"] boolValue]' in src
assert '[ProcessTag isEqualToString:@"springboard"]&&![s[@"audioPlayed"] boolValue]' in src
assert 'BOOL alreadyConnected=[s[@"connectedObserved"] boolValue]' in src
assert 'if(alreadyConnected)return;' in src
assert 's[@"audioPlayed"]=@YES;' in src
assert 'BOOL played=PlayLocal(uuid);' in src
assert 'if([PlayerCallUUID isEqual:uuid])' in src

# Prevent plugin from attempting answer in this mode, including a delayed job begun before toggling.
assert 'if(AACSystemAnswerTestActive(incomingPrefs)){' in src
assert 'SYSTEM_ANSWER_TEST delayed plugin answer suppressed' in src
assert 'SYSTEM_ANSWER_TEST blocked plugin answer submission after mode change' in src
assert src.index('if(AACSystemAnswerTestActive(incomingPrefs)){') < src.index('s[@"scheduled"]=@YES;')
assert src.index('if(AACSystemAnswerTestActive(Prefs())){') < src.index('s[@"attempted"]=@YES;s[@"pending"]=@YES;')
assert 'BOOL legacyEligible=!systemTestActive&&![s[@"systemTestSeen"] boolValue]&&AACMayAutoplay(s);' in src

# Actual local decode/playback is guarded and reports each failed stage.
for step in ('stage=read','stage=decode','stage=prepare','stage=play','stage=exception','SYSTEM_ANSWER_TEST','AUDIO_TEST'):
 assert step in src,step
assert 'AVAudioPlayer' in src and 'prepareToPlay' in src and '[newPlayer play]' in src
assert 'LOCAL output only, never claims caller/uplink delivery' in src
assert 'setCategory:' not in src and 'setActive:' not in src
assert '[prefs[@"SystemAnswerPlaybackTest"] boolValue]' not in src
assert 'return ConfigValid&&!Stopped&&[prefs[@"Enabled"] boolValue];' in src

assert 'python3 tests/system_playback_checks.py' in workflow
assert 'Version: 1.17.6' in (root/'control').read_text()
assert 'PACKAGE_VERSION := 1.17.6' in (root/'Makefile').read_text()
assert 'test "$(dpkg-deb -f "$deb" Version)" = "1.17.6"' in workflow
print('PASS: system-managed answer and single opt-in playback switch, ringtone eligibility, no plugin answer in test mode, single SpringBoard host, one-shot local playback, shared settings and honest no-uplink logs')
