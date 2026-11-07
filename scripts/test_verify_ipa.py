import plistlib
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

from verify_ipa import APP_PATH, BUNDLE_ID, verify_ipa


class DevicePackageValidationTests(unittest.TestCase):
    def package(self, root, platform=2, signed=False, bundle_id=BUNDLE_ID):
        commands = struct.pack("<6I", 0x32, 24, platform, 0, 0, 0)
        if signed:
            commands += struct.pack("<4I", 0x1D, 16, 0, 0)
        macho = struct.pack("<8I", 0xFEEDFACF, 0x0100000C, 0, 2,
                            2 if signed else 1, len(commands), 0, 0) + commands
        info = {
            "CFBundleIdentifier": bundle_id,
            "CFBundleVersion": "1",
            "CFBundleShortVersionString": "0.1.0",
            "CFBundleSupportedPlatforms": ["iPhoneOS"],
            "DTPlatformName": "iphoneos",
            "CFBundleExecutable": "PhotoPlayer",
            "MinimumOSVersion": "17.0",
            "DTSDKName": "iphoneos27.1",
        }
        path = Path(root) / "test.ipa"
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr(APP_PATH + "Info.plist", plistlib.dumps(info))
            archive.writestr(APP_PATH + "PhotoPlayer", macho)
            archive.writestr(APP_PATH + "PrivacyInfo.xcprivacy", plistlib.dumps({}))
        return path

    def test_device_package_is_accepted(self):
        with tempfile.TemporaryDirectory() as root:
            self.assertEqual(verify_ipa(self.package(root), "1")["platform"], "iOS")

    def test_arm64_simulator_cannot_masquerade_as_device(self):
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaisesRegex(ValueError, "device iOS"):
                verify_ipa(self.package(root, platform=7), "1")

    def test_signed_binary_is_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaisesRegex(ValueError, "code signature"):
                verify_ipa(self.package(root, signed=True), "1")

    def test_changed_identity_or_build_is_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaisesRegex(ValueError, "Bundle ID"):
                verify_ipa(self.package(root, bundle_id="other.app"), "1")
            with self.assertRaisesRegex(ValueError, "Build number"):
                verify_ipa(self.package(root), "2")
