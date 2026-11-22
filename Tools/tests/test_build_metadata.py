import concurrent.futures
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_metadata import settings


class BuildMetadataTests(unittest.TestCase):
    def test_reservation_revision_and_modified_state(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            def git(*args):
                return subprocess.check_output(['git', *args], cwd=root, text=True).strip()
            git('init', '-q')
            (root / '.gitignore').write_text('build/\n.build-metadata/\n')
            for platform, number in [('iOS', 1), ('macOS', 13)]:
                config = root / 'Apps' / platform / 'Configuration/App.xcconfig'
                config.parent.mkdir(parents=True)
                config.write_text(f'CURRENT_PROJECT_VERSION = {number}\n')
            git('add', '.')
            git('-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-qm', 'Fixture')
            self.assertEqual(settings('iOS', root=root), [
                'CURRENT_PROJECT_VERSION=1', f'EARSTUDIO_REVISION={git("rev-parse", "--short=12", "HEAD")}',
                'EARSTUDIO_SOURCE_STATE=clean'])
            self.assertEqual(settings('iOS', True, root)[0], 'CURRENT_PROJECT_VERSION=2')
            self.assertEqual(settings('iOS', root=root)[2], 'EARSTUDIO_SOURCE_STATE=clean')
            (root / 'new-source.swift').write_text('// Uncommitted source')
            self.assertEqual(settings('iOS', root=root)[2], 'EARSTUDIO_SOURCE_STATE=modified')
            self.assertEqual(settings('macOS', root=root)[0], 'CURRENT_PROJECT_VERSION=13')
            with concurrent.futures.ThreadPoolExecutor() as pool:
                numbers = list(pool.map(lambda _: settings('iOS', True, root)[0], range(4)))
            self.assertEqual(set(numbers), {f'CURRENT_PROJECT_VERSION={n}' for n in range(3, 7)})
