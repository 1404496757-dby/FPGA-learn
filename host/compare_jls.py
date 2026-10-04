"""Decode the four HDL-generated JPEG-LS frames and compare every pixel."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('run_dir', type=Path)
parser.add_argument('--ffmpeg', default=shutil.which('ffmpeg'))
args = parser.parse_args()
if not args.ffmpeg:
    parser.error('ffmpeg not found; supply --ffmpeg ABSOLUTE_PATH')
results = []
for index in range(4):
    encoded = args.run_dir / f'image_{index}.jls'
    original = (args.run_dir / f'image_{index}.raw').read_bytes()
    decoded = args.run_dir / f'image_{index}.decoded.raw'
    subprocess.run([args.ffmpeg, '-hide_banner', '-loglevel', 'error', '-y',
                    '-i', str(encoded), '-frames:v', '1', '-f', 'rawvideo',
                    '-pix_fmt', 'gray', str(decoded)], check=True)
    actual = decoded.read_bytes()
    if len(original) != 4096 or actual != original:
        raise SystemExit(f'FAIL image {index}: original={len(original)}, decoded={len(actual)}')
    results.append({'frame': index, 'pixels': len(actual), 'encoded_bytes': encoded.stat().st_size,
                    'raw_over_encoded': len(original)/encoded.stat().st_size,
                    'pixel_sha256': hashlib.sha256(actual).hexdigest(), 'passed': True})
(args.run_dir / 'pixel_check.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
print('PASS_JLS_PIXELS: all four 64x64 images match exactly after independent software decoding')
