"""Reject simulator/signed packages and report provenance for the device IPA."""

import hashlib
import json
import os
import plistlib
import re
import struct
import sys
import zipfile
from pathlib import Path

BUNDLE_ID = "io.github.photoplayer.p6a936d329b934a8ba532081564a51c07"
APP_PATH = "Payload/PhotoPlayer.app/"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def verify_macho(data):
    require(len(data) >= 32, "Truncated Mach-O")
    magic, cpu, _, filetype, commands, command_bytes, _, _ = struct.unpack_from("<8I", data)
    require(magic == 0xFEEDFACF and cpu == 0x0100000C and filetype == 2,
            "Expected a thin arm64 Mach-O executable")
    require(32 + command_bytes <= len(data), "Truncated load commands")
    offset = 32
    platforms = []
    for _ in range(commands):
        require(offset + 8 <= 32 + command_bytes, "Invalid load command")
        command, size = struct.unpack_from("<2I", data, offset)
        require(size >= 8 and offset + size <= 32 + command_bytes, "Invalid command size")
        require(command != 0x1D, "Executable contains a code signature")
        if command == 0x32:  # LC_BUILD_VERSION; IOS=2, IOSSIMULATOR=7
            require(size >= 24, "Invalid build version command")
            platforms.append(struct.unpack_from("<I", data, offset + 8)[0])
        if command in (0x21, 0x2C):  # LC_ENCRYPTION_INFO[_64]
            require(size >= 20, "Invalid encryption command")
            require(struct.unpack_from("<I", data, offset + 16)[0] == 0,
                    "Encrypted executable")
        offset += size
    require(offset == 32 + command_bytes, "Load command length mismatch")
    require(platforms == [2], "Executable must target device iOS, not iOS Simulator")


def verify_ipa(path, expected_build):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        require(len(names) == len(set(names)), "Duplicate ZIP paths")
        require(all(n.startswith("Payload/") and ".." not in n.split("/") for n in names),
                "Unexpected ZIP path")
        require(not any("_CodeSignature" in n or n.endswith("embedded.mobileprovision") for n in names),
                "Signing material must not be included")
        info = plistlib.loads(archive.read(APP_PATH + "Info.plist"))
        require(info["CFBundleIdentifier"] == BUNDLE_ID, "Bundle ID changed")
        require(info["CFBundleVersion"] == expected_build, "Build number mismatch")
        require(info["CFBundleSupportedPlatforms"] == ["iPhoneOS"], "Not an iPhoneOS bundle")
        require(info["DTPlatformName"] == "iphoneos", "Wrong SDK platform")
        require(info["CFBundleExecutable"] == "PhotoPlayer", "Unexpected executable")
        require(APP_PATH + "PrivacyInfo.xcprivacy" in names, "Missing privacy manifest")
        verify_macho(archive.read(APP_PATH + "PhotoPlayer"))
    return {
        "bundle_id": info["CFBundleIdentifier"],
        "build_number": info["CFBundleVersion"],
        "version": info["CFBundleShortVersionString"],
        "minimum_ios": info["MinimumOSVersion"],
        "sdk": info["DTSDKName"],
        "platform": "iOS",
        "architecture": "arm64",
        "configuration": "Release",
        "unsigned": True,
        "sha256": hashlib.sha256(Path(path).read_bytes()).hexdigest(),
    }


if __name__ == "__main__":
    version_config = Path("Config/Version.xcconfig").read_text()
    build = re.search(r"^CURRENT_PROJECT_VERSION\s*=\s*(\d+)\s*$", version_config, re.M)[1]
    result = verify_ipa(sys.argv[1], build)
    result.update({
        "commit": os.environ["GITHUB_SHA"],
        "run_id": os.environ["GITHUB_RUN_ID"],
        "run_attempt": os.environ["GITHUB_RUN_ATTEMPT"],
        "run_url": f'{os.environ["GITHUB_SERVER_URL"]}/{os.environ["GITHUB_REPOSITORY"]}/actions/runs/{os.environ["GITHUB_RUN_ID"]}',
        "xcode_version": os.environ["EXPECTED_XCODE_VERSION"],
        "xcode_build": os.environ["EXPECTED_XCODE_BUILD"],
        "xcodegen_version": os.environ["XCODEGEN_VERSION"],
        "runner_label": "xcode-27",
        "runner_image": os.environ.get("ImageVersion", "unknown"),
    })
    print(json.dumps(result, indent=2))
