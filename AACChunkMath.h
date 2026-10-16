#ifndef AAC_CHUNK_MATH_H
#define AAC_CHUNK_MATH_H
/* ================= 1.16.0: 分片框架纯算术（无 Foundation 依赖） =================
   这一层只做算术，不碰通知、不碰内存分配，因此可以在构建机上用普通 cc 编译并单元测试
   （tests/chunkmath.c，CI 里真的编译并运行）。AACChunkMsg.h 使用同一份常量与同一套公式，
   tests/source_checks.py 会核对两个文件里的常量没有漂移。

   框架（TASK 1）：
   1) 名内载荷通道：把消息文本（自带长度 + CRC32 的信封头）做 base64url，按
      AAC_CHUNK_ENCODED_BYTES（900）个字符切成最多 AAC_CHUNK_MAX_CHUNKS（12）片，每片作为
      Darwin 通知名的一部分：com.autoanswer.call.msg.<tag>.<seq>.<total>.<base64url片>。
      总解码上限 AAC_CHUNK_MAX_TOTAL_BYTES（12288 字节）。900 是 4 的倍数，所以每片都是完整的
      base64 组，单独解码不会产生补齐歧义。
   2) 状态槽通道：Darwin 通知名不能通配，名字里带任意内容的片无法被接收方预先注册，因此同一
      名字族另有一条可被预先注册的通道：把同一文本装进 96 个固定槽
      com.autoanswer.call.msg.<tag>.w.<槽号> 的 64 位状态里（每槽 6 字节载荷 + 16 位代次），
      最后一个写的 com.autoanswer.call.msg.<tag>.hdr 状态提交（代次 + 字节长度）。接收方用
      notify_register_check/notify_get_state 按槽读回，校验代次一致、长度一致、CRC32 一致。
   两条通道都只使用本插件自有名字，且都有硬上限。 */
#define AAC_CHUNK_ENCODED_BYTES 900u
#define AAC_CHUNK_MAX_CHUNKS 12u
#define AAC_CHUNK_MAX_TOTAL_BYTES 12288u
#define AAC_CHUNK_MAX_WORDS 96u
#define AAC_CHUNK_WORD_BYTES 6u
#define AAC_CHUNK_MAX_STATE_BYTES (AAC_CHUNK_MAX_WORDS * AAC_CHUNK_WORD_BYTES)
#define AAC_CHUNK_GEN_SHIFT 48u
#define AAC_CHUNK_GEN_MASK 0xFFFF000000000000ull
#define AAC_CHUNK_WORD_MASK 0x0000FFFFFFFFFFFFull
#define AAC_CHUNK_RING_PER_TAG 8u
#define AAC_CHUNK_MSG_TRUNCATED_MARKER "\xe2\x80\xa6<msg-truncated>"
#define AAC_CHUNK_MIN_MSG_BYTES 64u

