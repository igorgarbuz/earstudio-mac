#!/usr/bin/env python3
"""Reserve per-platform build numbers and capture the source revision before building."""
import argparse
import fcntl
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parent.parent


def settings(platform, reserve=False, root=ROOT):
    config = root / 'Apps' / platform / 'Configuration/App.xcconfig'
    lock_dir = root / '.build-metadata'
    lock_dir.mkdir(exist_ok=True)
    with (lock_dir / 'build-number.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        revision = subprocess.check_output(['git', 'rev-parse', '--short=12', 'HEAD'], cwd=root, text=True).strip()
        modified = bool(subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=normal'], cwd=root, text=True).strip())
        source = config.read_text()
        match = re.search(r'^CURRENT_PROJECT_VERSION = ([0-9]+)$', source, re.M)
        if not match:
            raise ValueError(f'{config}: expected an integer CURRENT_PROJECT_VERSION')
        counter = lock_dir / f'{platform}.json'
        previous = json.loads(counter.read_text()) if counter.exists() else 0
        number = max(int(match[1]), previous) + int(reserve)
        if reserve:
            temporary = counter.with_suffix('.tmp')
            temporary.write_text(json.dumps(number))
            temporary.replace(counter)
        return [f'CURRENT_PROJECT_VERSION={number}',
                f'EARSTUDIO_REVISION={revision}',
                f'EARSTUDIO_SOURCE_STATE={"modified" if modified else "clean"}']


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('platform', choices=['iOS', 'macOS'])
    parser.add_argument('--reserve', action='store_true')
    args = parser.parse_args()
    print('\n'.join(settings(args.platform, args.reserve)))
