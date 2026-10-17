"""Static safeguards for the iOS 17.3 TelephonyUI diagnostic / Add replacement experiment.
This does not simulate UIKit, CallKit, audio focus, or an actual cellular call.
"""
from pathlib import Path
import plistlib
r=Path(__file__).resolve().parents[1]
s=(r/'AACStopOverlay.h').read_text();t=(r/'Tweak.x').read_text()
f=(r/'AutoAnswerCall.plist').read_text()
assert 'com.apple.InCallService' in f and 'com.apple.springboard' in f
assert 'Executables' not in f
assert 'TPSlidingButton' in s and 'TPPillView' in s
assert 'CALLUI inventory' in s and 'CALLUI window' in s and 'CALLUI add-accessor' in s
assert 'AACStopOverlayFindAddAccessor' in s and 'method_getNumberOfArguments(m)!=2' in s
assert 'AACStopOverlayVerifiedUUID' in s and 'age>12' in s
assert 'static inline NSUUID *AACStopOverlayVerifiedUUID(void){\n NSUUID *connected=AACStopOverlayConnectedUUID();' in s
assert '- (void)stopPressed:(id)sender{\n NSUUID *connected=AACStopOverlayVerifiedUUID();' in s
assert 'if(!optIn||!connected)' in s and 'if(!w||!native)' in s
assert '@"人工接管"' in s and 'AACAudioStopMatches(connected)' in s
assert 'reason=manual-takeover-before-play' in t
assert 'native.hidden=YES' in s and 'AACStopOverlayRestoreNative' in s
assert 'no geometry fallback' in s and 'return nil;' in s
assert 'AACAudioRequestManualStop(connected)' in s
assert 'CALLUI_BOOT 1.18.1 constructor' in t
assert 'SYSTEM_COMPANION passive-only' in t and 'SubmitBlock=nil;' in t
assert 'AACSBStart(env);' not in t
assert 'AUDIO_DIAG interruption' in t and 'AUDIO_DIAG route-change' in t
assert 'AACAudioPublishStatus(uuid,@"playing")' in t
assert 'AVAudioSessionCategoryOptionMixWithOthers' in t
assert 'LOCAL output only, never claims caller/uplink delivery' in t
print('PASS: filter, early-load marker, read-only TelephonyUI evidence, safe native control, playback heartbeat and audio interruption diagnostics')
