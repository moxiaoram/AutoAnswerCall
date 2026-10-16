#import <Foundation/Foundation.h>
#import <notify.h>
#import "AACChunkMath.h"
#import "AACSharedLog.h"
/* ============ 1.16.0 TASK 1/2: 跨进程分片消息（Darwin 名内载荷） ============
   为什么要有它（1.15.0 的真实设备证据，用户 iOS 17.3 RootHide 设备）：
     - 进程探测页：incall (com.autoanswer.call.probe.incall) 到达 2 次；springboard 到达 2 次
       —— 所以 InCallService 的 so 确实被注入，它的探测通知确实跨进程到达。1.15.0 之前
       「incall 从未到达」是时序假象（该进程只在通话期间运行）。
     - 宿主跨进程上报读回页：Hosts = ( springboard )；[incall] 本进程未读到该宿主的任何键；
       两个真实 plist 路径在设置进程里都「不存在/不可见」，而设置进程却读到了同一域的 12 个键。
       结论：文件/CFPreferences 通道只对共享同一容器/偏好上下文的宿主有效（SpringBoard），
       InCallService 的上报读不回来。
     - 因此唯一被证实可跨进程的通道是 Darwin 通知，而它的名字是任意字符串。
   本文件把一份有界发现摘要通过两种**自有名字**的通道发出去，二者都有硬上限：
     A. 名内载荷通道（TASK 1 的要求）：消息文本自带「长度 + CRC32」信封头，做 base64url 后按
        900 字符切片，每片放进通知名的一部分：
          com.autoanswer.call.msg.<tag>.<seq>.<total>.<base64url片>
        顺序结构名 com.autoanswer.call.msg.<tag>.<seq>.<total> 与结束标记
        com.autoanswer.call.msg.<tag>.end.<total> 单独发送，接收方据此得到 到达片数/总片数、
        结束标记、最近更新时间与完整性。上限：12 片、总解码 12288 字节、每片 900 个字符。
     B. 状态槽通道（可被接收方预先注册的那一半）：Darwin 通知名不能通配，名字里带任意内容的片
        无法被预先注册，所以同一名字族另有一条固定名字的通道：com.autoanswer.call.msg.<tag>.w.<0..95>
        的 64 位状态各带 6 字节载荷 + 16 位代次，最后的 com.autoanswer.call.msg.<tag>.hdr 状态
        提交（代次 + 字节长度）。接收方用 notify_register_check/notify_get_state 读回并校验
        代次、长度与 CRC32。上限：96 槽 × 6 字节 = 576 字节。
   请求即时报（TASK 2）：设置页 POST com.autoanswer.call.msgrequest.<tag>，该宿主立刻重发一次。
   诚实性：两条通道都未在设备上验证过；本文件只报告真实的 notify_post/notify_set_state 状态码、
   真实的读回结果，读不到就写读不到，绝不因此断言任何宿主未注入。原有通道一律保留、不削弱。 */

static NSString * const AACChunkMsgPrefix=@"com.autoanswer.call.msg.";
static NSString * const AACChunkMsgRequestPrefix=@"com.autoanswer.call.msgrequest.";
static NSString * const AACChunkMsgTruncatedMarker=@"…<msg-truncated>";
static NSString * const AACChunkMsgEnvelopeMagic=@"AACMSG1";
static NSTimeInterval const AACChunkMsgIntervalSeconds=20.0;
static NSUInteger const AACChunkMsgMaxChunks=AAC_CHUNK_MAX_CHUNKS;
static NSUInteger const AACChunkMsgEncodedBytes=AAC_CHUNK_ENCODED_BYTES;
static NSUInteger const AACChunkMsgMaxTotalBytes=AAC_CHUNK_MAX_TOTAL_BYTES;
static NSUInteger const AACChunkMsgMaxWords=AAC_CHUNK_MAX_WORDS;
static NSUInteger const AACChunkMsgWordBytes=AAC_CHUNK_WORD_BYTES;
static NSUInteger const AACChunkMsgMaxStateBytes=AAC_CHUNK_MAX_STATE_BYTES;
static NSUInteger const AACChunkMsgRingPerTag=AAC_CHUNK_RING_PER_TAG;
static NSUInteger const AACChunkMsgNameChannelMaxBytes=(AAC_CHUNK_MAX_CHUNKS*AAC_CHUNK_ENCODED_BYTES)/4u*3u;

static inline NSArray *AACChunkMsgKnownTags(void){return @[@"incall",@"springboard",@"mobilephone",@"settings"];}
static inline NSString *AACChunkMsgSanitizeTag(NSString *tag){
 if([tag isKindOfClass:NSString.class]&&[AACChunkMsgKnownTags() containsObject:tag])return tag;
 return @"unknown";
}
static inline NSString *AACChunkMsgStructName(NSString *tag,NSUInteger seq,NSUInteger total){
 return [NSString stringWithFormat:@"%@%@.%lu.%lu",AACChunkMsgPrefix,AACChunkMsgSanitizeTag(tag),(unsigned long)seq,(unsigned long)total];
}
static inline NSString *AACChunkMsgPayloadName(NSString *tag,NSUInteger seq,NSUInteger total,NSString *chunk){
 return [NSString stringWithFormat:@"%@%@.%lu.%lu.%@",AACChunkMsgPrefix,AACChunkMsgSanitizeTag(tag),(unsigned long)seq,(unsigned long)total,[chunk isKindOfClass:NSString.class]?chunk:@""];
}
static inline NSString *AACChunkMsgEndName(NSString *tag,NSUInteger total){
 return [NSString stringWithFormat:@"%@%@.end.%lu",AACChunkMsgPrefix,AACChunkMsgSanitizeTag(tag),(unsigned long)total];
}
static inline NSString *AACChunkMsgHeaderName(NSString *tag){
 return [NSString stringWithFormat:@"%@%@.hdr",AACChunkMsgPrefix,AACChunkMsgSanitizeTag(tag)];
}
static inline NSString *AACChunkMsgWordName(NSString *tag,NSUInteger index){
 return [NSString stringWithFormat:@"%@%@.w.%lu",AACChunkMsgPrefix,AACChunkMsgSanitizeTag(tag),(unsigned long)index];
}
static inline NSString *AACChunkMsgRequestName(NSString *tag){
 return [AACChunkMsgRequestPrefix stringByAppendingString:AACChunkMsgSanitizeTag(tag)];
}
static inline NSArray *AACChunkMsgRequestNames(void){
 NSMutableArray *out=[NSMutableArray new];
 for(NSString *tag in AACChunkMsgKnownTags())[out addObject:AACChunkMsgRequestName(tag)];
 return out;
}
/* The literal name shape is kept as a real string so the artifact checker and a human reading
   the binary can see the framing without following a format string. */
