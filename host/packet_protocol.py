"""Pure protocol helpers shared by PC clients. No serial port opened on import."""
import struct
import time

def crc16(data):
    value = 0xFFFF
    for byte in data:
        value ^= byte << 8
        for _ in range(8):
            value = ((value << 1) ^ (0x1021 if value & 0x8000 else 0)) & 0xFFFF
    return value

def xor8(data):
    result = 0
    for byte in data:
        result ^= byte
    return result

def comm_request(opcode, sequence, value):
    body = bytes((0xA5, opcode, sequence, value))
    return body + bytes((xor8(body),))

def comm_reply(packet, sequence):
    if len(packet) != 5 or packet[0] != 0x5A or xor8(packet) != 0 or packet[2] != sequence:
        raise ValueError('Invalid communication reply framing/checksum/sequence')
    return packet[1], packet[3]

def image_request(pixels, sequence):
    if len(pixels) != 4096:
        raise ValueError('Expected exactly 64x64 grayscale pixels')
    body = bytes((sequence,)) + pixels
    return b'JL' + body + struct.pack('<H', crc16(body))

def image_reply(packet, sequence):
    if len(packet) < 8 or packet[:2] != b'JS' or packet[2] != sequence:
        raise ValueError('Invalid image reply header/sequence')
    size = int.from_bytes(packet[4:6], 'little')
    if size > 32768 or len(packet) != size + 8:
        raise ValueError('Invalid image reply length')
    if crc16(packet[2:-2]) != int.from_bytes(packet[-2:], 'little'):
        raise ValueError('Image reply CRC mismatch')
    if packet[3] != 0:
        raise ValueError(f'FPGA rejected frame: status=0x{packet[3]:02X}')
    return packet[6:-2]

def read_exact(port, count, deadline_seconds=20):
    output = bytearray()
    deadline = time.monotonic() + deadline_seconds
    while len(output) < count:
        output.extend(port.read(count-len(output)))
        if time.monotonic() > deadline:
            raise TimeoutError(f'Serial response timed out after {len(output)}/{count} bytes')
    return bytes(output)

def self_test():
    assert crc16(b'123456789') == 0x29B1
    request = comm_request(0, 1, 0x13)
    assert request == bytes.fromhex('A5 00 01 13 B7')
    assert comm_reply(bytes.fromhex('5A 00 01 13 48'), 1) == (0, 0x13)
    body = bytes((7, 0, 2, 0, 0xFF, 0xD9))
    packet = b'JS'+body+struct.pack('<H', crc16(body))
    assert image_reply(packet, 7) == b'\xff\xd9'
    print('PASS_HOST_PROTOCOL: CRC known vector, byte order, checksum and framing')

if __name__ == '__main__':
    self_test()
