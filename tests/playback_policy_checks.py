"""1.17.8 static checks for replay of the actual Mode=1/PlayAudio=true log regression."""
from pathlib import Path
import plistlib
r=Path(__file__).resolve().parents[1]
t=(r/'Tweak.x').read_text()
p=(r/'AACPolicy.h').read_text()
ui=plistlib.loads((r/'Preferences/Resources/Root.plist').read_bytes())
w=(r/'.github/workflows/build.yml').read_text()
assert 'AACPlaybackRuleMatches' in p and '(mode==1||mode==2)' in p
assert 'AACShouldPlayForSystemConnection' in p
assert 'BOOL eligible=AACPlaybackRulesAllow(call,incomingPrefs,&policyReason);' in t
assert 'BOOL playbackRulesAllow=AACPlaybackRulesAllow(call,prefs,&policyReason);' in t
assert 'systemTestActive&&ringingSeen&&playbackRulesAllow&&playbackSwitch' in t
assert 'AUDIO_TEST result=skipped reason=playback-policy-rejected detail=' in t
assert 'BOOL legacyEligible=!systemTestActive&&![s[@"systemTestSeen"] boolValue]&&AACMayAutoplay(s);' in t
# The legacy answer request is NOT used for system-managed playback.
ring=t[t.index('if(AACSystemAnswerTestActive(incomingPrefs)){'):t.index('if([s[@"scheduled"] boolValue]')]
assert 'Allowed(call,incomingPrefs)' not in ring
connected=t[t.index('static void ObserveConnection('):t.index('/* Subscribe to UUID-specific peer signals')]
assert 'Allowed(' not in connected
assert 'if(alreadyConnected)return;' in connected
assert 's[@"audioPlayed"]=@YES;' in connected
assert 'AUDIO_TEST route before category=' in t and 'AVAudioSessionCategoryOptionMixWithOthers' in t
labels={i.get('key'):i for i in ui['items'] if i.get('key')}
assert labels['Mode']['validTitles']==['方案1：全部来电播放','方案2：排除名单以外的来电播放']
assert 'cc -std=c11 tests/playback_policy.c -lm' in w
assert 'python3 tests/playback_policy_checks.py' in w
assert '1.17.8' in (r/'control').read_text()
print('PASS: Mode 1 no longer uses legacy Mode-2-only Allowed(), connection revalidation, safer ring gate, read-only route diagnostics')