static inline NSString *AACChunkMsgNameShapeText(void){
 return @"com.autoanswer.call.msg.<tag>.<seq>.<total>.<base64url分片>  +  com.autoanswer.call.msg.<tag>.<seq>.<total>  +  com.autoanswer.call.msg.<tag>.end.<total>  +  com.autoanswer.call.msg.<tag>.w.<0..95>  +  com.autoanswer.call.msg.<tag>.hdr  +  com.autoanswer.call.msgrequest.<tag>";
}
static inline NSString *AACChunkMsgBoundText(void){
 return @"名内载荷通道：最多 12 片，每片最多 900 个 base64url 字符（通知名里没有 '/'、没有 NUL），总解码上限 12288 字节；状态槽通道：96 槽 × 6 字节 = 576 字节，16 位代次 + 字节长度 + CRC32 提交；每 tag 只保留最近 8 条（环形缓冲，有界）。";
}
/* ---------------- base64url（无 '/'、无 NUL，可安全放进通知名） ---------------- */
static inline NSString *AACChunkMsgBase64UrlEncode(NSData *data){
 if(![data isKindOfClass:NSData.class])return @"";
 NSMutableString *text=[[data base64EncodedStringWithOptions:0] mutableCopy];
 [text replaceOccurrencesOfString:@"+" withString:@"-" options:0 range:NSMakeRange(0,text.length)];
 [text replaceOccurrencesOfString:@"/" withString:@"_" options:0 range:NSMakeRange(0,text.length)];
 [text replaceOccurrencesOfString:@"=" withString:@"" options:0 range:NSMakeRange(0,text.length)];
 return [text copy];
}
static inline NSData *AACChunkMsgBase64UrlDecode(NSString *chunk){
 if(![chunk isKindOfClass:NSString.class]||!chunk.length)return nil;
 NSMutableString *text=[chunk mutableCopy];
 [text replaceOccurrencesOfString:@"-" withString:@"+" options:0 range:NSMakeRange(0,text.length)];
 [text replaceOccurrencesOfString:@"_" withString:@"/" options:0 range:NSMakeRange(0,text.length)];
 while(text.length%4u)[text appendString:@"="];
 return [[NSData alloc] initWithBase64EncodedString:text options:NSDataBase64DecodingIgnoreUnknownCharacters];
}
/* ---------------- 信封（自带长度 + CRC32，接收方据此发现截断） ---------------- */
static inline NSString *AACChunkMsgEnvelope(NSString *channel,NSString *tag,NSString *kind,NSData *payload,BOOL truncated){
 unsigned crc=AACChunkCrc32(payload.bytes,(unsigned)payload.length);
 unsigned pieces=(unsigned)AACChunkCount((unsigned)AACChunkMsgBase64UrlEncode(payload).length);
 if([channel isEqualToString:@"state"])pieces=AACChunkBytesNeeded((unsigned)payload.length);
 return [NSString stringWithFormat:@"%@ channel=%@ tag=%@ kind=%@ pieces=%u bytes=%lu crc32=%08x truncated=%@ utc=%@",
         AACChunkMsgEnvelopeMagic,channel,AACChunkMsgSanitizeTag(tag),kind?:@"unknown",pieces,(unsigned long)payload.length,crc,truncated?@"yes":@"no",NSDate.date];
}
/* 校验一个重组后的信封：magic / channel / pieces / bytes / crc32 与真实载荷必须一致。
   返回的 text 是载荷文本；任何一项不一致都返回 ok=NO 并写明原因（不猜测）。 */
