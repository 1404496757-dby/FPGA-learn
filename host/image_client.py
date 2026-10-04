import argparse
from pathlib import Path
import struct
import subprocess
import time
from packet_protocol import image_request, image_reply, read_exact

parser = argparse.ArgumentParser(description='64x64 raw grayscale -> FPGA JPEG-LS -> decoded pixel comparison')
parser.add_argument('--port', required=True)
parser.add_argument('--pattern', choices=('gradient','checker','noise','constant'), default='gradient')
parser.add_argument('--input-raw', type=Path, help='Optional raw file containing exactly 4096 bytes')
parser.add_argument('--output', type=Path, default=Path('board_capture'))
parser.add_argument('--sequence', type=int, default=1)
parser.add_argument('--ffmpeg', default=r'C:\Program Files\ffmpeg-7.0.2-full_build\bin\ffmpeg.exe')
args = parser.parse_args()
if not 0 <= args.sequence <= 255:
    parser.error('sequence must be 0..255')
if args.input_raw:
    pixels=args.input_raw.read_bytes()
else:
    values=[]; prng=0x12345678
    for i in range(4096):
        x,y=i%64,i//64
        prng=(prng*1664525+1013904223)&0xFFFFFFFF
        values.append({'constant':127,'gradient':(x*3+y*5)&255,
                       'checker':255 if (x^y)&1 else 0,'noise':prng>>24}[args.pattern])
    pixels=bytes(values)
request=image_request(pixels,args.sequence)
try:
    import serial
except ImportError:
    parser.error('Install pyserial in your Python environment: python -m pip install pyserial')
with serial.Serial(args.port,115200,timeout=0.5,write_timeout=5) as port:
    time.sleep(0.1); port.reset_input_buffer()
    port.write(request); port.flush()
    header=read_exact(port,6)
    if header[:2]!=b'JS':
        raise ValueError('Unexpected response magic')
    size=struct.unpack('<H',header[4:6])[0]
    if size>32768:
        raise ValueError('Response exceeds supported buffer size')
    packet=header+read_exact(port,size+2)
encoded=image_reply(packet,args.sequence)
args.output.mkdir(parents=True,exist_ok=True)
(args.output/'original.raw').write_bytes(pixels)
(args.output/'response.packet').write_bytes(packet)
jls=args.output/'board.jls'; jls.write_bytes(encoded)
decoded=args.output/'decoded.raw'
subprocess.run([args.ffmpeg,'-hide_banner','-loglevel','error','-y','-i',str(jls),
                '-frames:v','1','-f','rawvideo','-pix_fmt','gray',str(decoded)],check=True)
if decoded.read_bytes()!=pixels:
    raise SystemExit('FAIL decoded pixels differ from input')
print(f'PASS_BOARD_IMAGE: 4096 pixels match, JLS bytes={len(encoded)}, output={args.output.resolve()}')
