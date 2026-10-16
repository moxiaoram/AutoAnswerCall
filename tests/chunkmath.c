/* 1.16.0 分片框架纯算术单元测试（CI: cc -std=c11 tests/chunkmath.c -o /tmp/aac-chunkmath && /tmp/aac-chunkmath）
   只测 AACChunkMath.h 的算术：片数/片长/seq-total 合法性/base64url 字母表/掩码完整性/
   状态槽打包解包/槽数/CRC32。被测代码与 AACChunkMsg.h 使用同一份头文件，因此数值不会漂移。 */
#include <stdio.h>
#include <string.h>
#include "../AACChunkMath.h"

static int failures = 0;
static void ok(int condition, const char *what) {
    if (condition) { printf("  ok   %s\n", what); }
    else { printf("  FAIL %s\n", what); failures++; }
}

int main(void) {
    printf("AACChunkMath unit test (1.16.0 framing arithmetic)\n");

    /* 常量本身：这些数字被 tests/source_checks.py 交叉核对，改动必须是有意的。 */
    ok(AAC_CHUNK_ENCODED_BYTES == 900u, "chunk encoded cap is exactly 900 bytes of name payload");
    ok(AAC_CHUNK_MAX_CHUNKS == 12u, "chunk count cap is 12");
    ok(AAC_CHUNK_MAX_TOTAL_BYTES == 12288u, "total cap is 12288 bytes (12 KiB)");
    ok(AAC_CHUNK_ENCODED_BYTES % 4u == 0u, "900 is a multiple of 4 so every chunk is whole base64 groups");
    ok(AAC_CHUNK_MAX_TOTAL_BYTES / 4u * 3u <= (unsigned long)AAC_CHUNK_MAX_CHUNKS * AAC_CHUNK_ENCODED_BYTES,
       "the decoded-byte cap is reachable within the chunk cap");

    /* 片数：边界与上限。 */
    ok(AACChunkCount(0u) == 0u, "0 bytes -> 0 chunks (never post an empty message)");
    ok(AACChunkCount(1u) == 1u, "1 byte -> 1 chunk");
    ok(AACChunkCount(899u) == 1u, "899 -> 1 chunk");
    ok(AACChunkCount(900u) == 1u, "exactly one full chunk stays one chunk");
    ok(AACChunkCount(901u) == 2u, "901 -> 2 chunks");
    ok(AACChunkCount(10800u) == 12u, "10800 encoded chars -> exactly the 12-chunk cap");
    ok(AACChunkCount(20000u) == 12u, "beyond the cap the count is clamped to 12 (never unbounded)");

    /* 片长：除末片外都是满片。 */
    ok(AACChunkLengthAt(0u, 900u) == 900u, "first full chunk is 900");
    ok(AACChunkLengthAt(0u, 901u) == 900u && AACChunkLengthAt(1u, 901u) == 1u, "last chunk carries the remainder");
    ok(AACChunkLengthAt(1u, 900u) == 0u, "a chunk index past the count has length 0");
    ok(AACChunkLengthsConsistent(900u, 1u) == 1, "one full chunk is consistent");
    ok(AACChunkLengthsConsistent(901u, 2u) == 1, "900+1 split is consistent");
    ok(AACChunkLengthsConsistent(1800u, 2u) == 1, "two full chunks are consistent");
    ok(AACChunkLengthsConsistent(901u, 1u) == 0, "a truncated total is inconsistent");
    ok(AACChunkLengthsConsistent(450u, 2u) == 0, "a wrong chunk count is inconsistent");
    ok(AACChunkLengthsConsistent(0u, 0u) == 1, "empty message: zero chunks is consistent");

    /* seq/total 合法性。 */
    ok(AACChunkSeqTotalValid(1u, 1u) == 1, "seq=1 total=1 valid");
    ok(AACChunkSeqTotalValid(12u, 12u) == 1, "seq=12 total=12 valid");
    ok(AACChunkSeqTotalValid(0u, 3u) == 0, "seq=0 invalid");
    ok(AACChunkSeqTotalValid(4u, 3u) == 0, "seq>total invalid");
    ok(AACChunkSeqTotalValid(1u, 13u) == 0, "total above the cap invalid");
    ok(AACChunkSeqTotalValid(-1, 3u) == 0, "negative seq invalid after the unsigned cast");

    /* base64url 字母表：通知名里不能有 '/'、'='、'+' 或 NUL。 */
    ok(AACChunkIsBase64UrlChar('A') && AACChunkIsBase64UrlChar('z') && AACChunkIsBase64UrlChar('0'), "alnum allowed");
    ok(AACChunkIsBase64UrlChar('-') && AACChunkIsBase64UrlChar('_'), "base64url - and _ allowed");
    ok(!AACChunkIsBase64UrlChar('/'), "'/' is NOT allowed in a notification name");
    ok(!AACChunkIsBase64UrlChar('+') && !AACChunkIsBase64UrlChar('='), "'+' and '=' are NOT used");
    ok(AACChunkAlphabetOk("Ab0-_Z", 6u) == 1, "a sanitized chunk passes the alphabet check");
    ok(AACChunkAlphabetOk("Ab/c", 4u) == 0, "a chunk with '/' is rejected");
    ok(AACChunkAlphabetOk("Ab\0c", 4u) == 0, "a chunk with an embedded NUL is rejected");
    ok(AACChunkAlphabetOk(0, 0u) == 1, "the empty chunk is trivially ok");

    /* 解码长度：900 字符 -> 675 字节；末片可能不是 4 的倍数。 */
    ok(AACChunkDecodedLength(900u) == 675u, "900 encoded chars decode to 675 bytes");
    ok(AACChunkDecodedLength(4u) == 3u, "4 chars -> 3 bytes");
    ok(AACChunkDecodedLength(2u) == 1u, "2 chars -> 1 byte");
    ok(AACChunkDecodedLength(3u) == 2u, "3 chars -> 2 bytes");
    ok(AACChunkDecodedLength(0u) == 0u, "0 chars -> 0 bytes");
    ok(AACChunkDecodedLength(12u * AAC_CHUNK_ENCODED_BYTES) == 8100u,
       "the 12-chunk name channel carries at most 8100 decoded bytes (below the 12288 cap)");

    /* 完整性掩码。 */
    ok(AACChunkMaskComplete(0x2u, 1u) == 1, "bit 1 set means chunk 1 arrived");
    ok(AACChunkMaskComplete(0xEu, 3u) == 1, "bits 1..3 set is complete for total=3");
    ok(AACChunkMaskComplete(0xCu, 3u) == 0, "a missing chunk 1 is incomplete");
    ok(AACChunkMaskComplete(0xEu, 4u) == 0, "a missing chunk 4 is incomplete");
    ok(AACChunkMaskComplete(0xFFEu, 12u) == 0, "11 of 12 chunks is still incomplete at the cap");
    ok(AACChunkMaskComplete((1u << 12) | 0xFFEu, 12u) == 1, "all 12 chunks complete exactly at the cap");
    ok(AACChunkMaskComplete(0u, 0u) == 0 && AACChunkMaskComplete(0u, 13u) == 0, "total 0 and total>cap are never complete");

    /* 状态槽：打包/解包往返 + 代次绝不丢 + 0 状态永不出现。 */
    {
        unsigned char word[AAC_CHUNK_WORD_BYTES]; unsigned char back[AAC_CHUNK_WORD_BYTES];
        unsigned gen = 0; unsigned i;
        for (i = 0; i < AAC_CHUNK_WORD_BYTES; i++) word[i] = (unsigned char)(0x11u * (i + 1u));
        unsigned long long state = AACChunkPackState(7u, word);
        ok((state >> AAC_CHUNK_GEN_SHIFT) == 7u, "the 16-bit generation survives the pack");
        gen = AACChunkUnpackState(state, back);
        ok(gen == 7u, "unpack returns the generation");
        ok(memcmp(word, back, AAC_CHUNK_WORD_BYTES) == 0, "6 payload bytes round-trip exactly");
        { unsigned char zero[AAC_CHUNK_WORD_BYTES]; unsigned char zback[AAC_CHUNK_WORD_BYTES]; unsigned zgen;
          memset(zero, 0, sizeof zero);
          ok(AACChunkPackState(1u, zero) != 0ull, "an all-zero payload still packs a non-zero state (gen in the high bits)");
          zgen = AACChunkUnpackState(AACChunkPackState(3u, zero), zback);
          ok(zgen == 3u && zback[0] == 0 && zback[AAC_CHUNK_WORD_BYTES - 1u] == 0, "a zero word round-trips with its generation");
        }
        ok(AACChunkUnpackState(0ull, back) == 0u, "a never-set state (0) reads as generation 0 = nothing received");
    }
    ok(AACChunkPackState(0xFFFFu, 0) == AAC_CHUNK_GEN_MASK, "a fully used 16-bit generation stays inside its mask");

    /* 槽数。 */
    ok(AACChunkBytesNeeded(0u) == 0u, "0 bytes need 0 slots");
    ok(AACChunkBytesNeeded(1u) == 1u && AACChunkBytesNeeded(6u) == 1u, "up to 6 bytes fit one slot");
    ok(AACChunkBytesNeeded(7u) == 2u, "7 bytes need 2 slots");
    ok(AACChunkBytesNeeded(AAC_CHUNK_MAX_STATE_BYTES) == AAC_CHUNK_MAX_WORDS, "the full state capacity needs exactly 96 slots");
    ok(AACChunkBytesNeeded(AAC_CHUNK_MAX_STATE_BYTES + 1u) == AAC_CHUNK_MAX_WORDS, "beyond capacity is clamped, never unbounded");
    ok(AAC_CHUNK_MAX_STATE_BYTES == 576u, "the state channel is hard-capped at 576 payload bytes");

    /* CRC-32 已知向量 + 长度敏感性。 */
    ok(AACChunkCrc32((const unsigned char *)"123456789", 9u) == 0xCBF43926u, "CRC-32 known vector 123456789 -> 0xCBF43926");
    ok(AACChunkCrc32((const unsigned char *)"", 0u) == 0u, "CRC-32 of nothing is 0");
    ok(AACChunkCrc32((const unsigned char *)"abc", 3u) != AACChunkCrc32((const unsigned char *)"abd", 3u), "one changed byte changes the CRC");
    ok(AACChunkCrc32((const unsigned char *)"abcd", 4u) != AACChunkCrc32((const unsigned char *)"abc", 3u), "a truncated payload changes the CRC");

    printf("%s: %d failure(s)\n", failures ? "FAIL" : "PASS", failures);
    return failures ? 1 : 0;
}
