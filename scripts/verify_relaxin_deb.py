#!/usr/bin/env python3
"""Inspect the ACTUAL GitHub Actions .deb, not merely source packaging."""
import io
import os
from pathlib import Path
import re
import subprocess
import sys
import tarfile
import tempfile

PACKAGE='com.local.awemevision.relaxin'
ARCH='iphoneos-arm64e'
LOADER='DYYY' if os.environ.get('LEGACY_LOADER_NAME','1') == '1' else 'AwemeVision'
SO=f'Library/MobileSubstrate/DynamicLibraries/{LOADER}.dylib'
FILTER=f'Library/MobileSubstrate/DynamicLibraries/{LOADER}.plist' 

def fail(message): raise ValueError(message)

def ar_members(path):
    data=Path(path).read_bytes()
    if not data.startswith(b'!<arch>\n'): fail('not a Debian ar archive')
    index=8; out={}
    while index<len(data):
        header=data[index:index+60]
        if len(header)!=60 or header[58:60]!=b'`\n': fail('bad ar header')
        name=header[:16].decode('ascii').strip().rstrip('/')
        size=int(header[48:58].decode('ascii').strip())
        index+=60
        if index+size>len(data): fail('truncated ar data')
        out[name]=data[index:index+size]
        index+=size+(size%2)
    return out

def extract_tar(blob):
    with tarfile.open(fileobj=io.BytesIO(blob),mode='r:*') as f:
        return {m.name.removeprefix('./').lstrip('/'):(f.extractfile(m).read() if m.isfile() else None) for m in f.getmembers()}

def main(path):
    print('Package under test:',path)
    data=ar_members(path)
    ctlname=next((k for k in data if k.startswith('control.tar.')),None)
    dataname=next((k for k in data if k.startswith('data.tar.')),None)
    if not ctlname or not dataname: fail('missing control.tar or data.tar')
    controls=extract_tar(data[ctlname]); files=extract_tar(data[dataname])
    control=controls.get('control')
    if not control: fail('missing Debian control metadata')
    text=control.decode('utf8',errors='replace')
    for expected in [f'Package: {PACKAGE}', f'Architecture: {ARCH}', 'Version: 2.0.2', 'Conflicts: com.huami.dyyy', 'firmware (>= 17.3)', 'firmware (<< 17.4)']:
        if expected not in text: fail('missing control field: '+expected)
    if 'Provides: com.huami.dyyy' in text: fail('would impersonate old upgrade package')
    if SO not in files or not files[SO]: fail('new dylib missing')
    if FILTER not in files or not files[FILTER]: fail('new injection filter missing')
    if b'com.ss.iphone.ugc.Aweme' not in files[FILTER]: fail('wrong Douyin bundle in filter')
    if b'Executables' in files[FILTER]: fail('unexpected executable filter: legacy Bundles-only injection required')
    if files[SO][:4] not in (b'\xcf\xfa\xed\xfe',b'\xca\xfe\xba\xbe',b'\xbe\xba\xfe\xca'): fail('binary not 64-bit Mach-O')
    other='AwemeVision' if LOADER=='DYYY' else 'DYYY'
    if any(k.endswith('/'+other+'.dylib') or k.endswith('/'+other+'.plist') for k in files): fail('mixed loader filenames; stale build')
    if any(k.startswith('var/jb/') for k in files): fail('ordinary rootless path inside RootHide archive')
    if sys.platform=='darwin':
        with tempfile.TemporaryDirectory() as directory:
            binary=Path(directory)/(LOADER+'.dylib')
            binary.write_bytes(files[SO]); archs=subprocess.check_output(['lipo','-archs',str(binary)],text=True)
            if 'arm64' not in archs.split(): fail('missing arm64 slice')
            deps=subprocess.check_output(['otool','-L',str(binary)],text=True)
            print('Mach-O linked dependencies:\n'+deps)
            if '/var/jb/' in deps: fail('generic rootless dependency in RootHide tweak')
            print('NOTE: dynamic_lookup imports still require runtime symbol resolution on device')
    print(f'PASS — independent package, iOS 17.3 RootHide, {LOADER} dylib, Bundles-only filter, architecture')

if __name__=='__main__':
    if len(sys.argv)!=2:
        print('Usage: verify_relaxin_deb.py path/to/one.deb',file=sys.stderr); sys.exit(2)
    try: main(sys.argv[1])
    except (ValueError,OSError,tarfile.TarError,subprocess.CalledProcessError) as e:
        print('FAIL',e,file=sys.stderr); sys.exit(1)
