"""Validate a cloud-built device IPA before offering it for personal signing."""
import hashlib
import json
import plistlib
import struct
import sys
import zipfile
from pathlib import Path, PurePosixPath


def verify(path):
    path = Path(path)
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        for name in names:
            parts = PurePosixPath(name).parts
            if not name.startswith("Payload/Ozyy.app/") and name not in ("Payload/", "Payload/Ozyy.app/"):
                raise ValueError("Unexpected file outside the app payload")
            if ".." in parts or "\\" in name or name.startswith("/"):
                raise ValueError("Unsafe archive path")
            if name.endswith((".mobileprovision", ".p12", ".pfx", ".pem", ".key")) or "/_CodeSignature/" in name:
                raise ValueError("Signing material must not appear in the unsigned package")
        if archive.testzip() is not None:
            raise ValueError("Damaged ZIP member")
        info = plistlib.loads(archive.read("Payload/Ozyy.app/Info.plist"))
        if info.get("CFBundleIdentifier") != "xyz.ozyy.mobile" or info.get("DTPlatformName") != "iphoneos":
            raise ValueError("Not the Ozyy physical iPhone app")
        if info.get("CFBundleExecutable") != "Ozyy" or "iPhoneOS" not in info.get("CFBundleSupportedPlatforms", []):
            raise ValueError("Executable or platform mismatch")
        binary = archive.read("Payload/Ozyy.app/Ozyy")
        if len(binary) < 4096 or binary[:4] != b"\xcf\xfa\xed\xfe" or struct.unpack_from("<I", binary, 4)[0] != 0x0100000C:
            raise ValueError("Missing compiled arm64 Mach-O executable")
        if not info.get("MinimumOSVersion") or float(info["MinimumOSVersion"]) < 17:
            raise ValueError("Unexpected minimum iOS version")
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    print(json.dumps({"ipa": path.name, "bytes": path.stat().st_size, "sha256": digest, "signed": False, "requiresPersonalSigning": True}))


if __name__ == "__main__":
    verify(sys.argv[1])
