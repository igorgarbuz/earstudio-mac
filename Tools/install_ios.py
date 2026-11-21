#!/usr/bin/env python3
"""Incrementally build, sign and install on an unambiguously selected iPhone."""
import argparse
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile

from build_metadata import settings as build_settings
from apple_signing import SetupError, identities, select_team, verify_app

ROOT = Path(__file__).resolve().parent.parent
BUNDLE_ID = "com.igor.earstudio-companion.ios"


def device_json(arguments):
    with tempfile.TemporaryDirectory(prefix="earstudio-device-") as directory:
        output = Path(directory) / "result.json"
        subprocess.run(["xcrun", "devicectl", *arguments, "--timeout", "20", "--quiet",
                        "--json-output", str(output)], check=True)
        data = json.loads(output.read_text())
        if data.get("info", {}).get("outcome") != "success":
            raise SetupError("Device discovery failed; check the iPhone's cable, trust and Developer Mode.")
        return data["result"]


def iphones(data):
    return [d for d in data.get("devices", [])
            if d.get("hardwareProperties", {}).get("deviceType") == "iPhone"
            and d["hardwareProperties"].get("reality") == "physical"]


def connected(device):
    return device.get("connectionProperties", {}).get("tunnelState") == "connected"


def describe(device):
    return (f"{device.get('deviceProperties', {}).get('name', 'iPhone')} "
            f"[{device['identifier']}] — "
            f"{'connected' if connected(device) else 'not currently connected'}")


def select_device(devices, selector=None):
    if selector:
        choices = [d for d in devices if selector.casefold() in {
            d['identifier'].casefold(),
            d.get('hardwareProperties', {}).get('udid', '').casefold(),
            d.get('deviceProperties', {}).get('name', '').casefold()}]
    else:
        choices = [d for d in devices if connected(d)] or devices
    if len(choices) != 1:
        raise SetupError("Cannot choose one iPhone. Connect/unlock it, trust this Mac, or pass --device NAME_OR_ID.\n"
                         + "\n".join(describe(d) for d in devices))
    return choices[0]


def build_command(device, team, configuration):
    udid = device.get("hardwareProperties", {}).get("udid")
    if not udid:
        raise SetupError("Device has no hardware UDID; pair it with Xcode first.")
    return ["xcodebuild", "-project", str(ROOT / "EarStudioiOS.xcodeproj"),
            "-scheme", "EarStudioiOS", "-configuration", configuration,
            "-destination", f"platform=iOS,id={udid}",
            "-derivedDataPath", str(ROOT / "build/iOS-signed"),
            "-allowProvisioningUpdates", "-allowProvisioningDeviceRegistration",
            f"DEVELOPMENT_TEAM={team}", "CODE_SIGN_STYLE=Automatic",
            "CODE_SIGN_IDENTITY=Apple Development", "CODE_SIGNING_ALLOWED=YES", "build"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default=os.environ.get("IOS_DEVICE_ID"), help="iPhone name, hardware UDID or CoreDevice ID")
    parser.add_argument("--team", default=os.environ.get("APPLE_TEAM_ID"), help="Apple signing team ID")
    parser.add_argument("--configuration", choices=["Debug", "Release"], default="Debug")
    parser.add_argument("--launch", action="store_true", help="launch after successful installation")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--list", action="store_true", help="list discovered iPhones and certificate teams")
    mode.add_argument("--check", action="store_true", help="check device/signing prerequisites without building or installing")
    mode.add_argument("--dry-run", action="store_true", help="show selected device/team and commands, even if device is offline")
    args = parser.parse_args()
    subprocess.run(["xcodebuild", "-version"], check=True, stdout=subprocess.DEVNULL)
    devices = iphones(device_json(["list", "devices"]))
    available = identities()
    if args.list:
        print("\n".join(describe(d) for d in devices) or "No paired physical iPhones found.")
        print("Certificate teams: " + (", ".join(sorted({i.team for i in available})) or "none"))
        return
    device = select_device(devices, args.device)
    team = select_team(available, args.team)
    print(f"iPhone: {describe(device)}\nSigning team: {team}", flush=True)
    command = build_command(device, team, args.configuration)
    app = ROOT / "build/iOS-signed/Build/Products" / f"{args.configuration}-iphoneos" / "EarStudio iOS.app"
    install = ["xcrun", "devicectl", "device", "install", "app", "--device", device["identifier"], str(app)]
    launch = ["xcrun", "devicectl", "device", "process", "launch", "--device", device["identifier"], BUNDLE_ID]
    if args.dry_run:
        for operation in [command, install] + ([launch] if args.launch else []):
            print(shlex.join(operation))
        return
    # A paired device may be cached/offline. Refresh before any build or portal
    # mutation; devicectl can return cached details even with a success exit code.
    refreshed = device_json(["device", "info", "details", "--device", device["identifier"]])
    properties = refreshed.get("deviceProperties", {})
    if not connected(refreshed):
        raise SetupError("iPhone is offline. Connect it by USB, unlock it, and trust this Mac, then retry.")
    if properties.get("developerModeStatus") != "enabled":
        raise SetupError("Enable iPhone Settings → Privacy & Security → Developer Mode, restart and confirm.")
    if not properties.get("ddiServicesAvailable"):
        if args.check:
            raise SetupError("iPhone development services are not ready. Unlock the phone and run the installer so Xcode can prepare the device; ensure Xcode supports its iOS version.")
        print("Development services are not ready yet; Xcode will attempt device preparation.", flush=True)
    if args.check:
        print("Device prerequisites passed. Xcode account/provisioning access will be checked during the signed build.")
        return
    logs = ROOT / "build/logs"
    logs.mkdir(parents=True, exist_ok=True)
    log = logs / "ios-install-build.log"
    print(f"Building and signing incrementally; log: {log}", flush=True)
    metadata = build_settings("iOS", reserve=True)
    print("Build metadata: " + ", ".join(metadata), flush=True)
    command[-1:-1] = metadata
    with log.open("w") as stream:
        result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT)
    if result.returncode:
        print("\n".join(log.read_text(errors="replace").splitlines()[-60:]), file=sys.stderr)
        raise SetupError(f"Signed build failed; nothing installed. Sign into Xcode Accounts and check the team/device provisioning. Full log: {log}")
    verify_app(app, team)
    subprocess.run(install, check=True)
    if args.launch:
        subprocess.run(launch, check=True)
    print("Installed EarStudio on the selected iPhone.")


if __name__ == "__main__":
    try:
        main()
    except (SetupError, subprocess.CalledProcessError, OSError, ValueError, KeyError) as error:
        print(f"iPhone installation: {error}", file=sys.stderr)
        sys.exit(1)
