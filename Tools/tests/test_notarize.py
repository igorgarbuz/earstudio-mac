"""Exercise release safety gates without Apple credentials or network access."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'notarize.sh'

class NotarizeTests(unittest.TestCase):
    def run_case(self, status='Accepted', failure=''):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'Tools').mkdir()
            script = root / 'Tools/notarize.sh'
            shutil.copy2(SCRIPT, script)
            bin_dir = root / 'bin'
            bin_dir.mkdir()
            stub = '''#!/usr/bin/env python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
command = name + ' ' + ' '.join(args[:2])
with open(os.environ['CALLS'], 'a') as f: f.write(command + '\\n')
if os.environ.get('FAIL') and command.startswith(os.environ['FAIL']): sys.exit(1)
if name == 'xcrun' and args[:2] == ['notarytool', 'submit']:
    print(json.dumps({'id': 'test-id', 'status': os.environ['STATUS']}))
if name == 'xcrun' and args[:2] == ['notarytool', 'log']:
    pathlib.Path(args[-1]).write_text('{}')
if name == 'xcrun' and args[:2] == ['stapler', 'staple']:
    with open(args[-1], 'ab') as f: f.write(b'-ticket')
'''
            for tool in ('xcrun', 'codesign', 'spctl'):
                p = bin_dir / tool
                p.write_text(stub)
                p.chmod(0o755)
            image = root / 'App with spaces.dmg'
            image.write_bytes(b'signed-image')
            checksum = Path(str(image) + '.sha256')
            checksum.write_text('stale checksum')
            calls = root / 'calls'
            env = dict(os.environ, PATH=str(bin_dir)+os.pathsep+os.environ['PATH'],
                       STATUS=status, FAIL=failure, CALLS=str(calls))
            result = subprocess.run(['bash', str(script), str(image)], env=env,
                                    capture_output=True, text=True)
            return result, calls.read_text(), checksum.read_text() if checksum.exists() else None

    def test_success_hashes_stapled_bytes(self):
        result, calls, checksum = self.run_case()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(hashlib.sha256(b'signed-image-ticket').hexdigest(), checksum)
        self.assertIn('xcrun stapler validate', calls)
        self.assertIn('spctl --assess', calls)

    def test_rejected_or_pending_never_staples_or_creates_checksum(self):
        for status in ('Invalid', 'In Progress'):
            with self.subTest(status=status):
                result, calls, checksum = self.run_case(status)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn('xcrun stapler', calls)
                self.assertIsNone(checksum)

    def test_failures_never_leave_publishable_checksum(self):
        for failure in ('codesign', 'xcrun notarytool submit', 'xcrun stapler staple',
                        'xcrun stapler validate', 'spctl'):
            with self.subTest(failure=failure):
                result, calls, checksum = self.run_case(failure=failure)
                self.assertNotEqual(result.returncode, 0)
                self.assertIsNone(checksum)

if __name__ == '__main__':
    unittest.main()
