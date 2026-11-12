#!/usr/local/bin/python3

"""
What the GUI asks of juist, answered as JSON. The firewall's admin keys are
in a keystore of root's own, apart from juistd, which runs as the juist user
and holds none.

  juist.py status | devices | health | log | subnets | admins | invite-status
  juist.py keep-host-dns
  juist.py invite start|cancel EXPIRES
  juist.py remove DEVICE
"""

import json
import os
import re
import signal
import subprocess
import sys
import time

JUIST = '/usr/local/bin/juist'
KEYSTORE = '/var/db/juist-admin'
SOCKET = '/var/run/juist/juistd.sock'
RUNDIR = '/var/run/juist-admin'
INVITE_LOG = RUNDIR + '/invite.log'
INVITE_PID = RUNDIR + '/invite.pid'
ENV = {'JUIST_HOME': KEYSTORE, 'PATH': '/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin'}
TEXT = {
    'status': ['status'],
    'health': ['health'],
    'log': ['log'],
    'subnets': ['subnet'],
    'admins': ['admins'],
}


def juist(args):
    try:
        p = subprocess.run([JUIST] + args, env=ENV, capture_output=True, text=True, timeout=30,
                           stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired) as e:
        return {'rc': 1, 'output': str(e)}
    return {'rc': p.returncode, 'output': (p.stdout + p.stderr).strip()}


def table(text):
    """ juist's listings are columns padded to their widest value, so each starts where its header does """
    lines = [l for l in text.splitlines() if l.strip()]
    if not lines:
        return []
    starts = [m.start() for m in re.finditer(r'\S+', lines[0])]
    names = lines[0].split()
    rows = []
    for line in lines[1:]:
        if line.startswith(('hint:', 'warning:', 'juist:')):
            continue
        rows.append({
            name.lower(): line[start:end].strip()
            for name, start, end in zip(names, starts, starts[1:] + [None])
        })
    return rows


def devices():
    r = juist(['devices'])
    r['rows'] = table(r['output']) if r['rc'] == 0 else []
    for row in r['rows']:
        row['self'] = row.get('name', '').endswith(' (this device)')
        row['name'] = row.get('name', '').removesuffix(' (this device)')
    return r


def invite_pid():
    try:
        pid = int(open(INVITE_PID).read())
        os.kill(pid, 0)
        return pid
    except (OSError, ValueError):
        return None


def invite_status():
    try:
        output = open(INVITE_LOG).read().strip()
    except OSError:
        output = ''
    link = re.search(r"juist:[^\s']+", output)
    return {'rc': 0, 'running': invite_pid() is not None, 'link': link.group(0) if link else '', 'output': output}


def invite(action, expires):
    pid = invite_pid()
    if pid:
        os.killpg(pid, signal.SIGTERM)
        for _ in range(20):
            if invite_pid() is None:
                break
            time.sleep(0.1)
    if action != 'start':
        return invite_status()
    if not re.fullmatch(r'[0-9]{1,3}[mhd]', expires):
        return {'rc': 1, 'output': 'an invite lasts like 15m, 2h or 7d'}
    os.makedirs(RUNDIR, mode=0o700, exist_ok=True)
    # The link alone, a 128-bit secret, and no code for the LAN to guess.
    # --yes admits whoever joins by it: the words cannot be compared here.
    with open(os.open(INVITE_LOG, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), 'w') as log:
        p = subprocess.Popen([JUIST, 'invite', '--yes', '--no-lan', '--expires', expires], env=ENV,
                             stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
    with open(INVITE_PID, 'w') as f:
        f.write(str(p.pid))
    return {'rc': 0, 'running': True, 'link': '', 'output': ''}


def keep_host_dns():
    """ juistd would point the firewall's resolv.conf at itself; the firewall keeps its own """
    for _ in range(10):
        if os.path.exists(SOCKET):
            return juist(['set', '--dns=false'])
        time.sleep(1)
    return {'rc': 1, 'output': 'juistd did not come up'}


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ''
    if cmd == 'keep-host-dns':
        return keep_host_dns()
    if cmd in TEXT:
        return juist(TEXT[cmd])
    if cmd == 'devices':
        return devices()
    if cmd == 'invite-status':
        return invite_status()
    if cmd == 'invite' and len(argv) == 4:
        return invite(argv[2], argv[3])
    if cmd == 'remove' and len(argv) == 3 and re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9.-]*', argv[2]):
        return juist(['remove', argv[2], '--yes'])
    return {'rc': 2, 'output': 'juist.py: unknown request'}


print(json.dumps(main(sys.argv)))
