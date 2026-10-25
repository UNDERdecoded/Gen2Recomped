import copy
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("component", Path(__file__).parents[1] / "tools/runtime-upvalue-check/component.py")
C = importlib.util.module_from_spec(spec)
spec.loader.exec_module(C)


def thin(arch):
    return struct.pack("<IIIIIIII", 0xFEEDFACF, 0x0100000C if arch == "arm64" else 0x01000007,
                       0, 6, 1, 24, 0, 0) + struct.pack("<IIIIII", 0x32, 24, 1, 0x000B0000, 0x000F0000, 0) + b"unit Mach-O payload"


def universal(first, second):
    offset = 48
    return (struct.pack(">II", 0xCAFEBABE, 2)
            + struct.pack(">IIIII", 0x01000007, 0, offset, len(first), 0)
            + struct.pack(">IIIII", 0x0100000C, 0, offset + len(first), len(second), 0)
            + first + second)


class Components(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.tree = {name: "a" * 40 for name in C.ENGINE_PATHS}

    def pair(self, platform="macos", arch="arm64"):
        library = thin(arch)
        if platform == "windows":
            data = bytearray(96)
            data[:2] = b"MZ"
            struct.pack_into("<I", data, 60, 64)
            data[64:68] = b"PE\0\0"
            struct.pack_into("<H", data, 68, 0x8664)
            library = bytes(data)
        capacity = dict(passed=True, sourceUnchanged=True, luaJitSource=C.PIN,
                        engineTree=self.tree, engineSource="b" * 40,
                        platform="Windows" if platform == "windows" else "Darwin",
                        machine="AMD64" if platform == "windows" else arch,
                        variants=[dict(name=name, capacity=limit, engineSuites=351,
                                       closure=dict(passed=True, minimum=limit),
                                       cApiCounts=[60] if limit == 60 else [60, 61, 64, 96, 120],
                                       librarySha256=C.sha(library))
                                  for name, limit in (("stock", 60), ("extended", 120))])
        raw = json.dumps(capacity).encode()
        host = dict(passed=True, platform=capacity["platform"], machine=capacity["machine"],
                    baseLoveCommit=C.LOVE, originalArchiveSha256=C.HOST_ARCHIVES[platform],
                    qualificationSha256=C.sha(raw), inputCandidateLibrarySha256=C.sha(library),
                    variants=[dict(variant=name, capacity=limit, checks=1)
                              for name, limit in (("stock", 60), ("extended", 120))])
        return capacity, host, library

    def check_pair(self, capacity, host, library, platform="macos"):
        raw = json.dumps(capacity).encode()
        return C.qualify(raw, json.dumps(host).encode(), library, platform)

    def bundle(self, platform="macos"):
        rows = []
        bodies = {}
        for arch in sorted(C.ARCHES[platform]):
            capacity, host, body = self.pair(platform, arch)
            cp, hp = arch + "-capacity.json", arch + "-host.json"
            (self.root / cp).write_text(json.dumps(capacity))
            (self.root / hp).write_text(json.dumps(host))
            rows.append(dict(architecture=arch, capacityReport=cp, hostReport=hp,
                             capacitySha256=C.sha((self.root / cp).read_bytes()),
                             hostSha256=C.sha((self.root / hp).read_bytes())))
            bodies[arch] = body
        library = (universal(bodies["x86_64"], bodies["arm64"])
                   if platform == "macos" else bodies["x86_64"])
        (self.root / "library").write_bytes(library)
        (self.root / "COPYRIGHT").write_bytes(b"unit license notice")
        manifest = dict(schema=1, experimental=True, platform=platform, capacity=120,
                        luaJitSource=C.PIN, baseLoveCommit=C.LOVE, library="library",
                        librarySha256=C.sha(library), qualifications=rows,
                        notice="COPYRIGHT", noticeSha256=C.sha(b"unit license notice"))
        p = self.root / "component.json"
        p.write_text(json.dumps(manifest))
        return p, manifest

    def test_complete_native_receipts_and_slices(self):
        for platform in ("windows", "macos"):
            with self.subTest(platform=platform):
                p, _ = self.bundle(platform)
                library, notice, manifest = C.verify(p, platform, self.tree)
                self.assertTrue(library.is_file() and notice.is_file())
                self.assertEqual(manifest["capacity"], 120)
                if platform == "macos":
                    self.assertEqual(manifest["minimumMacOS"], "11.0.0")

    def test_highest_native_macos_minimum_is_preserved(self):
        higher = bytearray(thin("x86_64"))
        struct.pack_into("<I", higher, 44, 0x000E0100)
        self.assertEqual(C.macos_minimum({"x86_64": bytes(higher), "arm64": thin("arm64")}), "14.1.0")

    def test_source_only_or_unrelated_host_report_is_rejected(self):
        capacity, host, body = self.pair()
        for key, value in (("passed", False), ("baseLoveCommit", "other"),
                           ("qualificationSha256", "0" * 64),
                           ("inputCandidateLibrarySha256", "0" * 64)):
            with self.subTest(key=key):
                changed = copy.deepcopy(host)
                changed[key] = value
                with self.assertRaises(ValueError):
                    self.check_pair(capacity, changed, body)

    def test_unbound_or_incomplete_engine_qualification_is_rejected(self):
        capacity, host, body = self.pair()
        for key, value in (("engineTree", {}), ("sourceUnchanged", False), ("passed", False)):
            with self.subTest(key=key):
                changed = copy.deepcopy(capacity)
                changed[key] = value
                with self.assertRaises(ValueError):
                    self.check_pair(changed, host, body)

    def test_runtime_from_other_engine_tree_is_rejected(self):
        p, _ = self.bundle()
        changed = dict(self.tree, src="0" * 40)
        with self.assertRaises(ValueError):
            C.verify(p, "macos", changed)

    def test_missing_mac_architecture_is_rejected(self):
        p, manifest = self.bundle()
        (self.root / "library").write_bytes(thin("arm64"))
        manifest["librarySha256"] = C.sha(thin("arm64"))
        p.write_text(json.dumps(manifest))
        with self.assertRaises(ValueError):
            C.verify(p, "macos", self.tree)

    def test_modified_slice_or_receipt_is_rejected(self):
        p, manifest = self.bundle()
        (self.root / "arm64-host.json").write_text("{}")
        with self.assertRaises(ValueError):
            C.verify(p, "macos", self.tree)
        p, manifest = self.bundle()
        data = (self.root / "library").read_bytes()[:-1] + b"!"
        (self.root / "library").write_bytes(data)
        manifest["librarySha256"] = C.sha(data)
        p.write_text(json.dumps(manifest))
        with self.assertRaises(ValueError):
            C.verify(p, "macos", self.tree)

    def test_fat_header_cannot_relabel_a_slice(self):
        with self.assertRaises(ValueError):
            C.slices(universal(thin("arm64"), thin("x86_64")), "macos")

    def test_notice_and_receipt_paths_are_bounded(self):
        for relative in ("../notice", "sub/../../notice", "../" + self.root.name + "/COPYRIGHT",
                         "/absolute", "C:\\data", "..\\notice"):
            with self.subTest(relative=relative), self.assertRaises(ValueError):
                C.child(self.root, relative)
        p, _ = self.bundle()
        (self.root / "COPYRIGHT").write_text("changed")
        with self.assertRaises(ValueError):
            C.verify(p, "macos", self.tree)

    def test_wrong_pe_architecture_is_rejected(self):
        _, _, library = self.pair("windows", "x86_64")
        changed = bytearray(library)
        struct.pack_into("<H", changed, 68, 0x014C)
        with self.assertRaises(ValueError):
            C.slices(bytes(changed), "windows")


if __name__ == "__main__":
    unittest.main()
