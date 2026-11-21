import contextlib
import io
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import apple_signing as signing
import install_ios as installer


def phone(name="Phone", identifier="CORE-ID", udid="HARDWARE-UDID", online=True):
    return {"identifier": identifier,
            "hardwareProperties": {"deviceType": "iPhone", "reality": "physical", "udid": udid},
            "deviceProperties": {"name": name, "developerModeStatus": "enabled", "ddiServicesAvailable": online},
            "connectionProperties": {"tunnelState": "connected" if online else "disconnected"}}


class SelectionTests(unittest.TestCase):
    def test_connected_phone_wins_over_cached_phone(self):
        active = phone()
        self.assertEqual(installer.select_device([phone("Old", online=False), active]), active)

    def test_multiple_connected_phones_require_selection(self):
        devices = [phone(), phone("Second", "SECOND-ID", "SECOND-UDID")]
        with self.assertRaises(signing.SetupError):
            installer.select_device(devices)
        self.assertEqual(installer.select_device(devices, "SECOND-UDID"), devices[1])
        self.assertEqual(installer.select_device(devices, "Second"), devices[1])

    def test_simulators_and_ipads_are_excluded(self):
        simulated, ipad = phone(), phone()
        simulated["hardwareProperties"]["reality"] = "simulated"
        ipad["hardwareProperties"]["deviceType"] = "iPad"
        self.assertEqual(installer.iphones({"devices": [simulated, ipad, phone()]}), [phone()])

    def test_same_team_certificates_do_not_create_ambiguity(self):
        a = signing.Identity("A" * 40, "Apple Development: Person (PERSON1234)", "TEAM123456")
        b = signing.Identity("B" * 40, "Apple Distribution: Company", "TEAM123456")
        self.assertEqual(signing.select_team([a, b]), "TEAM123456")
        with self.assertRaises(signing.SetupError):
            signing.select_team([a, signing.Identity("C" * 40, b.name, "OTHER12345")])

    def test_explicit_team_allows_xcode_to_provision_new_identity(self):
        self.assertEqual(signing.select_team([], "TEAM123456"), "TEAM123456")
        with self.assertRaises(signing.SetupError):
            signing.select_team([], "invalid")

    def test_macos_never_substitutes_development_or_ambiguous_identity(self):
        development = signing.Identity("A" * 40, "Apple Development: Person", "TEAM123456")
        release = signing.Identity("B" * 40, "Developer ID Application: Company", "TEAM123456")
        renewed = signing.Identity("C" * 40, release.name, release.team)
        with self.assertRaises(signing.SetupError):
            signing.select_mac_identity([development])
        with self.assertRaises(signing.SetupError):
            signing.select_mac_identity([release, renewed])
        self.assertEqual(signing.select_mac_identity([release, renewed], selector=renewed.fingerprint), renewed)

    def test_team_comes_from_real_certificate_ou_not_common_name_suffix(self):
        # Generate a disposable public certificate; no account/keychain access.
        with tempfile.TemporaryDirectory() as temporary:
            cert = Path(temporary) / "certificate.pem"
            subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                            "-keyout", str(Path(temporary) / "key.pem"), "-out", str(cert),
                            "-days", "1", "-subj", "/CN=Apple Development: Person (PERSON1234)/OU=TEAM123456"],
                           check=True, capture_output=True)
            fingerprint, team = signing.certificate_metadata(cert.read_text())
            self.assertEqual(team, "TEAM123456")
            self.assertRegex(fingerprint, r"^[A-F0-9]{40}$")

    def test_distribution_verification_requires_team_runtime_authority_and_timestamp(self):
        good = ("TeamIdentifier=TEAM123456\nAuthority=Developer ID Application: Company\n"
                "CodeDirectory v=20500 size=120 flags=0x10000(runtime) hashes=3\nTimestamp=Today\n")
        for metadata, valid in [(good, True), (good.replace("TEAM123456", "OTHER12345"), False),
                                (good.replace("Developer ID Application", "Apple Development"), False),
                                (good.replace("0x10000(runtime)", "0x0(none)"), False),
                                (good.replace("Timestamp=Today\n", ""), False)]:
            with self.subTest(metadata=metadata), patch.object(signing.subprocess, "run", side_effect=[
                subprocess.CompletedProcess([], 0), subprocess.CompletedProcess([], 0, "", metadata)
            ]):
                if valid:
                    signing.verify_app("Example.app", "TEAM123456", developer_id=True)
                else:
                    with self.assertRaises(signing.SetupError):
                        signing.verify_app("Example.app", "TEAM123456", developer_id=True)


class InstallWorkflowTests(unittest.TestCase):
    def exercise(self, device=None, failed_build=False, failed_signature=False, dry_run=False):
        selected = device or phone()
        calls = []

        def run(command, **kwargs):
            calls.append(command)
            return subprocess.CompletedProcess(command, 1 if failed_build and "build" in command else 0)

        with tempfile.TemporaryDirectory() as directory, \
             patch.object(installer, "ROOT", Path(directory)), \
             patch.object(installer, "device_json", side_effect=[{"devices": [selected]}, selected]), \
             patch.object(installer, "build_settings", return_value=["CURRENT_PROJECT_VERSION=42", "EARSTUDIO_REVISION=abc123", "EARSTUDIO_SOURCE_STATE=modified"]), \
             patch.object(installer, "identities", return_value=[]), \
             patch.object(installer.subprocess, "run", side_effect=run), \
             patch.object(installer, "verify_app", side_effect=signing.SetupError("Wrong team") if failed_signature else None), \
             patch.object(sys, "argv", ["install-ios", "--team", "TEAM123456", "--launch"] + (["--dry-run"] if dry_run else [])), \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            error = None
            try:
                installer.main()
            except signing.SetupError as caught:
                error = caught
        return calls, error

    def test_offline_phone_never_builds_or_installs(self):
        calls, error = self.exercise(device=phone(online=False))
        self.assertIsNotNone(error)
        self.assertEqual(calls, [["xcodebuild", "-version"]])

    def test_build_failure_never_installs_stale_app(self):
        calls, error = self.exercise(failed_build=True)
        self.assertIsNotNone(error)
        self.assertFalse(any("install" in c for c in calls))

    def test_wrong_signature_never_installs(self):
        calls, error = self.exercise(failed_signature=True)
        self.assertIsNotNone(error)
        self.assertFalse(any("install" in c for c in calls))

    def test_dry_run_does_not_build_or_install(self):
        calls, error = self.exercise(dry_run=True)
        self.assertIsNone(error)
        self.assertEqual(calls, [["xcodebuild", "-version"]])

    def test_build_uses_udid_install_uses_coredevice_id_and_always_builds(self):
        calls, error = self.exercise()
        self.assertIsNone(error)
        build = next(c for c in calls if "build" in c)
        self.assertIn("platform=iOS,id=HARDWARE-UDID", build)
        self.assertIn("CURRENT_PROJECT_VERSION=42", build)
        install = next(c for c in calls if "install" in c)
        self.assertEqual(install[install.index("--device") + 1], "CORE-ID")
        self.assertLess(calls.index(build), calls.index(install))
        self.assertIn("launch", calls[-1])


if __name__ == "__main__":
    unittest.main()