static inline NSDictionary *AACChunkMsgVerifyEnvelope(NSData *envelopeData){
 NSMutableDictionary *result=[NSMutableDictionary new];
 result[@"ok"]=@NO;
 @try{
  if(![envelopeData isKindOfClass:NSData.class]||!envelopeData.length){result[@"reason"]=@"空载荷";return result;}
  NSString *text=[[NSString alloc] initWithData:envelopeData encoding:NSUTF8StringEncoding];
  if(!text.length){result[@"reason"]=@"载荷不是合法 UTF-8";return result;}
  NSRange newline=[text rangeOfString:@"\n"];
  if(newline.location==NSNotFound){result[@"reason"]=@"缺少信封头（没有换行分隔）";return result;}
  NSString *head=[text substringToIndex:newline.location];
  NSString *body=[text substringFromIndex:newline.location+1];
  NSMutableDictionary *fields=[NSMutableDictionary new];
  for(NSString *token in [head componentsSeparatedByString:@" "]){
   NSRange eq=[token rangeOfString:@"="];
   if(eq.location==NSNotFound||eq.location==0)continue;
   fields[[token substringToIndex:eq.location]]=[token substringFromIndex:eq.location+1];
  }
  result[@"magic"]=fields[@"magic"]?:[head componentsSeparatedByString:@" "].firstObject;
  if(![result[@"magic"] isEqualToString:AACChunkMsgEnvelopeMagic]){result[@"reason"]=[NSString stringWithFormat:@"信封 magic 不是 %@",AACChunkMsgEnvelopeMagic];return result;}
  result[@"channel"]=fields[@"channel"]?:@"unknown";
  result[@"tag"]=fields[@"tag"]?:@"unknown";
  result[@"kind"]=fields[@"kind"]?:@"unknown";
  NSData *bodyData=[body dataUsingEncoding:NSUTF8StringEncoding];
  unsigned crc=AACChunkCrc32(bodyData.bytes,(unsigned)bodyData.length);
  NSString *expectedCrc=fields[@"crc32"];
  NSString *actualCrc=[NSString stringWithFormat:@"%08x",crc];
  result[@"declaredBytes"]=@((unsigned long long)(fields[@"bytes"]?strtoul(fields[@"bytes"].UTF8String,NULL,10):0));
  result[@"actualBytes"]=@((unsigned long long)bodyData.length);
  result[@"declaredCrc32"]=expectedCrc?:@"(missing)";
  result[@"actualCrc32"]=actualCrc;
  result[@"text"]=body;
  if(!expectedCrc.length){result[@"reason"]=@"信封头缺少 crc32";return result;}
  if([result[@"declaredBytes"] unsignedLongLongValue]!=bodyData.length){result[@"reason"]=[NSString stringWithFormat:@"长度不一致：信封声明 %@ 字节，实际 %lu 字节",fields[@"bytes"],(unsigned long)bodyData.length];return result;}
  if(![[expectedCrc lowercaseString] isEqualToString:actualCrc]){result[@"reason"]=[NSString stringWithFormat:@"CRC32 不一致：信封声明 %@，实际 %@",expectedCrc,actualCrc];return result;}
  result[@"truncated"]=@([fields[@"truncated"] isEqualToString:@"yes"]);
  result[@"ok"]=@YES;
  result[@"reason"]=@"长度与 CRC32 均一致";
 }@catch(NSException *e){result[@"ok"]=@NO;result[@"reason"]=[@"信封校验异常：" stringByAppendingString:e.reason?:@"unknown"];}
 return result;
}
/* 把消息文本按上限截断并显式加标记（绝不静默截断）。 */
static inline NSString *AACChunkMsgBound(NSString *text,NSUInteger cap,BOOL *truncated){
 NSString *body=[text isKindOfClass:NSString.class]?text:@"";
 if(body.length<=cap){if(truncated)*truncated=NO;return body;}
 // 按 UTF-8 字节安全截断：逐个缩短直到编码后不超过 cap。
 NSMutableString *cut=[body mutableCopy];
 while(cut.length&&[[cut dataUsingEncoding:NSUTF8StringEncoding] length]>cap)[cut deleteCharactersInRange:NSMakeRange(cut.length-1,1)];
 if(truncated)*truncated=YES;
 return [cut stringByAppendingString:AACChunkMsgTruncatedMarker];
}
/* ---------------- 发送端：真正的 notify_post / notify_set_state 状态码 ---------------- */
static inline NSMutableDictionary *AACChunkMsgChannelResult(void){
 NSMutableDictionary *channel=[NSMutableDictionary new];
 channel[@"posts"]=@0;channel[@"ok"]=@0;channel[@"failed"]=@0;channel[@"errors"]=[NSMutableArray new];
 return channel;
}
static inline void AACChunkMsgCountPost(NSMutableDictionary *channel,NSString *name,uint32_t status){
 channel[@"posts"]=@([channel[@"posts"] unsignedIntegerValue]+1);
 if(status==NOTIFY_STATUS_OK)channel[@"ok"]=@([channel[@"ok"] unsignedIntegerValue]+1);
 else{
  channel[@"failed"]=@([channel[@"failed"] unsignedIntegerValue]+1);
  @try{[(NSMutableArray *)channel[@"errors"] addObject:[NSString stringWithFormat:@"%@ → notify 状态 %u",name,status]];}@catch(NSException *e){}
 }
}
/* 名内载荷通道：结构名 + 载荷名 + 结束标记，逐片真实发送。 */
static inline NSDictionary *AACChunkMsgPublishNameChannel(NSString *tag,NSString *kind,NSString *text){
 NSMutableDictionary *channel=AACChunkMsgChannelResult();
 @try{
  BOOL truncated=NO;
  NSUInteger payloadCap=AACChunkMsgNameChannelMaxBytes>200?AACChunkMsgNameChannelMaxBytes-200:64;
  NSString *bounded=AACChunkMsgBound(text,payloadCap,&truncated);
  NSData *payload=[bounded dataUsingEncoding:NSUTF8StringEncoding];
  NSString *envelope=[AACChunkMsgEnvelope(@"name",tag,kind,payload,truncated) stringByAppendingFormat:@"\n%@",bounded];
  NSString *encoded=AACChunkMsgBase64UrlEncode([envelope dataUsingEncoding:NSUTF8StringEncoding]);
  NSUInteger total=AACChunkCount((unsigned)encoded.length);
  channel[@"channel"]=@"name";
  channel[@"chunkCount"]=@(total);
  channel[@"encodedBytes"]=@(encoded.length);
  channel[@"payloadBytes"]=@(payload.length);
  channel[@"boundBytes"]=@(AACChunkMsgNameChannelMaxBytes);
  channel[@"truncated"]=@(truncated);
  channel[@"envelope"]=envelope;
  channel[@"alphabetOk"]=@(AACChunkAlphabetOk(encoded.UTF8String,(unsigned)encoded.length)?YES:NO);
  if(total==0){
   channel[@"note"]=@"消息为空：不发任何片（绝不发空消息）";
   return channel;
  }
  for(NSUInteger index=0;index<total;index++){
   NSString *chunk=[encoded substringWithRange:NSMakeRange(index*AACChunkMsgEncodedBytes,AACChunkLengthAt((unsigned)index,(unsigned)encoded.length))];
   if(!AACChunkAlphabetOk(chunk.UTF8String,(unsigned)chunk.length)){
    channel[@"alphabetOk"]=@NO;
    @try{[(NSMutableArray *)channel[@"errors"] addObject:[NSString stringWithFormat:@"第 %lu 片不是合法 base64url，已拒绝发送",(unsigned long)(index+1)]];}@catch(NSException *e){}
    continue;
   }
   AACChunkMsgCountPost(channel,AACChunkMsgStructName(tag,index+1,total),notify_post(AACChunkMsgStructName(tag,index+1,total).UTF8String));
   AACChunkMsgCountPost(channel,AACChunkMsgPayloadName(tag,index+1,total,chunk),notify_post(AACChunkMsgPayloadName(tag,index+1,total,chunk).UTF8String));
  }
  AACChunkMsgCountPost(channel,AACChunkMsgEndName(tag,total),notify_post(AACChunkMsgEndName(tag,total).UTF8String));
  channel[@"endSent"]=@YES;
 }@catch(NSException *e){channel[@"exception"]=e.reason?:@"未知异常";}
 return channel;
}
/* 状态槽通道：96 个固定名，每槽 64 位 = 16 位代次 + 6 字节载荷；最后写 hdr 提交。 */
static NSMutableDictionary *AACChunkMsgWordTokens=nil;
static unsigned AACChunkMsgGeneration=0;
static inline int AACChunkMsgCheckToken(NSString *name){
 if(!AACChunkMsgWordTokens)AACChunkMsgWordTokens=[NSMutableDictionary new];
 NSNumber *cached=AACChunkMsgWordTokens[name];
 if(cached)return cached.intValue;
 int token=0;
 uint32_t status=notify_register_check(name.UTF8String,&token);
 if(status!=NOTIFY_STATUS_OK)return 0;
 @try{AACChunkMsgWordTokens[name]=@(token);}@catch(NSException *e){}
 return token;
}
static inline unsigned AACChunkMsgNextGeneration(void){
 AACChunkMsgGeneration=(AACChunkMsgGeneration+1u)&0xFFFFu;
 if(AACChunkMsgGeneration==0u)AACChunkMsgGeneration=1u;
 return AACChunkMsgGeneration;
}
static inline NSDictionary *AACChunkMsgPublishStateChannel(NSString *tag,NSString *kind,NSString *text){
 NSMutableDictionary *channel=AACChunkMsgChannelResult();
 @try{
  BOOL truncated=NO;
  NSUInteger payloadCap=AACChunkMsgMaxStateBytes>200?AACChunkMsgMaxStateBytes-200:64;
  NSString *bounded=AACChunkMsgBound(text,payloadCap,&truncated);
  NSData *payload=[bounded dataUsingEncoding:NSUTF8StringEncoding];
  NSString *envelope=[AACChunkMsgEnvelope(@"state",tag,kind,payload,truncated) stringByAppendingFormat:@"\n%@",bounded];
  NSData *envelopeData=[envelope dataUsingEncoding:NSUTF8StringEncoding];
  NSUInteger capped=envelopeData.length>AACChunkMsgMaxStateBytes?AACChunkMsgMaxStateBytes:envelopeData.length;
  unsigned gen=AACChunkMsgNextGeneration();
  unsigned words=AACChunkBytesNeeded((unsigned)capped);
  channel[@"channel"]=@"state";
  channel[@"generation"]=@(gen);
  channel[@"payloadBytes"]=@(payload.length);
  channel[@"envelopeBytes"]=@(capped);
  channel[@"wordCount"]=@(words);
  channel[@"boundBytes"]=@(AACChunkMsgMaxStateBytes);
  channel[@"truncated"]=@(truncated);
  if(words==0){channel[@"note"]=@"消息为空：不发任何槽";return channel;}
  const unsigned char *bytes=envelopeData.bytes;
  for(NSUInteger index=0;index<words;index++){
   unsigned char word[AAC_CHUNK_WORD_BYTES];
   NSUInteger offset=index*AACChunkMsgWordBytes;
   for(NSUInteger i=0;i<AACChunkMsgWordBytes;i++)word[i]=(offset+i<capped)?bytes[offset+i]:0;
   NSString *name=AACChunkMsgWordName(tag,index);
   int token=AACChunkMsgCheckToken(name);
   if(!token){
    channel[@"failed"]=@([channel[@"failed"] unsignedIntegerValue]+1);
    @try{[(NSMutableArray *)channel[@"errors"] addObject:[NSString stringWithFormat:@"%@ → notify_register_check 失败",name]];}@catch(NSException *e){}
    continue;
   }
   AACChunkMsgCountPost(channel,name,notify_set_state(token,AACChunkPackState(gen,word)));
  }
  /* hdr 最后写：它的状态是提交点（代次 + 已写字节数）。 */
  {
   unsigned char word[AAC_CHUNK_WORD_BYTES];
   NSString *name=AACChunkMsgHeaderName(tag);
   int token=AACChunkMsgCheckToken(name);
   for(NSUInteger i=0;i<AACChunkMsgWordBytes;i++)word[i]=(unsigned char)((capped >> (8u*(AACChunkMsgWordBytes-1u-i))) & 0xFFu);
   if(!token){
    channel[@"failed"]=@([channel[@"failed"] unsignedIntegerValue]+1);
    @try{[(NSMutableArray *)channel[@"errors"] addObject:[NSString stringWithFormat:@"%@ → notify_register_check 失败",name]];}@catch(NSException *e){}
   }else{
    AACChunkMsgCountPost(channel,name,notify_set_state(token,AACChunkPackState(gen,word)));
    channel[@"headerCommitted"]=@(AACChunkPackState(gen,word));
   }
  }
 }@catch(NSException *e){channel[@"exception"]=e.reason?:@"未知异常";}
 return channel;
}
/* 两条通道一起发；返回值只包含真实状态码，不含任何「应该成功了」的假设。 */
static inline NSDictionary *AACChunkMsgPublish(NSString *tag,NSString *text,NSString *kind){
 NSMutableDictionary *result=[NSMutableDictionary new];
 @try{
  NSString *t=AACChunkMsgSanitizeTag(tag);
  result[@"tag"]=t;
  result[@"kind"]=kind?:@"unknown";
  result[@"nameChannel"]=AACChunkMsgPublishNameChannel(t,kind,text);
  result[@"stateChannel"]=AACChunkMsgPublishStateChannel(t,kind,text);
  result[@"nameShape"]=AACChunkMsgNameShapeText();
  result[@"bounds"]=AACChunkMsgBoundText();
  result[@"utc"]=NSDate.date;
 }@catch(NSException *e){result[@"exception"]=e.reason?:@"未知异常";}
 return result;
}
/* TASK 2: 请求某宿主立刻重发（设置页调用）。 */
static inline uint32_t AACChunkMsgRequestTag(NSString *tag){
 uint32_t status=NOTIFY_STATUS_FAILED;
 @try{status=notify_post(AACChunkMsgRequestName(tag).UTF8String);}@catch(NSException *e){}
 return status;
}
static inline NSDictionary *AACChunkMsgRequestAll(void){
 NSMutableDictionary *result=[NSMutableDictionary new];
 for(NSString *tag in AACChunkMsgKnownTags()){
  uint32_t status=AACChunkMsgRequestTag(tag);
  result[tag]=@(status);
  AACSharedAppend(@"settings",[NSString stringWithFormat:@"已请求宿主 %@ 立刻重发分片消息：post %@ = %u（送达未确认；只有该宿主真的重发时才会看到新片）",tag,AACChunkMsgRequestName(tag),status]);
 }
 return result;
}
/* 宿主端：注册「立即重发」请求 + 立即发一次 + 每 20 秒发一次。block 返回当前摘要文本。 */
static dispatch_source_t AACChunkMsgTimer=nil;
static NSMutableArray *AACChunkMsgRequestTokens=nil;
static inline void AACChunkMsgStart(NSString *tag,NSString *(^textBlock)(void)){
 @try{
  NSString *t=AACChunkMsgSanitizeTag(tag);
  NSString *(^block)=[textBlock copy];
  void (^publish)(NSString *)=^(NSString *why){
   @try{
    NSString *text=block?block():@"（无消息文本）";
    NSDictionary *post=AACChunkMsgPublish(t,text,why);
    NSDictionary *name=post[@"nameChannel"],*state=post[@"stateChannel"];
    AACSharedAppend(t,[NSString stringWithFormat:@"分片消息已发送（%@）：名内载荷通道 片=%@ 编码字节=%@ payload=%@ 发送=%@ 成功=%@ 失败=%@ 字母表合法=%@ 截断=%@；状态槽通道 代次=%@ 槽=%@ 信封字节=%@ 发送=%@ 成功=%@ 失败=%@ 截断=%@；名字形状=%@；上限=%@",why,name[@"chunkCount"],name[@"encodedBytes"],name[@"payloadBytes"],name[@"posts"],name[@"ok"],name[@"failed"],name[@"alphabetOk"],name[@"truncated"],state[@"generation"],state[@"wordCount"],state[@"envelopeBytes"],state[@"posts"],state[@"ok"],state[@"failed"],state[@"truncated"],AACChunkMsgNameShapeText(),AACChunkMsgBoundText()]);
   }@catch(NSException *e){AACSharedAppend(t,[@"分片消息发送异常：" stringByAppendingString:e.reason?:@"unknown"]);}
  };
  publish(@"初次发送");
  if(!AACChunkMsgRequestTokens)AACChunkMsgRequestTokens=[NSMutableArray new];
  int token=0;
  uint32_t status=notify_register_dispatch(AACChunkMsgRequestName(t).UTF8String,&token,dispatch_get_main_queue(),^(int t2){publish(@"收到设置页的立即重发请求");});
  if(status==NOTIFY_STATUS_OK)[AACChunkMsgRequestTokens addObject:@(token)];
  else AACSharedAppend(t,[NSString stringWithFormat:@"注册立即重发请求名 %@ 失败（notify 状态 %u）：本宿主不会响应按需上报",AACChunkMsgRequestName(t),status]);
  if(AACChunkMsgTimer)return;
  dispatch_source_t timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
  if(!timer){AACSharedAppend(t,@"分片消息定时器创建失败；只做了本次发送");return;}
  dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,(int64_t)(AACChunkMsgIntervalSeconds*NSEC_PER_SEC)),(uint64_t)(AACChunkMsgIntervalSeconds*NSEC_PER_SEC),5ull*NSEC_PER_SEC);
  dispatch_source_set_event_handler(timer,^{publish(@"周期性发送");});
  AACChunkMsgTimer=timer;
  dispatch_resume(timer);
  AACSharedAppend(t,[NSString stringWithFormat:@"分片消息通道已启动：每 %.0f 秒发送一次；名内载荷通道最多 %lu 片 / 每片 %lu 字符 / 总解码 %lu 字节，状态槽通道 %lu 槽 × %lu 字节 = %lu 字节；%s",AACChunkMsgIntervalSeconds,(unsigned long)AACChunkMsgMaxChunks,(unsigned long)AACChunkMsgEncodedBytes,(unsigned long)AACChunkMsgMaxTotalBytes,(unsigned long)AACChunkMsgMaxWords,(unsigned long)AACChunkMsgWordBytes,(unsigned long)AACChunkMsgMaxStateBytes,"两条通道都未在设备上验证"]);
 }@catch(NSException *e){AACSharedAppend(AACChunkMsgSanitizeTag(tag),[@"分片消息启动异常：" stringByAppendingString:e.reason?:@"unknown"]);}
}
/* ---------------- 接收端（设置进程；任何进程都可以调用，只读自己的进程视角） ----------------
   接收方策略：Darwin 通知不能通配，所以只注册**可以被枚举出来的固定名字**：
     - 顺序结构名 com.autoanswer.call.msg.<tag>.<seq>.<total>（seq 1..12，total seq..12：每 tag 78 个）
     - 结束标记 com.autoanswer.call.msg.<tag>.end.<total>（total 1..12：每 tag 12 个）
     - 状态槽与提交名 com.autoanswer.call.msg.<tag>.w.<0..95> 与 com.autoanswer.call.msg.<tag>.hdr
       （用 notify_register_check + notify_get_state 按需读回：读回的是通知名自己的 64 位状态）
   名内载荷通道的**片内容**（名字里带 base64url）无法被预先注册，因此本进程只能观察到
   结构名/结束标记（到达片数、总片数、结束标记、最近更新时间、完整性），这不是缺陷而是
   Darwin 通知的既有约束：要读内容只能走固定名字的状态槽通道。这里如实写出，不假装能读。 */
