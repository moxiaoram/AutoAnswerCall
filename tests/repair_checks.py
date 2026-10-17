"""Focused source-level regression checks for the 1.17.2 fixes.

These are not a substitute for compiling with Theos or making a real incoming call.
"""
from pathlib import Path
import plistlib
import re

root = Path(__file__).resolve().parents[1]
button = (root / 'AACButtonScan.h').read_text()
tweak = (root / 'Tweak.x').read_text()
records = (root / 'AACRecords.h').read_text()
plist = plistlib.loads((root/'Preferences/Resources/Root.plist').read_bytes())

# Tap signal identity must contain BOTH remote host and this exact call UUID.
assert 'return [NSString stringWithFormat:@"%@%@.%@",AACButtonTapPrefix,tag,uuid];' in button
assert 'notify_post(AACButtonTapNameForCall(tag,uuid).UTF8String)' in button
assert 'NSDate *when=AACButtonTapSeen?AACButtonTapSeen[AACButtonPeerKey(tag,uuid)]:nil' in button
assert 'AACButtonPeerTapped(higherPriorityTags,uuid)' in button
assert 'notify_register_dispatch(notification.UTF8String,&token' in tweak
assert 'AACButtonTapNameForCall(peerTag,uuid.UUIDString)' in tweak
assert 'AACButtonNotePeerTap(peerTag,uuid.UUIDString)' in tweak
assert 'AACWatchPeerTaps(uuid,s)' in tweak
assert 'AACUnwatchPeerTaps(uuid,s)' in tweak
assert 'notify_cancel(token.intValue)' in tweak
assert 'for(NSString *tapName in AACButtonTapNames())' not in tweak

# An unsuccessful mechanism returns the UUID claim to the pool; do not record success
# because sendActions threw an exception or a registered handler never existed.
assert 'if(!mechanism){AACButtonUnclaimTapUUID(uuid);' in button
assert 'if(upSent){' in button and 'if(downSent){' in button
assert 'if(pairsDown.count && !pairsUp.count)' in button
assert 'if(!Allowed(liveCall,Prefs()))' in tweak
assert '已尝试按钮动作但未观察到连接' in records
assert '未触发自动接听（查看详情）' in records

# User requested removal of grey explanatory hints; diagnostics stay in row contents.
assert not any('footerText' in entry or 'subtitle' in entry for entry in plist['items'])
for name in ['AACRecordsController.h','AACProbeController.h','AACLogExportController.h',
             'AACChunkMsgController.h','AACLogViewerController.h']:
    txt=(root/'Preferences'/name).read_text()
    assert '- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section{return nil;}' in txt,name
assert 'cell.detailTextLabel.text=' in (root/'Preferences/AACProbeController.h').read_text()
assert 'PACKAGE_VERSION := 1.17.7' in (root/'Makefile').read_text()
assert 'Version: 1.17.7' in (root/'control').read_text()
assert 'runs-on: macos-15' in (root/'.github/workflows/build.yml').read_text()
print('PASS: 1.17.2 fixes (UUID-specific notifications, claim rollback, event exceptions, settings recheck, outcome clarity, grey footers removed)')
