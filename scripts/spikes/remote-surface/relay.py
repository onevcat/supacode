#!/usr/bin/env python3
"""Display framed VT snapshots; relay PTY input back to the host socket."""
import os
import selectors
import socket
import struct
import sys
import tty

tty.setraw(0)
stream = socket.socket(socket.AF_UNIX)
stream.connect(sys.argv[1])
selector = selectors.DefaultSelector()
selector.register(stream, selectors.EVENT_READ)
selector.register(0, selectors.EVENT_READ)
buffer = bytearray()
while True:
    for key, _ in selector.select():
        if key.fileobj == 0:
            data = os.read(0, 4096)
            if not data:
                sys.exit(0)
            stream.sendall(data)
        else:
            data = stream.recv(65536)
            if not data:
                sys.exit(0)
            buffer.extend(data)
            while len(buffer) >= 4:
                length = struct.unpack('!I', buffer[:4])[0]
                if length > 4 * 1024 * 1024:
                    raise ValueError('frame exceeds spike limit')
                if len(buffer) < length + 4:
                    break
                payload = bytes(buffer[4:4 + length])
                del buffer[:4 + length]
                # Reset the display replica before applying a complete snapshot.
                frame = b'\x1b[?2026h\x1b[?1049l\x1b[0m\x1b[2J\x1b[H' + payload + b'\x1b[?2026l'
                while frame:
                    frame = frame[os.write(1, frame):]