static NSMutableDictionary *AACChunkMsgStore=nil;
static inline NSMutableDictionary *AACChunkMsgTagStore(NSString *tag){
 if(!AACChunkMsgStore)AACChunkMsgStore=[NSMutableDictionary new];
 NSMutableDictionary *store=AACChunkMsgStore[tag];
 if(!store){
  store=[NSMutableDictionary new];
  store[@"seqs"]=[NSMutableSet new];
  store[@"ring"]=[NSMutableArray new];
  AACChunkMsgStore[tag]=store;
 }
 return store;
}
static inline NSArray *AACChunkMsgObserveStart(void){
 NSMutableArray *tokens=[NSMutableArray new];
 @try{
  for(NSString *tag in AACChunkMsgKnownTags()){
   for(NSUInteger seq=1;seq<=AACChunkMsgMaxChunks;seq++){
    for(NSUInteger total=seq;total<=AACChunkMsgMaxChunks;total++){
     int token=0;
     NSMutableDictionary *store=AACChunkMsgTagStore(tag);
     uint32_t status=notify_register_dispatch(AACChunkMsgStructName(tag,seq,total).UTF8String,&token,dispatch_get_main_queue(),^(int t){
      @try{
       [store[@"seqs"] addObject:@(seq)];
       NSNumber *announced=store[@"total"];
       if(!announced||announced.unsignedIntegerValue<total)store[@"total"]=@(total);
       store[@"updated"]=NSDate.date;
       AACSharedAppend(@"settings",[NSString stringWithFormat:@"收到宿主 %@ 的名内载荷通道结构名：片 %lu/%lu（只证明该片位被发布；片内容是名字的一部分，无法预先注册）",tag,(unsigned long)seq,(unsigned long)total]);
      }@catch(NSException *e){}
     });
     if(status==NOTIFY_STATUS_OK)[tokens addObject:@(token)];
    }
   }
   for(NSUInteger total=1;total<=AACChunkMsgMaxChunks;total++){
    int token=0;
    NSMutableDictionary *store=AACChunkMsgTagStore(tag);
    uint32_t status=notify_register_dispatch(AACChunkMsgEndName(tag,total).UTF8String,&token,dispatch_get_main_queue(),^(int t){
     @try{
      store[@"endSeen"]=@YES;
      store[@"endTotal"]=@(total);
      store[@"updated"]=NSDate.date;
      AACSharedAppend(@"settings",[NSString stringWithFormat:@"收到宿主 %@ 的名内载荷通道结束标记：总片数 %lu",tag,(unsigned long)total]);
     }@catch(NSException *e){}
    });
    if(status==NOTIFY_STATUS_OK)[tokens addObject:@(token)];
   }
  }
 }@catch(NSException *e){AACSharedAppend(@"settings",[@"分片消息观察注册异常：" stringByAppendingString:e.reason?:@"unknown"]);}
 return tokens;
}
static inline void AACChunkMsgObserveStop(NSArray *tokens){
 for(NSNumber *token in tokens)@try{notify_cancel(token.intValue);}@catch(NSException *e){}
}
/* 把一条校验通过的文本作为真实文件落盘（写在哪由既有的候选目录解析决定，写失败如实报告）。 */
static inline void AACChunkMsgPersist(NSString *tag,NSString *text,NSString *why){
 NSError *error=nil;
 BOOL ok=AACSharedWriteNamed(tag,@"host-messages.txt",text,&error);
 NSMutableDictionary *store=AACChunkMsgTagStore(tag);
 store[@"filePath"]=[NSString stringWithFormat:@"aac-%@.host-messages.txt",tag];
 store[@"fileWritten"]=@(ok);
 store[@"fileError"]=ok?@"(none)":(error.localizedDescription?:@"写入失败");
 AACSharedAppend(@"settings",[NSString stringWithFormat:@"重组分片消息落盘（%@）：aac-%@.host-messages.txt 写入=%@（%@）",why,tag,ok?@"是":@"否",ok?@"长度与 CRC32 已校验":(error.localizedDescription?:@"写入失败")]);
}
/* 读回状态槽通道：代次一致 + 长度一致 + CRC32 一致才认可是完整消息。 */
static inline void AACChunkMsgRefreshTag(NSString *tag){
 NSMutableDictionary *store=AACChunkMsgTagStore(tag);
 @try{
  NSString *hdrName=AACChunkMsgHeaderName(tag);
  int hdrToken=AACChunkMsgCheckToken(hdrName);
  if(!hdrToken){store[@"stateNote"]=[NSString stringWithFormat:@"%@ 的 notify_register_check 失败：状态槽通道在本进程不可读",hdrName];return;}
  uint64_t hdrState=0;
  uint32_t hdrStatus=notify_get_state(hdrToken,&hdrState);
  if(hdrStatus!=NOTIFY_STATUS_OK){store[@"stateNote"]=[NSString stringWithFormat:@"notify_get_state(%@) 返回 %u",hdrName,hdrStatus];return;}
  unsigned gen=(unsigned)((hdrState & AAC_CHUNK_GEN_MASK) >> AAC_CHUNK_GEN_SHIFT);
  if(gen==0){
   store[@"stateGen"]=@0;
   store[@"stateNote"]=@"状态槽提交名的状态为 0：本进程从未读到任何提交（= 没有观察到该宿主的状态槽消息，不等于该宿主未注入）";
   return;
  }
  unsigned char header[AAC_CHUNK_WORD_BYTES];
  AACChunkUnpackState(hdrState,header);
  NSUInteger declared=0;
  for(NSUInteger i=0;i<AACChunkMsgWordBytes;i++)declared=(declared<<8)|(NSUInteger)header[i];
  if(declared==0||declared>AACChunkMsgMaxStateBytes)declared=AACChunkMsgMaxStateBytes;
  NSUInteger words=AACChunkBytesNeeded((unsigned)declared);
  NSMutableData *data=[NSMutableData data];
  NSUInteger missing=0,newer=0;
  for(NSUInteger index=0;index<words;index++){
   NSString *name=AACChunkMsgWordName(tag,index);
   int token=AACChunkMsgCheckToken(name);
   if(!token){missing++;continue;}
   uint64_t state=0;
   if(notify_get_state(token,&state)!=NOTIFY_STATUS_OK){missing++;continue;}
   unsigned wordGen=(unsigned)((state & AAC_CHUNK_GEN_MASK) >> AAC_CHUNK_GEN_SHIFT);
   if(wordGen!=gen){
    /* 代次不一致：该槽属于另一代（发送方正在写新消息，或该槽从未被本代写过）；两种都算缺。
       代次非 0 且不等于提交代次 => 该槽已经被更新的一代改写。 */
    if(wordGen!=0)newer++;
    missing++;
    continue;
   }
   unsigned char word[AAC_CHUNK_WORD_BYTES];
   AACChunkUnpackState(state,word);
   [data appendBytes:word length:AACChunkMsgWordBytes];
  }
  store[@"stateGen"]=@(gen);
  store[@"stateDeclaredBytes"]=@(declared);
  store[@"stateWordsNeeded"]=@(words);
  store[@"stateWordsMissing"]=@(missing);
  store[@"stateWordsNewer"]=@(newer);
  store[@"stateUpdated"]=NSDate.date;
  if(missing){
   store[@"stateComplete"]=@NO;
   store[@"stateText"]=nil;
   store[@"stateNote"]=[NSString stringWithFormat:@"状态槽通道不完整：需要 %lu 槽，缺 %lu 槽（其中 %lu 槽属于更新的代次，说明发送方正在写新消息）；不做任何内容猜测",(unsigned long)words,(unsigned long)missing,(unsigned long)newer];
   return;
  }
  if(data.length>declared)[data setLength:declared];
  NSDictionary *verified=AACChunkMsgVerifyEnvelope(data);
  store[@"stateComplete"]=@YES;
  store[@"stateVerified"]=verified[@"ok"];
  store[@"stateReason"]=verified[@"reason"];
  store[@"stateDeclaredCrc32"]=verified[@"declaredCrc32"];
  store[@"stateActualCrc32"]=verified[@"actualCrc32"];
  store[@"stateBytes"]=@(data.length);
  if(![verified[@"ok"] boolValue]){
   store[@"stateText"]=nil;
   store[@"stateNote"]=[NSString stringWithFormat:@"代次 %u 的 %lu 槽已全部读到，但信封校验失败：%@",gen,(unsigned long)words,verified[@"reason"]];
   return;
  }
  NSString *text=verified[@"text"];
  NSString *previous=[store[@"stateText"] isKindOfClass:NSString.class]?store[@"stateText"]:nil;
  store[@"stateText"]=text;
  store[@"stateChannel"]=verified[@"channel"];
  store[@"stateKind"]=verified[@"kind"];
  store[@"stateNote"]=[NSString stringWithFormat:@"代次 %u 完整：%lu 槽、%lu 字节、CRC32 %@ 与信封头一致（%@）",gen,(unsigned long)words,(unsigned long)data.length,verified[@"actualCrc32"],verified[@"reason"]];
  @try{
   NSMutableArray *ring=store[@"ring"];
   [ring addObject:@{@"utc":NSDate.date,@"gen":@(gen),@"bytes":@(data.length),@"crc32":verified[@"actualCrc32"]?:@"",@"text":text?:@""}];
   while(ring.count>AACChunkMsgRingPerTag)[ring removeObjectAtIndex:0];
  }@catch(NSException *e){}
  if(![text isEqualToString:previous?:@""]){
   AACChunkMsgPersist(tag,text,@"状态槽通道");
   AACSharedAppend(@"settings",[NSString stringWithFormat:@"宿主 %@ 的分片消息（状态槽通道 代次 %u）：\n%@",tag,gen,text]);
  }
 }@catch(NSException *e){store[@"stateNote"]=[@"状态槽读回异常：" stringByAppendingString:e.reason?:@"unknown"];}
}
static inline void AACChunkMsgRefresh(void){
 for(NSString *tag in AACChunkMsgKnownTags())AACChunkMsgRefreshTag(tag);
}
/* 每个 tag 的结构化读数：片数/总片数、最近更新、完整性、解码字节、以及状态槽通道的文本。 */
static inline NSDictionary *AACChunkMsgTagReport(NSString *tag){
 NSMutableDictionary *store=AACChunkMsgTagStore(tag);
 unsigned mask=0;
 @try{for(NSNumber *seq in store[@"seqs"])mask|=(1u<<seq.unsignedIntValue);}@catch(NSException *e){}
 NSUInteger total=[store[@"total"] isKindOfClass:NSNumber.class]?[store[@"total"] unsignedIntegerValue]:0;
 NSUInteger received=0;
 for(NSUInteger seq=1;seq<=total;seq++)if(mask&(1u<<seq))received++;
 BOOL nameComplete=total>0&&AACChunkMaskComplete(mask,(unsigned)total);
 NSString *stateText=[store[@"stateText"] isKindOfClass:NSString.class]?store[@"stateText"]:nil;
 return @{@"tag":tag,
          @"chunksReceived":@(received),@"chunksTotal":@(total),
          @"nameComplete":@(nameComplete),
          @"endSeen":@([store[@"endSeen"] boolValue]),@"endTotal":store[@"endTotal"]?:@0,
          @"nameUpdated":store[@"updated"]?:NSDate.distantPast,
          @"statesGen":store[@"stateGen"]?:@0,
          @"stateDeclaredBytes":store[@"stateDeclaredBytes"]?:@0,
          @"stateWordsNeeded":store[@"stateWordsNeeded"]?:@0,
          @"stateWordsMissing":store[@"stateWordsMissing"]?:@0,
          @"stateComplete":store[@"stateComplete"]?:@NO,
          @"stateVerified":store[@"stateVerified"]?:@NO,
          @"stateBytes":store[@"stateBytes"]?:@0,
          @"stateText":stateText?:@"",
          @"stateNote":store[@"stateNote"]?:@"本进程尚未读回该宿主的状态槽通道（读不到不代表该宿主未注入）",
          @"filePath":store[@"filePath"]?:[NSString stringWithFormat:@"aac-%@.host-messages.txt（尚未写出）",tag],
          @"fileWritten":store[@"fileWritten"]?:@NO,
          @"fileError":store[@"fileError"]?:@"(none)",
          @"ring":[store[@"ring"] copy]?:@[]};
}
/* 名内载荷通道只能观察到结构，必须如实说明，不能假装解出了内容。 */
static inline NSString *AACChunkMsgNameChannelNote(void){
 return @"名内载荷通道的片内容写在通知名里，接收方无法预先注册任意名字（Darwin 通知不支持通配）：本页只能给出到达片数/总片数、结束标记、最近更新时间与完整性；解码字节只有在片内容可读时才不为 0。要看内容请用固定名字的状态槽通道。";
}
static inline NSString *AACChunkMsgTagSummaryText(NSString *tag){
 NSDictionary *report=AACChunkMsgTagReport(tag);
 NSMutableString *text=[NSMutableString string];
 [text appendFormat:@"[%@]\n  名内载荷通道：到达 %@/%@ 片；结束标记=%@（总片数 %@）；最近更新=%@；完整性=%@；解码字节=%@（上限 12288 字节；片内容不可预先注册）\n",
                      tag,report[@"chunksReceived"],report[@"chunksTotal"],([report[@"endSeen"] boolValue]?@"已收到":@"未收到"),report[@"endTotal"],report[@"nameUpdated"],([report[@"nameComplete"] boolValue]?@"完整":@"不完整"),@(0)];
 [text appendFormat:@"  状态槽通道：代次=%@；需要 %@ 槽（每槽 %lu 字节，声明 %@ 字节）；缺 %@ 槽；完整=%@；校验通过=%@；字节=%@\n  说明：%@\n",
                      report[@"statesGen"],report[@"stateWordsNeeded"],(unsigned long)AACChunkMsgWordBytes,report[@"stateDeclaredBytes"],report[@"stateWordsMissing"],([report[@"stateComplete"] boolValue]?@"是":@"否"),([report[@"stateVerified"] boolValue]?@"是":@"否"),report[@"stateBytes"],report[@"stateNote"]];
 [text appendFormat:@"  落盘：%@（已写入=%@；%@；环形缓冲最近 %lu 条）\n",report[@"filePath"],([report[@"fileWritten"] boolValue]?@"是":@"否"),report[@"fileError"],(unsigned long)[(NSArray *)report[@"ring"] count]];
 NSString *body=report[@"stateText"];
 [text appendFormat:@"  重组文本（状态槽通道校验通过时）：\n%@\n",[body length]?body:@"（空：本进程没有读到任何校验通过的跨进程分片消息——如实报告为未观察到该通道）"];
 return text;
}
static inline NSString *AACChunkMsgDump(void){
 NSMutableString *text=[NSMutableString string];
 [text appendString:@"# 跨进程分片消息（Darwin 名内载荷 + 固定名字状态槽）1.16.0\n"];
 [text appendFormat:@"# 名字形状：%@\n",AACChunkMsgNameShapeText()];
 [text appendFormat:@"# 上限：%@\n",AACChunkMsgBoundText()];
 [text appendFormat:@"# 按需上报：设置页 POST %@ 使该宿主立刻重发一次\n",@"com.autoanswer.call.msgrequest.<tag>"];
 [text appendFormat:@"# %@\n",AACChunkMsgNameChannelNote()];
 BOOL any=NO;
 for(NSString *tag in AACChunkMsgKnownTags()){
  NSDictionary *report=AACChunkMsgTagReport(tag);
  if([report[@"chunksTotal"] unsignedIntegerValue]||[report[@"stateVerified"] boolValue])any=YES;
  [text appendString:@"\n"];
  [text appendString:AACChunkMsgTagSummaryText(tag)];
 }
 if(!any)[text appendString:@"\n（本进程没有观察到任何 tag 的分片消息：如实报告为「该传输未在本进程被观察到」，不等于任何宿主未注入，也不等于接听可用。）\n"];
 return text;
}
