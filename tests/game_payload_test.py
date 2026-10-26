"""Exercise the mobile packers' immutable payload path without a device SDK."""
import json
import os
import shutil
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
try:
    from qa_storage import qa_source, qa_run
except ModuleNotFoundError as error:
    if error.name != "qa_storage":
        raise
    # Standalone upstream checkouts need no local disposable-cache manager.
    from subprocess import run as qa_run
    def qa_source(path):
        return path
from stage_game_payload import stage

qa_source(ROOT)


class PayloadContract(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="mobile-payload-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        qa_source(self.root)
        self.source = self.root / "frozen.love"
        self.destination = self.root / "assets/game.love"
        self.entries = {
            "main.lua": b"return true", "conf.lua": b"return true",
            "src/core/Version.lua": b'return {engine="1.2.3"}',
            "src/core/GameVersion.lua": b'return {manifest="tools/rom_manifest_test.json"}',
            "tools/rom_manifest_test.json": json.dumps({"romSha1": "a" * 40}).encode(),
        }

    def archive(self, extra=None):
        with zipfile.ZipFile(self.source, "w") as archive:
            for name, data in {**self.entries, **(extra or {})}.items():
                archive.writestr(name, data)

    def test_copy_preserves_signed_or_hashed_payload_bytes(self):
        self.archive()
        stage(self.source, self.destination, "1.2.3")
        self.assertEqual(self.source.read_bytes(), self.destination.read_bytes())
        stage(self.destination, self.destination, "1.2.3")
        self.assertEqual(self.source.read_bytes(), self.destination.read_bytes())

    def test_bad_payload_never_overwrites_previously_staged_payload(self):
        self.destination.parent.mkdir()
        self.destination.write_bytes(b"previous build")
        for name in ("map.gba", "test.nds", "slot.sav", "data/generated/map.lua", "../escape", "C:\\bad", "baseroms/cart.bin"):
            with self.subTest(name=name):
                self.archive({name: b"fixture"})
                with self.assertRaises(ValueError):
                    stage(self.source, self.destination)
                self.assertEqual(self.destination.read_bytes(), b"previous build")

    def test_missing_manifest_and_version_mismatch_are_errors(self):
        self.archive()
        with self.assertRaisesRegex(ValueError, "version"):
            stage(self.source, self.destination, "1.2.4")
        del self.entries["tools/rom_manifest_test.json"]
        self.archive()
        with self.assertRaises(KeyError):
            stage(self.source, self.destination)
        self.assertFalse(self.destination.exists())

    def test_android_script_embeds_exact_payload_with_separate_package(self):
        self.archive()
        for relative in ("scripts/build_android.sh", "tools/stage_game_payload.py"):
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, target)
        android = self.root / "mobile/android"
        (android / "love/src/jni/love/src").mkdir(parents=True)
        (android / "app/src/main").mkdir(parents=True)
        for name in ("settings.gradle", "gradlew"):
            (android / name).write_text("")
        (android / "gradle.properties").write_text("app.application_id=stable.app\napp.name=stable\n")
        manifest = android / "app/src/main/AndroidManifest.xml"
        manifest.write_text("<manifest><application></application></manifest>")
        host = self.root / "mobile/second-display/SecondDisplayHost.java"
        host.parent.mkdir(parents=True)
        host.write_text("// synthetic packaging fixture")
        result = qa_run(["bash", str(self.root / "scripts/build_android.sh"), "--package-only",
                         "--version", "1.2.3", "--game-love", str(self.source)],
                        env={**os.environ, "GEN2_APPLICATION_ID": "org.example.preview", "GEN2_APP_NAME": "Preview"},
                        capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((android / "app/src/embed/assets/game.love").read_bytes(), self.source.read_bytes())
        props = (android / "gradle.properties").read_text()
        self.assertIn("app.application_id=org.example.preview", props)
        self.assertIn("app.version_name=1.2.3", props)
        self.assertIn('android:authorities="org.example.preview.seconddisplay"', manifest.read_text())
        # The real vendored manifest already contains a provider. A subsequent
        # build with a different app ID must update it instead of preserving
        # an authority that conflicts with the stable installed application.
        result = qa_run(["bash", str(self.root / "scripts/build_android.sh"), "--package-only",
                         "--version", "1.2.3", "--game-love", str(self.source)],
                        env={**os.environ, "GEN2_APPLICATION_ID": "org.example.otherpreview"},
                        capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('android:authorities="org.example.otherpreview.seconddisplay"', manifest.read_text())
        self.assertNotIn('android:authorities="org.example.preview.seconddisplay"', manifest.read_text())
        self.assertEqual(manifest.read_text().count('<provider'), 1)


if __name__ == "__main__":
    unittest.main()
