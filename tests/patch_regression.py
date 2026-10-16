"""Regression source invariants for the 1.16.0 safety repairs; no device execution."""
from pathlib import Path
r=Path(__file__).resolve().parents[1]
s=(r/'AACChunkMsg.h').read_text()
a=(r/'Preferences/AACRootListController.m').read_text()
checks={
 'UTF-8 cap includes truncation marker': 'NSUInteger payloadBudget=cap-markerBytes;' in s,
 'truncation does not split Unicode clusters':'NSStringEnumerationByComposedCharacterSequences' in s,
 'name channel fits whole envelope':'AACChunkMsgFittedEnvelope(@"name",tag,kind,text,AACChunkMsgNameChannelMaxBytes' in s,
 'state channel fits whole envelope':'AACChunkMsgFittedEnvelope(@"state",tag,kind,text,AACChunkMsgMaxStateBytes' in s,
 'no silent state envelope cropping':'NSUInteger capped=envelopeData.length; /* never truncate a signed envelope */' in s,
 'header invalidated before writes':s.index('notify_set_state(headerToken,0ull)')<s.index('for(NSUInteger index=0;index<words;index++){',s.index('static inline NSDictionary *AACChunkMsgPublishStateChannel')),
 'only commit after slot success':'if(!allWritten)' in s and 'uint32_t commitStatus=notify_set_state(headerToken,commit)' in s,
 'reject malformed header length':'提交头长度 %lu 非法' in s,
 'reject concurrent header change':'confirmState!=hdrState' in s,
 'verify payload channel and host tag':'信封 tag/channel 与所读取的宿主状态槽不匹配' in s,
 'verify envelope piece count':'piecesField.unsignedIntegerValue!=expectedPieces' in s,
 'avoid duplicate ring entries':'if(![last[@"gen"] isEqual:@(gen)]' in s,
 'do not sum rounds indefinitely':'if(seq==1){[store[@"seqs"] removeAllObjects]' in s,
 'import selection warnings are not import failures':'NSMutableArray *warnings=[NSMutableArray new]' in a and 'warnings addObject:' in a,
}
for name,ok in checks.items():
 print(('PASS' if ok else 'FAIL')+': '+name)
assert all(checks.values()),'patch regression check failed'
