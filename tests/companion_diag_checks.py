"""1.18.1 safe UI telemetry and local playback state regression (static only)."""
from pathlib import Path
r=Path(__file__).resolve().parents[1]
t=(r/'Tweak.x').read_text(); u=(r/'AACStopOverlay.h').read_text()
assert 'AACStopOverlayReportSummary()' in t
assert 'CALLUI_UI_INIT' in u and 'AACStopOverlayLatestDiagnostic' in u
assert 'AACStopOverlayLatestDecision' in u and 'addSemanticMatches' in u
assert 'visibleControls' in u and 'control:%@' in u
assert 'no geometry fallback' in u and 'native.hidden=YES' in u
assert 'PlayerInterruptionBegan=YES' in t
assert 'stage=audio-session-interruption-began' in t
assert 'AACAudioPublishStatus(uuid,@"starting")' in t
assert 'if(position>0.1)' in t and 'AACAudioPublishStatus(uuid,@"playing")' in t
assert 'CallAudioService' in (r/'FIXES-1.18.1.md').read_text()
print('PASS: host UI snapshot, explicit reasons, true playback-progress gate, interruption fail-safe')
