#!/usr/bin/env python3
"""Offline source and PNG tests only; NOT iOS/Logos runtime verification."""
from pathlib import Path
import base64,re,struct,zlib
root=Path(__file__).resolve().parents[1]
source=(root/'DYYYCapturedFeedIcons.m').read_text()
main=(root/'DYYY.xm').read_text()
settings=(root/'DYYYSettings.xm').read_text()
make=(root/'Makefile').read_text()
expected=('like_before','comment','unfavorite','share')
assert 'DYYYCapturedFeedIcons.m' in make
assert '#import "DYYYCapturedFeedIcons.h"' in main
assert 'DYYYLoadCustomImage(customFileName' in main, 'user-owned custom icons must retain priority'
assert 'BOOL nativeActiveState' in main and 'DYYYUseCapturedFeedIcons' in main
assert 'DYYYUseCapturedFeedIcons' in settings
assert '@"DYYYUseCapturedFeedIcons": @YES' in main
assert 'matchingNativeImage:imageToApply' in main
assert 'nativeImage.size' in source and 'UIImageRenderingModeAlwaysOriginal' in source
assert '-Wl,-undefined,error' in make and '-Wl,-undefined,dynamic_lookup' not in make
blocks={}
for name in expected:
    raw=(root/'assets'/'feed-icons'/(name+'.png')).read_bytes()
    assert raw.startswith(b'\x89PNG\r\n\x1a\n'),name
    assert raw[12:16] == b'IHDR', name
    width,height,depth,color=struct.unpack('>IIBB', raw[16:26])
    assert (width,height,depth,color)==(110,110,8,6), name # RGBA PNG, not opaque RGB
    chunks=[]
    cursor=8
    while cursor < len(raw):
        size=struct.unpack('>I',raw[cursor:cursor+4])[0]
        kind=raw[cursor+4:cursor+8]
        payload=raw[cursor+8:cursor+8+size]
        if kind==b'IDAT':chunks.append(payload)
        cursor += 12+size
        if kind==b'IEND':break
    assert chunks and zlib.decompress(b''.join(chunks)),name
    match=re.search(r'@"'+name+r'\.png"\s*:\s*((?:@"[A-Za-z0-9+/=]+"\s*)+)',source)
    assert match is not None, 'missing compiled image: '+name
    chunks=re.findall(r'@"([A-Za-z0-9+/=]+)"',match.group(1))
    assert base64.b64decode(''.join(chunks))==raw, 'PNG and embedded bytes differ: '+name
    print(f'PASS: {name} embedded / transparent / 110x110')
print('PASS: native-sized bitmap rendering, state preservation, settings toggle, user priority, strict linkage')
