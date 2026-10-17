"""1.18.1: safety and integration regression (source checks, not device validation)."""
from pathlib import Path
import plistlib
r=Path(__file__).resolve().parents[1]
s=(r/'Tweak.x').read_text(); d=(r/'AACPCMDecoder.h').read_text(); a=(r/'AACUplinkAdapter.h').read_text()
p=(r/'Preferences/Resources/Root.plist')
items=plistlib.loads(p.read_bytes())['items']
assert any(x.get('key')=='UplinkPCMProbe' and x.get('default') is False for x in items)
assert 'AACPCMProbeFile' in s and 'AACStartPCMProbe' in s
assert 'UPLINK_PCM_PROBE' in s and 'decoded-only' in d
assert 'ExtAudioFileOpenURL' in d and 'ExtAudioFileRead' in d
assert 'AACPCMQueuePush' in d and 'AACPCMQueuePop' in d
assert 'AACUplinkSubmitPCM' in a and 'return NO; /* failure is intentional' in a
assert 'sentFrames' in d and 'remoteAudible' in d and '@NO' in d
assert 'if(pcmProbeMode)' in s and 'PlayLocal(uuid)' in s
assert 'AACBridgePublish' in (r/'AACConfigBridge.h').read_text()
assert 'UplinkPCMProbe' in (r/'AACConfigBridge.h').read_text()
assert 'UplinkPCMProbe' in (r/'Preferences/AACRootListController.m').read_text()
assert '-framework AudioToolbox' in (r/'.github/workflows/build.yml').read_text()
print('PASS: fail-closed PCM probe, explicit opt-in, shared settings and decoder smoke harness')
