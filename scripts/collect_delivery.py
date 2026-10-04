"""Index explicitly selected, verified builds; do not select a build by age."""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--comm-build', required=True, type=Path)
parser.add_argument('--image-build', required=True, type=Path)
args = parser.parse_args()

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

records = json.loads((ROOT / 'verification_all.json').read_text(encoding='utf-8-sig'))
image_update = ROOT / 'verification_image.json'
if image_update.exists():
    update = json.loads(image_update.read_text(encoding='utf-8-sig'))
    if isinstance(update, dict):
        update = [update]
    records = [next((u for u in update if u['test'] == r['test']), r) for r in records]
markers = {'common': 'PASS_COMMON:', 'comm': 'PASS_COMM:', 'uart_board': 'PASS_UART_BOARD:',
           'image': 'PASS_IMAGE:', 'interview': 'PASS_INTERVIEW:', 'spi': 'PASS_SPI:'}
assert {r['test'] for r in records} == set(markers), 'Missing test group'
for r in records:
    assert r['passed'] and markers[r['test']] in (Path(r['run']) / 'simulation.log').read_text(errors='replace')
pixels = json.loads((Path(next(r['run'] for r in records if r['test'] == 'image')) / 'pixel_check.json').read_text())
assert len(pixels) == 4 and all(r['passed'] and r['pixels'] == 4096 for r in pixels)

sources = json.loads((ROOT / 'SOURCE_MANIFEST.json').read_text(encoding='utf-8-sig'))
for repo in sources['sources']:
    for f in repo['files']:
        assert digest(ROOT / f['path']) == f['sha256'], 'Vendor content changed: ' + f['path']

builds = {}
for mode, build in [('comm', args.comm_build.resolve()), ('image', args.image_build.resolve())]:
    assert build.is_relative_to(ROOT / 'builds'), 'Build outside this project'
    status = dict(line.split('=', 1) for line in (build / 'build_status.txt').read_text().splitlines())
    assert status['part'] == 'xc7a35tfgg484-2' and float(status['wns_ns']) >= 0 and float(status['whs_ns']) >= 0
    assert re.search(r'Violations found:\s*0', (build / 'drc.rpt').read_text()), 'Unresolved DRC'
    timing = (build / 'timing.rpt').read_text()
    for pattern in [r'There are 0 ports with no output delay specified',
                    r'There are 0 register/latch pins with no clock',
                    r'There are 0 pins that are not constrained for maximum delay\.']:
        assert re.search(pattern, timing), 'Missing timing constraints'
    util = (build / 'utilization.rpt').read_text()
    usage = {}
    for label in ['Slice LUTs', 'Slice Registers', 'Block RAM Tile', 'DSPs']:
        value = re.search(r'\|\s*' + re.escape(label) + r'\s*\|\s*([\d.]+)\s*\|', util)
        assert value, 'Missing utilization: ' + label
        usage[label] = float(value.group(1))
    bit = build / ('jianli_' + mode + '.runs') / 'impl_1' / (status['top'] + '.bit')
    assert bit.stat().st_size > 1000
    dest = ROOT / 'output' / mode
    dest.mkdir(parents=True, exist_ok=True)
    for f in [bit, build / 'timing.rpt', build / 'utilization.rpt', build / 'drc.rpt', build / 'cdc.rpt']:
        shutil.copy2(f, dest / f.name)
    builds[mode] = {'build': str(build), 'project': str(build / ('jianli_' + mode + '.xpr')),
                    'bitstream': str(dest / bit.name), 'bitstream_sha256': digest(dest / bit.name),
                    'wns_ns': float(status['wns_ns']), 'whs_ns': float(status['whs_ns']),
                    'drc_violations': 0, 'usage': usage, 'board_tested': False}

files = [ROOT / 'README.md']
for directory in ['rtl', 'sim', 'constraints', 'scripts', 'host', 'vendor', 'docs']:
    files += [f for f in (ROOT / directory).rglob('*') if f.is_file() and '__pycache__' not in f.parts]
status = {'generated_at': datetime.now().astimezone().isoformat(), 'tool': 'Vivado 2018.3 / XSim / FFmpeg',
          'board': 'ACX750', 'part': 'xc7a35tfgg484-2', 'tests': records, 'pixel_checks': pixels,
          'builds': builds, 'physical_board_tested': False, 'spi_board_connection': 'internal MOSI/MISO loopback',
          'not_implemented': ['CAN', 'SD storage', 'DDR', 'camera', 'encoder feedback', 'physical motor control', 'ILA insertion'],
          'environment_note': 'Vivado Common 17-741: local Tcl store is unavailable; installation-area fallback used.',
          'client_dependency': 'pyserial is listed in host/requirements.txt; no physical serial test performed',
          'source_sha256': {str(f.relative_to(ROOT)): digest(f) for f in sorted(files)}}
(ROOT / 'DELIVERY_STATUS.json').write_text(json.dumps(status, ensure_ascii=False, indent=2), encoding='utf-8')
print('PASS_DELIVERY: six simulation groups, four independent pixel checks, two constrained builds; board test pending')
