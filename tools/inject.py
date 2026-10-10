import socket, struct, sys, time
# Minimal radiotap-header injector on a monitor iface. stdlib only.
# usage: inject.py <iface> <type> <count>   type in {probe,data,rts,auth}
iface, ftype, count = sys.argv[1], sys.argv[2], int(sys.argv[3])
RT = struct.pack('<BBHI', 0, 0, 8, 0)           # radiotap: ver,pad,len=8,present=0
SELF = bytes.fromhex('845cf32383cd')  # our (locally-administered) TA
BCAST = b'\xff\xff\xff\xff\xff\xff'
BSSID = bytes.fromhex('ccd843b2dd27')           # Abracadabra 5GHz
def mgmt(subtype, extra=b''):
    fc = struct.pack('<H', (0<<2)|(subtype<<4)) # type=mgmt(0)
    return fc + b'\x00\x00' + BCAST + SELF + BSSID + b'\x00\x00' + extra
frames = {
    'probe': mgmt(4, b'\x00\x00' + b'\x01\x04\x02\x04\x0b\x16'),  # probe-req, SSID wildcard + rates
    'auth':  mgmt(11, b'\x00\x00\x01\x00\x00\x00'),               # auth
    'data':  struct.pack('<H',(2<<2)|(0<<4)|0x0100) + b'\x00\x00' + BSSID + SELF + BCAST + b'\x00\x00', # data toDS
    'm4':    struct.pack('<H',(0<<2)|(4<<4)) + b'\x00\x00' + BCAST + bytes.fromhex('02deadbeef01') + BCAST + b'\x00\x00' + b'\x00\x0aINJTEST-M4' + b'\x01\x04\x02\x04\x0b\x16',
    'rts':   struct.pack('<H',(1<<2)|(11<<4)) + b'\x00\x00' + BSSID + SELF,  # ctrl RTS
}
pkt = RT + frames[ftype]
s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW)
s.bind((iface, 0))
sent=0
for i in range(count):
    try:
        s.send(pkt); sent+=1
    except OSError as e:
        print(f"send {i} failed: {e}"); break
    time.sleep(0.03)
print(f"sent {sent}/{count} {ftype} frames ({len(pkt)} bytes each)")
