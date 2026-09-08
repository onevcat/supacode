#!/usr/bin/env python3
"""Check behavioral evidence from the native harness, not its implementation."""
import json
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
r = json.loads((root / 'results.json').read_text())
assert r['host_pid_before'] == r['host_pid_after'] > 0, r
assert (root / 'input.bin').read_bytes() == b'jpa', r
assert r['input_bytes'] == 3, r
assert r['sent_frames'] == 5, r
for name, marker in [('initial', 'count=0'), ('input', 'count=1'),
                     ('reconnect', 'count=2'), ('primary', 'screen=primary'),
                     ('alternate-again', 'screen=alternate')]:
    host = (root / f'{name}-host.txt').read_text()
    client = (root / f'{name}-client.txt').read_text()
    assert marker in host, (name, host)
    assert host == client, (name, host, client)
    assert '中文 日本語 café' in client, (name, client)
    vt = (root / f'{name}-client.vt').read_bytes()
    assert vt == (root / f'{name}-host.vt').read_bytes(), (name, 'VT round-trip mismatch')
    assert b'38;2' in vt and b'48;2' in vt, name
    # The pinned formatter omits completed OSC 8 links from VT content.
    assert b'https://example.com' not in vt, (name, 'recheck known limitation')
    assert b'\x1b[9;5H' in vt, (name, 'cursor position missing')
assert r['snapshot_count'] > 0
fixture_pids = {re.search(r'PID=(\d+)', p.read_text()).group(1)
                for p in root.glob('*-host.txt')}
assert len(fixture_pids) == 1, fixture_pids
print(json.dumps(r, indent=2))
print('PASS: attach, styled content, Unicode, cursor, input, reconnect, primary screen, host PID')
