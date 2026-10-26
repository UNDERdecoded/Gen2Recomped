"""Filesystem and process-level safety checks for disposable QA caches."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
from qa_storage import Storage


class CacheLifecycle(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.root = self.home / "Documents/repo"
        self.root.mkdir(parents=True)
        self.state = self.home / "registry"
        self.managers = []

    def manager(self, **options):
        manager = Storage(self.root, home=self.home, state=self.state,
                          min_free=0, **options)
        self.managers.append(manager)
        self.addCleanup(manager.close)
        return manager

    def profile(self, name="oasc-test-qa-fixture"):
        return self.home / "Library/Application Support/LOVE" / name

    def payload(self, path, size=12000):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"x" * size)
        return path

    def test_finish_removes_only_generated_imports(self):
        manager = self.manager(import_limit=0)
        profile = manager.destination(self.profile())
        generated = self.payload(profile / "emerald/data/generated/maps.lua")
        assets = self.payload(profile / "emerald/assets/generated/tile.png")
        marker = self.payload(profile / "emerald/rom-cache.complete")
        protected = [self.payload(profile / p) for p in
                     ["emerald/save/save.lua", "options.lua", "result.json", "shot.png",
                      "mods/custom/main.lua"]]
        manager.close()
        self.assertFalse(generated.exists())
        self.assertFalse(assets.exists())
        self.assertFalse(marker.exists())
        self.assertTrue(all(p.exists() for p in protected))

    def test_player_and_unsafe_identity_are_rejected(self):
        manager = self.manager()
        player = self.payload(self.profile("oasc-private-work-1-0-1") /
                              "emerald/data/generated/maps.lua")
        with self.assertRaises(ValueError):
            manager.destination(player.parents[3])
        self.assertTrue(player.exists())
        with self.assertRaises(ValueError):
            manager.identity("../oasc-test-qa-escape")

    def test_symlinked_generated_cache_never_changes_target(self):
        manager = self.manager(import_limit=0)
        profile = manager.destination(self.profile())
        original = self.payload(self.home / "original/maps.lua")
        link = profile / "emerald/data/generated"
        link.parent.mkdir(parents=True)
        link.symlink_to(original.parent, target_is_directory=True)
        manager.close()
        self.assertTrue(original.exists())
        self.assertTrue(link.is_symlink())

    def test_foreign_nested_link_and_readonly_cache(self):
        manager = self.manager(import_limit=0)
        profile = manager.destination(self.profile())
        file = self.payload(profile / "emerald/data/generated/maps.lua")
        original = self.payload(self.home / "source.txt")
        (file.parent / "foreign").symlink_to(original)
        file.parent.chmod(0o500)
        manager.close()
        self.assertFalse(file.exists())
        self.assertTrue(original.exists())

    def test_active_profile_cannot_be_evicted_by_another_manager(self):
        first = self.manager(import_limit=0)
        profile = first.destination(self.profile())
        data = self.payload(profile / "emerald/data/generated/maps.lua")
        second = self.manager(import_limit=0)
        second.sweep()
        self.assertTrue(data.exists())
        first.close()
        self.assertFalse(data.exists())

    def test_borrowed_cache_stays_pinned_until_reader_finishes(self):
        owner = self.manager(import_limit=10**8)
        profile = owner.destination(self.profile())
        data = self.payload(profile / "emerald/data/generated/maps.lua")
        owner.close()
        reader = self.manager(import_limit=10**8)
        reader.source(profile)
        cleaner = self.manager(import_limit=0)
        cleaner.sweep()
        self.assertTrue(data.exists())
        reader.close()
        cleaner.sweep()
        self.assertFalse(data.exists())

    def test_default_import_aliases_pin_all_source_editions_before_collection(self):
        owner = self.manager(import_limit=10**8)
        profile = owner.destination(self.profile())
        data = self.payload(profile / 'ruby/data/generated/map.lua')
        owner.close()
        imports = self.root / '.local/imports'
        imports.mkdir(parents=True)
        (imports / 'ruby').symlink_to(profile / 'ruby', target_is_directory=True)
        reader = self.manager(import_limit=0)
        reader.cache(self.root / '.local/qa/new-run')
        self.assertTrue(data.exists())
        reader.close()
        self.assertTrue(data.exists(), 'persistent .local/imports template must remain reusable')
        (imports / 'ruby').unlink()
        self.manager(import_limit=0).sweep()
        self.assertFalse(data.exists())

    def test_cache_budget_and_age_keep_reports_and_installed_cache(self):
        manager = self.manager(geometry_limit=0)
        output = manager.cache(self.root / ".local/qa/bake")
        old = self.payload(output / "ruby" / ("a" * 64 + ".data"))
        installed = self.payload(output / "bundle" / ("b" * 64 + ".data"))
        report = self.payload(output / "result.json")
        index = self.payload(output / "ruby/index.data")
        (self.root / "gen3").mkdir()
        (self.root / "gen3/render-cache").symlink_to(installed.parent,
                                                     target_is_directory=True)
        manager.close()
        self.assertFalse(old.exists())
        self.assertTrue(installed.exists())
        self.assertTrue(report.exists())
        self.assertTrue(index.exists())

    def test_explicit_output_outside_qa_is_not_disposable(self):
        manager = self.manager(geometry_limit=0)
        folder = self.home / "release"
        self.assertEqual(manager.cache(folder), folder)
        file = self.payload(folder / ("c" * 64 + ".data"))
        manager.close()
        self.assertTrue(file.exists())

    def test_keep_marker_preserves_reference_payload(self):
        manager = self.manager(geometry_limit=0, max_age=0)
        folder = manager.cache(self.root / '.local/qa/reference')
        file = self.payload(folder / ('d' * 64 + '.data'))
        (folder / '.qa-keep').touch()
        manager.close()
        self.assertTrue(file.exists())
        (folder / '.qa-keep').unlink()
        self.manager(geometry_limit=0).sweep()
        self.assertFalse(file.exists())

    def test_installed_cache_in_another_worktree_remains_protected(self):
        manager = self.manager(geometry_limit=0)
        folder = manager.cache(self.root / '.local/qa/bake')
        file = self.payload(folder / ('f' * 64 + '.data'))
        other = self.home / 'Documents/consumer'
        (other / 'gen3').mkdir(parents=True)
        (other / 'gen3/render-cache').symlink_to(folder, target_is_directory=True)
        consumer = Storage(other, home=self.home, state=self.state,
                           min_free=0, geometry_limit=0)
        consumer.close()
        manager.close()
        self.assertTrue(file.exists())
        (other / 'gen3/render-cache').unlink()
        self.manager(geometry_limit=0).sweep()
        self.assertFalse(file.exists())

    def test_budget_is_shared_across_worktrees(self):
        owner = self.manager(geometry_limit=10**8)
        file = self.payload(owner.cache(self.root / '.local/qa/bake') / ('e' * 64 + '.data'))
        owner.close()
        other_root = self.home / 'Documents/other-repo'
        other_root.mkdir()
        cleaner = Storage(other_root, home=self.home, state=self.state,
                          min_free=0, geometry_limit=0)
        self.addCleanup(cleaner.close)
        cleaner.sweep()
        self.assertFalse(file.exists())

    def test_old_idle_entry_expires_even_below_budget(self):
        manager = self.manager(import_limit=10**8, max_age=1)
        profile = manager.destination(self.profile())
        data = self.payload(profile / "ruby/data/generated/maps.lua")
        manager.close()
        cleaner = self.manager(import_limit=10**8, max_age=1,
                               clock=lambda: time.time() + 5)
        cleaner.sweep()
        self.assertFalse(data.exists())

    def test_low_disk_refuses_child_before_it_writes(self):
        manager = self.manager()
        manager.identity("oasc-test-qa-fixture")
        manager.min_free = 100
        marker = self.home / "child-started"
        with patch("qa_storage.shutil.disk_usage", return_value=(100, 99, 1)):
            with self.assertRaises(RuntimeError):
                manager.run([sys.executable, "-c",
                             "from pathlib import Path;Path(%r).touch()" % str(marker)])
        self.assertFalse(marker.exists())

    def test_timeout_releases_after_child_has_stopped(self):
        manager = self.manager(import_limit=0)
        profile = manager.destination(self.profile())
        data = self.payload(profile / "ruby/data/generated/maps.lua")
        with self.assertRaises(subprocess.TimeoutExpired):
            manager.run([sys.executable, "-c", "import time;time.sleep(5)"], timeout=.1)
        manager.close()
        self.assertFalse(data.exists())

    def test_running_child_is_stopped_before_disk_is_exhausted(self):
        manager = self.manager(import_limit=0)
        manager.identity("oasc-test-qa-fixture")
        manager.min_free = 100
        finished = self.home / "finished"
        readings = iter([(1000, 0, 1000), (1000, 999, 1)])
        with patch("qa_storage.shutil.disk_usage", side_effect=lambda _: next(readings)):
            with self.assertRaisesRegex(RuntimeError, "safety reserve"):
                manager.run([sys.executable, "-c",
                             "import time;from pathlib import Path;time.sleep(5);Path(%r).touch()" % str(finished)])
        self.assertFalse(finished.exists())

    def test_subprocess_output_input_and_failure_contract_is_preserved(self):
        manager = self.manager()
        result = manager.run([sys.executable, "-c", "import sys;print(sys.stdin.read().upper())"],
                             input="hello", capture_output=True, text=True, check=True)
        self.assertEqual(result.stdout, "HELLO\n")
        self.assertEqual(result.returncode, 0)
        with self.assertRaises(subprocess.CalledProcessError) as error:
            manager.run([sys.executable, "-c", "import sys;print('proof');sys.exit(3)"],
                        capture_output=True, text=True, check=True)
        self.assertEqual(error.exception.returncode, 3)
        self.assertEqual(error.exception.stdout, "proof\n")

    def test_popen_guard_reports_failure_to_polling_runner(self):
        manager = self.manager()
        manager.min_free = 100
        readings = iter([(1000, 0, 1000), (1000, 999, 1)])
        with patch('qa_storage.shutil.disk_usage', side_effect=lambda _: next(readings)):
            process = manager.popen([sys.executable, '-c', 'import time;time.sleep(10)'])
            with self.assertRaisesRegex(RuntimeError, 'safety reserve'):
                process.wait(timeout=5)
            with self.assertRaises(RuntimeError):
                process.poll()

    def test_actual_shell_launcher_preserves_child_leases(self):
        manager = self.manager(import_limit=0)
        profile = manager.destination(self.profile())
        self.payload(profile / 'ruby/data/generated/map.lua')
        # Use the real production shell entrypoint, with a fake executable.
        launcher = TOOLS.parent / 'Start.command'
        (self.root / 'Start.command').write_bytes(launcher.read_bytes())
        (self.root / 'Start.command').chmod(0o700)
        local = self.root / '.local'
        local.mkdir()
        fake = self.root / 'fake-love'
        fake.write_text('#!' + sys.executable + '\nimport os,json\n'
                        "data=json.loads(os.environ['ORIGAMI_QA_LEASES'])\n"
                        "assert all(os.fstat(x['fd']) for x in data['leases'])\n"
                        "assert os.environ['POKEPORT_IDENTITY']=='oasc-test-qa-fixture'\n"
                        "print('leases-survived-shell')\n")
        fake.chmod(0o700)
        (local / 'love-path.txt').write_text(str(fake))
        result = manager.run([str(self.root / 'Start.command'), 'ruby'],
                             env=dict(os.environ, OA_QA_IDENTITY=profile.name),
                             capture_output=True, text=True, check=True, timeout=5)
        self.assertEqual(result.stdout, 'leases-survived-shell\n')

    def test_nested_python_runner_reuses_parent_lease_without_deadlock(self):
        manager = self.manager(import_limit=0)
        profile = manager.destination(self.profile())
        data = self.payload(profile / "ruby/data/generated/maps.lua")
        code = ("import sys;from pathlib import Path;sys.path.insert(0,%r);"
                "from qa_storage import Storage;"
                "s=Storage(Path(%r),home=Path(%r),state=Path(%r),min_free=0,import_limit=0);"
                "s.destination(Path(%r));s.close()" %
                (str(TOOLS), str(self.root), str(self.home), str(self.state), str(profile)))
        manager.run([sys.executable, "-c", code], check=True, timeout=5)
        self.assertTrue(data.exists())
        manager.close()
        self.assertFalse(data.exists())

    def test_love11_identity_does_not_create_a_second_love12_cache(self):
        manager = self.manager()
        profile = self.home / "Library/Application Support/oasc-test-qa-lua11"
        manager.destination(profile)
        manager.run([sys.executable, "-c", "pass"],
                    env=dict(os.environ, POKEPORT_IDENTITY=profile.name), check=True)
        records = [json.loads(p.read_text()) for p in self.state.glob("*.json")]
        self.assertEqual([p["path"] for p in records], [str(profile.resolve())])

    def test_gen2_cli_identity_is_managed_without_environment_override(self):
        manager = self.manager(import_limit=0)
        identity = 'oasc-gen2recomp-qa-native_fixture'
        data = self.payload(self.profile(identity) / 'ruby/data/generated/map.lua')
        process = manager.popen([sys.executable, '-c', 'import time;time.sleep(.1)',
                                 '--qa-identity', identity])
        cleaner = self.manager(import_limit=0)
        cleaner.sweep()
        self.assertTrue(data.exists())
        self.assertEqual(process.wait(timeout=5), 0)
        manager.close()
        self.assertFalse(data.exists())

    def test_child_retains_lease_if_parent_is_killed(self):
        script = self.home / "owner.py"
        ready = self.home / "ready"
        child_pid = self.home / "child.pid"
        script.write_text("import sys,time,os\nfrom pathlib import Path\n"
            "sys.path.insert(0,%r)\nfrom qa_storage import Storage\n" % str(TOOLS) +
            "s=Storage(Path(%r),home=Path(%r),state=Path(%r),min_free=0,import_limit=0)\n" %
            (str(self.root), str(self.home), str(self.state)) +
            "p=s.destination(Path(%r))/'ruby/data/generated/map.lua'\n" % str(self.profile()) +
            "p.parent.mkdir(parents=True);p.write_text('cache')\n"
            "s.run([sys.executable,'-c',%r])\n" %
            ("import os,time;from pathlib import Path;Path(%r).write_text(str(os.getpid()));Path(%r).touch();time.sleep(30)" %
             (str(child_pid), str(ready))))
        owner = subprocess.Popen([sys.executable, str(script)])
        self.addCleanup(lambda: owner.poll() is None and owner.kill())
        deadline = time.monotonic() + 10
        while not ready.exists() and time.monotonic() < deadline:
            time.sleep(.02)
        self.assertTrue(ready.exists())
        pid = int(child_pid.read_text())
        self.addCleanup(lambda: self.kill_if_alive(pid))
        owner.kill(); owner.wait()
        cleaner = self.manager(import_limit=0)
        cleaner.sweep()
        data = self.profile() / "ruby/data/generated/map.lua"
        self.assertTrue(data.exists(), "live child lost its imported data")
        os.kill(pid, 15)
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            cleaner.sweep()
            if not data.exists(): break
            time.sleep(.02)
        self.assertFalse(data.exists(), "abandoned data was not reclaimed")

    @staticmethod
    def kill_if_alive(pid):
        try: os.kill(pid, 9)
        except ProcessLookupError: pass


if __name__ == "__main__":
    unittest.main()
