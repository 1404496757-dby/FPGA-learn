import argparse
import time
from packet_protocol import comm_request, comm_reply, read_exact

parser = argparse.ArgumentParser(description='ACX750 communication demo client (115200 8N1)')
parser.add_argument('--port', required=True, help='Actual board COM port, e.g. COM5')
parser.add_argument('--mode', choices=('echo', 'spi', 'status'), default='echo')
parser.add_argument('--value', type=lambda value: int(value, 0), default=0xC1)
parser.add_argument('--sequence', type=int, default=1)
args = parser.parse_args()
if not 0 <= args.value <= 255 or not 0 <= args.sequence <= 255:
    parser.error('value and sequence must be 0..255')
try:
    import serial
except ImportError:
    parser.error('Install pyserial in your Python environment: python -m pip install pyserial')
opcode = {'echo': 0, 'spi': 1, 'status': 2}[args.mode]
with serial.Serial(args.port, 115200, timeout=0.5, write_timeout=5) as port:
    time.sleep(0.1)
    port.reset_input_buffer()
    port.write(comm_request(opcode, args.sequence, args.value)); port.flush()
    packet = read_exact(port, 5)
status, value = comm_reply(packet, args.sequence)
if status != opcode:
    raise SystemExit(f'FPGA error status=0x{status:02X}')
if opcode in (0, 1) and value != args.value:
    raise SystemExit(f'Loopback mismatch: sent={args.value:02X} received={value:02X}')
print(f'PASS {args.mode}: status=0x{status:02X} value=0x{value:02X}')
