"""Structural checks for iOS 17.3 native Add button replacement (not actual iOS tests)."""
from pathlib import Path
p=Path(__file__).resolve().parents[1]
s=(p/'AACStopOverlay.h').read_text();t=(p/'Tweak.x').read_text()
assert 'AACStopOverlayIsAddLabel' in s and '@"添加"' in s and '@"add call"' in s
assert 'AACStopOverlayNativeAdd' in s and 'AACStopOverlayRestoreNative' in s
assert 'native.hidden=YES' in s and 'AACStopOverlayNativeWasHidden' in s
assert 'AACStopOverlayWindow(&native,&frame)' in s and 'AACStopOverlayFindAdd' in s
assert 'AACStopOverlayHost' in s and '[w bringSubviewToFront:AACStopOverlayHost]' in s
assert 'UIControlEventTouchUpInside' in s and 'AACAudioRequestManualStop(connected)' in s
assert 'if(!connected||!optIn)' in s
assert 'call.hasConnected' in s and '!call.hasEnded' in s and '!call.outgoing' in s
assert 'elapsed<3.0' in t and 'audio-interrupted-or-session-suppressed' in t
assert 'AVAudioSessionCategoryPlayback' in t and 'AVAudioSessionCategoryOptionMixWithOthers' in t
assert 'configure-session' in t and 'activate-session' in t and 'session-restore' in t
assert 'LOCAL output only, never claims caller/uplink delivery' in t
assert 'Executables' in (p/'AutoAnswerCall.plist').read_text()
print('PASS: reversible native Add cover, connected-only control, UUID stop request, audio startup grace and session restoration')
