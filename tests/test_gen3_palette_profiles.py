import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("palette_profiles", ROOT / "tools/gen3_palette_profiles.py")
PROFILES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PROFILES)


class PaletteProfiles(unittest.TestCase):
    def test_generated_manifest_profiles_match_catalog(self):
        for game in ("emerald", "firered"):
            manifest = json.loads((ROOT / f"tools/rom_manifest_{game}.json").read_text())
            profile = PROFILES.profile_for_sha1(manifest["romSha1"])
            self.assertEqual(profile, manifest["terrainPalettePrograms"])
            self.assertEqual(profile["game"], game)
            self.assertEqual(profile["romSha1"], manifest["romSha1"])
            self.assertIn("github.com/pret/", profile["source"])
            self.assertIn("terrainPalettePrograms", (ROOT / "tools/gen3_discover.py").read_text())

    def test_exact_hash_and_detached_recipe(self):
        sha1 = "f3ae088181bf583e55daf962a92bb46f4f1d07b7"
        self.assertIsNone(PROFILES.profile_for_sha1("0" * 40))
        profile = PROFILES.profile_for_sha1(sha1)
        profile["programs"].clear()
        self.assertEqual(len(PROFILES.profile_for_sha1(sha1)["programs"]), 20)

    def test_pinned_cartridge_program_semantics(self):
        emerald = PROFILES.profile_for_sha1("f3ae088181bf583e55daf962a92bb46f4f1d07b7")
        firered = PROFILES.profile_for_sha1("41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc")
        palette = emerald["programs"][str(0xA1658)]
        self.assertEqual((palette["table"], palette["first"], palette["count"], palette["frames"], palette["step"]),
                         (0x52487C, 128, 16, 4, 4))
        self.assertEqual(sum(p["kind"] == "frames" for p in emerald["programs"].values()), 1)
        self.assertEqual(sum(p["kind"] == "static" for p in emerald["programs"].values()), 19)
        self.assertEqual(len(firered["programs"]), 6)
        self.assertTrue(all(p["kind"] == "static" for p in firered["programs"].values()))


if __name__ == "__main__":
    unittest.main()
