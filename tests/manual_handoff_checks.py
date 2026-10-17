"""Static regression checks for manual handoff, no claims about a real iPhone."""
from pathlib import Path
import plistlib
r=Path(__file__).resolve().parents[1]
t=(r/'Tweak.x').read_text()
h=(r/'AACAudioHandoff.h').read_text()
o=(r/'AACStopOverlay.h').read_text()
pl=plistlib.loads((r/'Preferences/Resources/Root.plist').read_bytes())
w=(r/'.github/workflows/build.yml').read_text()
assert 'AACAudioStopRequested' in h and 'AACAudioStateChanged' in h
assert 'playback-state.plist' in h and 'playback-stop-request.plist' in h
assert 'AACAudioValidEvent' in h and 'timestamp' in h
assert 'initWithUUIDString' in h
assert 'AACAudioPublishStatus' in h and 'AACAudioRequestManualStop' in h
assert 'AACAudioStopMatches' in h and 'writeToFile:path atomically:YES' in h
assert 'if(ok)notify_post' in h, 'publish only after writing a matching UUID to disk'
assert 'AACStopOverlayConnectedUUID' in o and 'call.hasConnected' in o and '!call.hasEnded' in o
assert 'AACStopOverlayWindow' in o and 'w.rootViewController' in o and 'w.isKeyWindow' in o
assert 'if(!optIn||!connected)' in o and 'AACStopOverlayRemove()' in o
assert 'AACManualStopAudioButton' in o and 'UIControlEventTouchUpInside' in o
assert 'AACAudioRequestManualStop(connected)' in o
assert 'stopRequestWritten=%d' in o and 'ACK timeout' in o and '正在停止' in o
assert 'AACAudioStopMatches(uuid)' in t and 'AACAudioStopMatches(owned)' in t
assert 'if([ProcessTag isEqualToString:@"springboard"])' in t
assert 'if([ProcessTag isEqualToString:@"incall"])' in t
assert 'AACStopOverlayStart(Observer,' in t and 'AACAudioPlaybackWatch(uuid)' in t
assert 'AACAudioStopOwned(@"UI-button-stop-request",@"stopped")' in t
assert 'AACAudioStopOwned(@"call-ended",@"ended")' in t
assert 'AACAudioStopOwned(@"settings-stop-plugin",@"stopped")' in t
assert 'PlayerCallUUID=uuid;' in t and 'if([PlayerCallUUID isEqual:uuid])' in t
assert 'BOOL legacyEligible=!systemTestActive&&![s[@"systemTestSeen"] boolValue]' in t
assert all('footerText' not in i and 'subtitle' not in i for i in pl['items'])
assert not any(i.get('key')=='SystemAnswerPlaybackTest' for i in pl['items'])
assert 'python3 tests/manual_handoff_checks.py' in w
assert '1.17.9' in (r/'Makefile').read_text() and '1.17.9' in (r/'control').read_text()
assert 'LOCAL output only, never claims caller/uplink delivery' in t
print('PASS: call-UUID-scoped stop request, in-call native Add replacement, owner ACK, retry, fallback polling, no cross-call stop, no cellular-uplink claim')
