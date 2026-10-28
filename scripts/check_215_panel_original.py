from pathlib import Path
base=Path(__file__).resolve().parents[1]
code=(base/'DYYYLongPressPanel.xm').read_text()
make=(base/'Makefile').read_text()
provider=(base/'DYYYOriginalQualityProvider.m').read_text()
settings=(base/'DYYYSettingViewController.m').read_text()
for key in ['保存封面','保存音频','保存图片','保存全部图片','解析下载地址','复制原画地址','保存原画视频']:
 assert key in code, f'missing homepage action: {key}'
assert 'DYYYOriginalQualityProvider.m' in make
assert 'dynamic_lookup' not in [x for x in make.splitlines() if x.strip().startswith('$(TWEAK_NAME)_LDFLAGS')]
assert 'fetch_video_high_quality_play_url' in provider and 'original_video_url' in provider
assert 'DYYYOriginalQualityToken' in settings and 'Bearer ' in provider
assert 'SecItemCopyMatching' in provider and 'SecItemAdd' in provider and 'SecItemUpdate' in provider
assert 'if (!token.length)' in provider
print('2.0.19 offline source checks passed; third-party API live availability NOT verified.')
