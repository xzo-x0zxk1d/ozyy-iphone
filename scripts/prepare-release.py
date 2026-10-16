"""Validate an authorized ad-hoc IPA on macOS and prepare immutable OTA assets.
Never obtains certificates, creates accounts, uploads credentials or purchases signing.
"""
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile

def require(ok, message):
    if not ok:
        raise ValueError(message)

def command(args, data=None):
    result = subprocess.run(args, input=data, capture_output=True, check=False)
    require(result.returncode == 0, "Apple signing verification failed. No release was prepared.")
    return result.stdout

def prepare(ipa, output):
    require(sys.platform == "darwin", "Native signing verification requires macOS with Xcode. Nothing was published.")
    require(ipa.is_file() and 0 < ipa.stat().st_size <= 200 * 1024 * 1024, "Expected an IPA under 200 MiB.")
    for tool in ("codesign", "security", "openssl"):
        require(shutil.which(tool), "Apple signing verification tools are missing.")
    with tempfile.TemporaryDirectory(prefix="ozyy-ipa-") as staging:
        root = Path(staging)
        with zipfile.ZipFile(ipa) as archive:
            entries = archive.infolist()
            require(len(entries) < 10000 and sum(e.file_size for e in entries) < 512 * 1024 * 1024, "IPA contents exceed release limits.")
            seen = set()
            for entry in entries:
                path = PurePosixPath(entry.filename)
                require(entry.filename not in seen and not path.is_absolute() and ".." not in path.parts and "\\" not in entry.filename and "\x00" not in entry.filename, "Invalid IPA archive path.")
                seen.add(entry.filename)
                require(not stat.S_ISLNK(entry.external_attr >> 16) and not entry.flag_bits & 1, "Links and encrypted archive entries are unsupported.")
            archive.extractall(root)
        apps = list((root / "Payload").glob("*.app"))
        require(len(apps) == 1, "Expected one iPhone application in the IPA.")
        app = apps[0]
        info = plistlib.loads((app / "Info.plist").read_bytes())
        require(info.get("CFBundleIdentifier") == "xyz.ozyy.mobile", "This IPA belongs to a different application.")
        version, build = str(info.get("CFBundleShortVersionString", "")), str(info.get("CFBundleVersion", ""))
        require(re.fullmatch(r"\d+\.\d+\.\d+", version) and re.fullmatch(r"\d+", build), "Invalid release version.")
        require("iPhoneOS" in info.get("CFBundleSupportedPlatforms", []), "Simulator builds cannot be installed on phones.")
        command(["codesign", "--verify", "--deep", "--strict", "-R", "anchor apple generic", str(app)])
        profile_path = app / "embedded.mobileprovision"
        require(profile_path.is_file(), "A valid provisioning profile is required.")
        profile = plistlib.loads(command(["security", "cms", "-D", "-i", str(profile_path)]))
        # Publicly borrowed enterprise certificates are not a distribution plan for family apps.
        require(not profile.get("ProvisionsAllDevices") and bool(profile.get("ProvisionedDevices")), "Only authorized ad-hoc device distribution is supported by this release tool.")
        expected = profile.get("Entitlements", {})
        require(expected.get("get-task-allow") is False, "Development provisioning cannot be published as a direct installer.")
        signed_bytes = command(["codesign", "-d", "--entitlements", ":-", str(app)])
        xml_start = signed_bytes.find(b"<?xml")
        signed = plistlib.loads(signed_bytes[xml_start:] if xml_start >= 0 else signed_bytes)
        require(signed.get("get-task-allow", False) is False and signed.get("application-identifier") == expected.get("application-identifier"), "Signed app entitlements do not match the profile.")
        require(str(signed.get("application-identifier", "")).endswith(".xyz.ozyy.mobile"), "Incorrect application identity.")
        expiration = profile["ExpirationDate"].replace(tzinfo=dt.timezone.utc)
        for cert in profile.get("DeveloperCertificates", []):
            line = command(["openssl", "x509", "-inform", "DER", "-noout", "-enddate"], cert).decode().strip()
            date = dt.datetime.strptime(line.removeprefix("notAfter="), "%b %d %H:%M:%S %Y %Z").replace(tzinfo=dt.timezone.utc)
            expiration = min(expiration, date)
        require(expiration > dt.datetime.now(dt.timezone.utc) + dt.timedelta(hours=24), "Signing expires too soon to release this build.")
    with ipa.open("rb") as source:
        digest = hashlib.file_digest(source, "sha256").hexdigest()
    filename = f"ozyy-ios-{version}-{digest[:12]}.ipa"
    output.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ipa, output / filename)
    release = {"ready": True, "bundleId": "xyz.ozyy.mobile", "version": version, "build": build,
        "ipaUrl": f"https://api.ozyy.xyz/download/{filename}", "sha256": digest,
        "bytes": ipa.stat().st_size, "expiresAt": int(expiration.timestamp() * 1000), "distribution": "ad-hoc"}
    (output / "ios-release.json").write_text(json.dumps(release, indent=2) + "\n", encoding="utf-8")
    print("Verified signed release prepared. Installation is limited to devices authorized by its provisioning profile. Apple may revoke signing before the listed expiry.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    try:
        prepare(args.ipa.resolve(), args.output.resolve())
    except (ValueError, KeyError, OSError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        print(f"BLOCKED: {error}", file=sys.stderr)
        sys.exit(2)
