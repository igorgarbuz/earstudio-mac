#!/usr/bin/env python3
"""Public certificate metadata only; private keys stay in the macOS Keychain."""
import argparse
from dataclasses import dataclass
import os
import re
import subprocess
import sys


class SetupError(RuntimeError):
    pass


@dataclass(frozen=True)
class Identity:
    fingerprint: str
    name: str
    team: str


def certificate_metadata(pem):
    result = subprocess.run(
        ["openssl", "x509", "-noout", "-subject", "-fingerprint", "-sha1",
         "-nameopt", "sep_multiline"], input=pem, text=True, capture_output=True, check=True)
    fingerprint = re.search(r"Fingerprint=([A-Fa-f0-9:]+)", result.stdout)
    team = re.search(r"^\s*OU\s*=\s*([A-Z0-9]{10})\s*$", result.stdout, re.MULTILINE)
    return (fingerprint.group(1).replace(":", "").upper() if fingerprint else "",
            team.group(1) if team else "")


def identities():
    valid = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"],
                           text=True, capture_output=True, check=True).stdout
    names = {fingerprint.upper(): name for fingerprint, name in
             re.findall(r'\d+\)\s+([A-Fa-f0-9]{40})\s+"([^"\n]+)"', valid)}
    if not names:
        return []
    # The suffix in an Apple Development common name can be a person ID, NOT
    # the team. Match the public certificate's fingerprint and read its OU.
    certificates = subprocess.run(["security", "find-certificate", "-a", "-p"],
                                  text=True, capture_output=True, check=True).stdout
    found = {}
    for pem in re.findall(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----",
                          certificates, re.DOTALL):
        fingerprint, team = certificate_metadata(pem)
        if fingerprint in names and team:
            found[fingerprint] = Identity(fingerprint, names[fingerprint], team)
    return list(found.values())


def select_team(available, explicit=None):
    if explicit:
        if not re.fullmatch(r"[A-Z0-9]{10}", explicit):
            raise SetupError("Team ID must contain ten uppercase letters/digits.")
        # Xcode can provision a development certificate for an explicitly chosen
        # account even when no matching private-key identity exists locally yet.
        return explicit
    prefixes = ("Apple Development:", "iPhone Developer:", "Apple Distribution:",
                "iPhone Distribution:", "Developer ID Application:")
    teams = sorted({i.team for i in available if i.name.startswith(prefixes)})
    if len(teams) != 1:
        raise SetupError("Cannot choose one signing team. Detected: " +
                         (", ".join(teams) or "none") +
                         ". Pass --team TEAM_ID or set APPLE_TEAM_ID; sign into Xcode Accounts first.")
    return teams[0]


def select_mac_identity(available, team=None, selector=None):
    choices = [i for i in available if i.name.startswith("Developer ID Application:")
               and (not team or i.team == team)
               and (not selector or selector in (i.name, i.fingerprint))]
    if len(choices) != 1:
        raise SetupError(
            "A unique Developer ID Application identity with its private key is required. "
            "Create/download that certificate in Xcode Accounts → Manage Certificates, "
            "or import its certificate and private key. Apple Development is insufficient for distribution. "
            "Select among multiple identities with APPLE_TEAM_ID and/or MACOS_SIGN_IDENTITY. "
            "Use --ad-hoc only for local/CI builds.")
    return choices[0]


def verify_app(path, team, developer_id=False):
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(path)], check=True)
    result = subprocess.run(["codesign", "-d", "--verbose=4", str(path)],
                            text=True, capture_output=True, check=True)
    metadata = result.stderr + result.stdout
    if f"TeamIdentifier={team}\n" not in metadata:
        raise SetupError("Built app's signing team does not match the requested team.")
    if developer_id and ("Authority=Developer ID Application:" not in metadata
                         or not re.search(r"^CodeDirectory .*flags=.*\bruntime\b", metadata, re.MULTILINE)
                         or "\nTimestamp=" not in metadata):
        raise SetupError("Release signature needs Developer ID, hardened runtime and a secure timestamp.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["mac", "verify-mac"])
    parser.add_argument("path", nargs="?")
    parser.add_argument("--team", default=os.environ.get("APPLE_TEAM_ID"))
    args = parser.parse_args()
    if args.action == "mac":
        selected = select_mac_identity(identities(), args.team, os.environ.get("MACOS_SIGN_IDENTITY"))
        print(selected.fingerprint)
        print(selected.team)
    else:
        if not args.path or not args.team:
            parser.error("verify-mac requires a path and --team")
        verify_app(args.path, args.team, developer_id=True)


if __name__ == "__main__":
    try:
        main()
    except (SetupError, subprocess.CalledProcessError, OSError) as error:
        print(f"Signing setup: {error}", file=sys.stderr)
        sys.exit(1)
