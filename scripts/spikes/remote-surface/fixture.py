#!/usr/bin/env python3
"""Deterministic PTY fixture. It never runs a shell or an agent."""
import os
import sys
import tty

tty.setraw(sys.stdin.fileno())
count = 0
alternate = True

def draw():
    screen = '\x1b[?1049h' if alternate else '\x1b[?1049l'
    text = (screen + '\x1b[0m\x1b[2J\x1b[H'
            + '\x1b[1;36mRemote surface spike\x1b[0m\r\n'
            + 'Unicode: 中文 日本語 café e\u0301 🐈\r\n'
            + '\x1b[38;2;230;90;70mRGB foreground\x1b[0m '
            + '\x1b[48;2;30;80;120mRGB background\x1b[0m\r\n'
            + '\x1b[7mSelected item\x1b[0m  \x1b[4mUnderline\x1b[0m\r\n'
            + '\x1b]8;;https://example.com\x1b\\Link\x1b]8;;\x1b\\\r\n'
            + f'PID={os.getpid()} count={count} screen={"alternate" if alternate else "primary"}\r\n'
            + 'Keys: j = increment, p = primary, a = alternate\r\n'
            + '\x1b[?2004h\x1b[?25h\x1b[5 q\x1b[9;5H')
    os.write(1, text.encode())

draw()
while True:
    key = os.read(0, 1)
    if not key:
        break
    if key == b'j':
        count += 1
    elif key == b'p':
        alternate = False
    elif key == b'a':
        alternate = True
    draw()