/* 片数：0 长度 -> 0 片；否则向上取整并夹在 AAC_CHUNK_MAX_CHUNKS 内。 */
static inline unsigned AACChunkCount(unsigned encodedLength){
 if(encodedLength==0u)return 0u;
 unsigned count=(encodedLength + AAC_CHUNK_ENCODED_BYTES - 1u) / AAC_CHUNK_ENCODED_BYTES;
 return count > AAC_CHUNK_MAX_CHUNKS ? AAC_CHUNK_MAX_CHUNKS : count;
}
/* 第 index 片的起点（以编码字符计）。越界返回 0。 */
static inline unsigned AACChunkStartAt(unsigned index){
 unsigned count=AACChunkCount(AAC_CHUNK_MAX_TOTAL_BYTES * 2u);
 if(index >= count)return 0u;
 return index * AAC_CHUNK_ENCODED_BYTES;
}
/* 第 index 片在总长度 encodedLength 下的长度：满片是 900，末片是余数，越界返回 0。 */
static inline unsigned AACChunkLengthAt(unsigned index,unsigned encodedLength){
 unsigned total=AACChunkCount(encodedLength);
 if(index >= total)return 0u;
 unsigned start=index * AAC_CHUNK_ENCODED_BYTES;
 unsigned remaining=encodedLength - start;
 return remaining > AAC_CHUNK_ENCODED_BYTES ? AAC_CHUNK_ENCODED_BYTES : remaining;
}
/* 除末片外都必须是满片：这是接收方校验「长度一致」的依据之一。 */
static inline int AACChunkLengthsConsistent(unsigned encodedLength,unsigned total){
 if(total==0u)return encodedLength==0u;
 if(total != AACChunkCount(encodedLength))return 0;
 if(total == AAC_CHUNK_MAX_CHUNKS && encodedLength > total * AAC_CHUNK_ENCODED_BYTES)return 0;
 unsigned i=0u;
 while(i + 1u < total){ if(AACChunkLengthAt(i,encodedLength) != AAC_CHUNK_ENCODED_BYTES)return 0; i++; }
 return AACChunkLengthAt(total - 1u,encodedLength) > 0u ? 1 : 0;
}
/* seq/total 必须在 1..AAC_CHUNK_MAX_CHUNKS 且 seq <= total。 */
static inline int AACChunkSeqTotalValid(unsigned seq,unsigned total){
 if(seq < 1u || total < 1u)return 0;
 if(total > AAC_CHUNK_MAX_CHUNKS || seq > total)return 0;
 return 1;
}
/* base64url 字母表：A-Z a-z 0-9 - _ ，且不允许 '=' 补齐、'/'、'+' 或 NUL（通知名必须保持有效）。 */
static inline int AACChunkIsBase64UrlChar(int c){
 if(c >= 'A' && c <= 'Z')return 1;
 if(c >= 'a' && c <= 'z')return 1;
 if(c >= '0' && c <= '9')return 1;
 if(c == '-' || c == '_')return 1;
 return 0;
}
static inline int AACChunkAlphabetOk(const char *text,unsigned length){
 unsigned i=0u;
 if(!text && length)return 0;
 for(i=0u;i<length;i++){int c=(unsigned char)text[i];if(c==0)return 0;if(!AACChunkIsBase64UrlChar(c))return 0;}
 return 1;
}
/* base64url 编码长度对应的解码字节数（不带补齐：n/4*3 加余数映射）。 */
static inline unsigned AACChunkDecodedLength(unsigned encodedLength){
 unsigned groups=encodedLength / 4u;
 unsigned rest=encodedLength % 4u;
 unsigned bytes=groups * 3u;
 if(rest==2u)bytes += 1u;
 else if(rest==3u)bytes += 2u;
 return bytes;
}
/* presentMask 的 bit i 表示第 i+1 片已到达；要求 1..total 全部到达。 */
static inline int AACChunkMaskComplete(unsigned presentMask,unsigned total){
 unsigned i=0u;
 if(total==0u || total > AAC_CHUNK_MAX_CHUNKS)return 0;
 /* 32 位掩码只覆盖前 12 片，AAC_CHUNK_MAX_CHUNKS 是 12，因此不会溢出。 */
 for(i=1u;i<=total;i++)if(!(presentMask & (1u << i)))return 0;
 return 1;
}
/* 状态槽：高 16 位是代次（绝不写 0 状态，因为 notify_set_state 的 0 表示「未设置」），
   低 48 位是 6 字节大端载荷。 */
static inline unsigned long long AACChunkPackState(unsigned gen,const unsigned char word[AAC_CHUNK_WORD_BYTES]){
 unsigned long long payload=0ull;unsigned i=0u;
 for(i=0u;i<AAC_CHUNK_WORD_BYTES;i++)payload=(payload << 8) | (unsigned long long)(word?word[i]:0u);
 return (((unsigned long long)(gen & 0xFFFFu)) << AAC_CHUNK_GEN_SHIFT) | (payload & AAC_CHUNK_WORD_MASK);
}
static inline unsigned AACChunkUnpackState(unsigned long long state,unsigned char word[AAC_CHUNK_WORD_BYTES]){
 unsigned i=0u;
 unsigned long long payload=state & AAC_CHUNK_WORD_MASK;
 for(i=0u;i<AAC_CHUNK_WORD_BYTES;i++){ if(word)word[AAC_CHUNK_WORD_BYTES-1u-i]=(unsigned char)(payload & 0xFFull); payload >>= 8; }
 return (unsigned)((state & AAC_CHUNK_GEN_MASK) >> AAC_CHUNK_GEN_SHIFT);
}
/* 载荷长度 -> 需要的槽数（0 长度仍需 0 槽；超出上限则夹住）。 */
static inline unsigned AACChunkBytesNeeded(unsigned payloadLength){
 if(payloadLength==0u)return 0u;
 unsigned words=(payloadLength + AAC_CHUNK_WORD_BYTES - 1u) / AAC_CHUNK_WORD_BYTES;
 return words > AAC_CHUNK_MAX_WORDS ? AAC_CHUNK_MAX_WORDS : words;
}
/* 标准 CRC-32（IEEE 802.3 多项式 0xEDB88320），用于信封头里的长度/内容一致性校验。
   已知向量："123456789" -> 0xCBF43926。 */
static inline unsigned AACChunkCrc32(const unsigned char *data,unsigned length){
 unsigned crc=0xFFFFFFFFu;unsigned i=0u;int bit=0;
 if(!data && length)return 0u;
 for(i=0u;i<length;i++){
  crc ^= (unsigned)data[i];
  for(bit=0;bit<8;bit++)crc = (crc & 1u) ? ((crc >> 1) ^ 0xEDB88320u) : (crc >> 1);
 }
 return crc ^ 0xFFFFFFFFu;
}
#endif
