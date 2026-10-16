"""Verify the built deb ships the official, case-sensitive Phone bundle id.

Apple Platform Deployment lists the Phone app as com.apple.mobilephone.
This checks the artifact itself, not only the source tree.
"""
import pathlib
import plistlib
import sys
import tarfile

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else '/tmp/aac-debcheck')
filter_path = root / 'Library/MobileSubstrate/DynamicLibraries/AutoAnswerCall.plist'
dylib_path = root / 'Library/MobileSubstrate/DynamicLibraries/AutoAnswerCall.dylib'
if not filter_path.is_file() or not dylib_path.is_file():
    sys.exit('artifact layout missing filter plist or dylib')
bundles = plistlib.loads(filter_path.read_bytes())['Filter']['Bundles']
print('artifact filter bundles:', bundles)
if bundles != ['com.apple.mobilephone']:
    sys.exit('artifact filter bundle id is not the official com.apple.mobilephone')
dylib = dylib_path.read_bytes()
if b'com.apple.mobilephone' not in dylib:
    sys.exit('artifact dylib missing the official bundle id guard')
if b'MobilePhone' not in dylib:
    sys.exit('artifact dylib missing the process-name compatibility fallback')
print('artifact bundle id check passed (filter is lowercase only; dylib keeps the fallback)')
