import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

TOOLS=Path(__file__).resolve().parents[1]/'tools';sys.path.insert(0,str(TOOLS))
from qa_storage import Storage
import qa_legacy_storage as legacy
from install_qa_maintenance import install
REAL_BUSY=legacy.LiveUse.busy


class Retention(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.home=Path(self.tmp.name).resolve();self.root=self.home/'Documents/project';self.root.mkdir(parents=True)
        self.activity=patch('qa_legacy_storage.LiveUse.busy',return_value=False);self.activity.start();self.addCleanup(self.activity.stop)

    def manager(self,**options):
        m=Storage(self.root,home=self.home,min_free=0,**options);self.addCleanup(m.close);return m

    def put(self,p,data=b'source'):
        p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data);return p

    def show(self,parent,name,rel):
        proof=json.loads((parent/'qa-preserved-sources.json').read_text())[name]
        return subprocess.check_output(['git','--git-dir='+proof['git'],'show',proof['commit']+':snapshot/'+rel])

    def test_baseline_preserves_exact_models_sources_and_external_symlink(self):
        m=self.manager(copy_limit=0);p=m.copy(self.root/'.local/main-baseline')
        self.put(p/'main.lua',b'code\x00');self.put(p/'models/model.png',b'model')
        external=self.put(self.home/'original/model.bin',b'original');(p/'external').symlink_to(external)
        m.close();self.assertFalse(p.exists());self.assertEqual(external.read_bytes(),b'original')
        self.assertEqual(self.show(p.parent,p.name,'models/model.png'),b'model')
        self.assertEqual(self.show(p.parent,p.name,'external'),os.fsencode(external))

    def test_test_mod_roms_preferences_saves_and_custom_mod_remain(self):
        m=self.manager(copy_limit=0);profile=self.home/'Library/Application Support/LOVE/ula-live-switch-suite-0'
        mod=m.copy(profile/'mods/german_rom_source');self.put(mod/'manifest.json',b'{"id":"german_rom_source"}');self.put(mod/'code.lua')
        protected=[self.put(mod/'baseroms/original.gba'),self.put(mod/'baseroms/preferences.txt'),self.put(mod/'nested/saves/a.bin'),self.put(mod/'nested/game.sav'),self.put(profile/'red/save/player.lua'),self.put(profile/'mods/custom/model.bin')]
        m.close();self.assertTrue(all(p.exists()for p in protected));self.assertFalse((mod/'code.lua').exists())
        self.assertEqual(self.show(mod.parent,mod.name,'code.lua'),b'source')

    def test_nested_keep_marker_keeps_subtree(self):
        m=self.manager(copy_limit=0);p=m.copy(self.root/'.local/baseline')
        self.put(p/'old.lua');kept=self.put(p/'kept/source.lua');self.put(p/'kept/.qa-keep',b'')
        m.close();self.assertTrue(kept.exists());self.assertFalse((p/'old.lua').exists())

    def test_real_or_nested_git_checkouts_never_pruned(self):
        m=self.manager(copy_limit=0);p=m.copy(self.root/'.local/engine-parity/reference')
        source=self.put(p/'main.lua');self.put(p/'nested/.git/HEAD',b'ref: refs/heads/main')
        m.close();self.assertTrue(source.exists())

    def test_native_engine_copy_keeps_reports_host_and_saves(self):
        m=self.manager(copy_limit=0);run=self.root/'.local/qa/gen2recomp-qa-ruby-20261025000000'
        m.cache(run);source=self.put(run/'engine/main.lua');report=self.put(run/'verification.json');host=self.put(run/'host/conf.lua')
        save=self.put(self.home/'Library/Application Support/LOVE'/run.name/'ruby/save/player.lua')
        m.close();self.assertFalse(source.exists());self.assertTrue(report.exists()and host.exists()and save.exists())

    def test_source_lease_protects_baseline(self):
        p=self.root/'.local/main-baseline';writer=self.manager(copy_limit=100000);writer.copy(p);source=self.put(p/'main.lua');writer.close()
        reader=self.manager();reader.source(p/'main.lua')
        cleaner=self.manager(copy_limit=0);cleaner.sweep();self.assertTrue(source.exists())
        reader.close(collect=False);cleaner.sweep();self.assertFalse(source.exists())

    def test_profile_and_compiled_cache_leases_protect_mod_installation(self):
        profile=self.home/'Library/Application Support/LOVE/ula-test-qa';mod=profile/'mods/german_rom_source'
        writer=self.manager(copy_limit=100000);writer.copy(mod);source=self.put(mod/'code.lua');writer.close()
        owner=self.manager();owner.ula(profile/'modstorage/german_rom_source/compiled')
        cleaner=self.manager(copy_limit=0);cleaner.sweep();self.assertTrue(source.exists())
        owner.close(collect=False);cleaner.sweep();self.assertFalse(source.exists())

    def test_inherited_legacy_lease_survives_parent_close(self):
        owner=self.manager(copy_limit=0);p=owner.copy(self.root/'.local/baseline');source=self.put(p/'main.lua')
        child=owner.popen([sys.executable,'-c','import time;time.sleep(30)'])
        try:
            owner.close();cleaner=self.manager(copy_limit=0);cleaner.sweep();self.assertTrue(source.exists())
        finally:child.terminate();child.wait()
        cleaner.sweep();self.assertFalse(source.exists())

    def test_combined_budget_for_modern_and_additional_copies(self):
        clock=[time.time()];options=dict(copy_limit=100000,clock=lambda:clock[0])
        old=self.manager(**options);run=old.cache(self.root/'.local/qa/gen2-edition-mod/oasc-gen2recomp-qa-full109-20261025000000-ruby');a=self.put(run/'engine/a.lua');old.close()
        clock[0]+=1;new=self.manager(**options);p=new.copy(self.root/'.local/main-baseline');b=self.put(p/'b.lua');new.close()
        cleaner=self.manager(copy_limit=6000,clock=lambda:clock[0]);cleaner.sweep()
        self.assertFalse(a.exists());self.assertTrue(b.exists())

    def test_failed_archive_retains_copy(self):
        m=self.manager(copy_limit=0);p=m.copy(self.root/'.local/main-baseline');source=self.put(p/'main.lua')
        with patch('qa_preserved.Vault.capture',side_effect=OSError('archive unavailable')):m.close()
        self.assertTrue(source.exists())

    def test_new_reader_after_archiving_prevents_deletion(self):
        p=self.root/'.local/main-baseline';source=self.put(p/'main.lua')
        with self.assertRaises(RuntimeError):legacy.preserve(p,self.home,active=lambda path:True)
        self.assertTrue(source.exists())

    def test_new_immutable_copy_is_not_discovered_as_old(self):
        p=self.root/'.local/main-baseline';source=self.put(p/'main.lua');os.utime(source,(100,100));os.utime(p,(100,100))
        self.manager(copy_limit=0).sweep();self.assertTrue(source.exists())

    def test_periodic_discovery_removes_old_unregistered_copy(self):
        p=self.root/'.local/engine-parity/old';source=self.put(p/'main.lua')
        self.manager(copy_limit=0,clock=lambda:time.time()+7200).sweep();self.assertFalse(source.exists())

    def test_unmanaged_live_process_cwd_is_protected(self):
        p=self.root/'.local/main-baseline';p.mkdir(parents=True)
        child=subprocess.Popen([sys.executable,'-c','import time;time.sleep(30)'],cwd=p)
        try:self.assertTrue(REAL_BUSY(legacy.LiveUse(),p))
        finally:child.terminate();child.wait()

    def test_process_inspection_failure_fails_closed(self):
        with patch('qa_legacy_storage.subprocess.check_output',side_effect=OSError('ps unavailable')):
            self.assertTrue(REAL_BUSY(legacy.LiveUse(),self.root/'.local/baseline'))

    def test_arbitrary_sources_players_releases_and_aliases_are_rejected(self):
        m=self.manager()
        for p in [self.root/'src',self.home/'Library/Application Support/LOVE/player/mods/german_rom_source',self.root/'dist/official-release.zip']:
            with self.assertRaises(ValueError):m.copy(p)
        original=self.put(self.home/'original/a');link=self.root/'.local/main-baseline';link.parent.mkdir();link.symlink_to(original.parent)
        with self.assertRaises(ValueError):m.copy(link)

    def test_candidate_zip_is_archived_but_official_release_retained(self):
        m=self.manager(copy_limit=0);p=m.copy(self.root/'dist/Origami-Ascendant-Gen2Recomped-test-candidate.zip');self.put(p,b'zip bytes')
        release=self.put(p.parent/'official-release.zip');m.close()
        self.assertFalse(p.exists());self.assertTrue(release.exists());self.assertEqual(self.show(p.parent,p.name,p.name),b'zip bytes')

    def test_native_qa_import_cleanup_preserves_original_rom_and_save(self):
        m=self.manager(import_limit=0);p=m.destination(self.home/'Library/Application Support/LOVE/gen2recomp-qa-ruby-20261025000000')
        payload=self.put(p/'ruby/data/generated/maps.lua');original=self.put(p/'mods/german_rom_source/baseroms/original.gba');save=self.put(p/'ruby/save/player.lua')
        m.close();self.assertFalse(payload.exists());self.assertTrue(original.exists()and save.exists())

    def test_environment_reference_is_pinned_before_first_collection(self):
        writer=self.manager(copy_limit=100000);p=writer.copy(self.root/'.local/main-baseline');source=self.put(p/'a.lua');writer.close()
        reader=self.manager(copy_limit=0)
        reader.run([sys.executable,'-c','pass'],env=dict(os.environ,QA_REFERENCE_ROOT=str(p)),check=True)
        self.assertTrue(source.exists());self.manager(copy_limit=0).sweep();self.assertTrue(source.exists())
        reader.close(collect=False);self.manager(copy_limit=0).sweep();self.assertFalse(source.exists())

    def test_unmanaged_rewrite_protects_an_old_discovered_record(self):
        m=self.manager(copy_limit=0);p=self.root/'.local/main-baseline';source=self.put(p/'a.lua')
        m._write(m._key(p),dict(kind='legacy',path=str(p),root=str(self.root),updated=time.time()-90000,running=False,discovered=True))
        m.sweep();self.assertTrue(source.exists())

    def test_same_named_foreign_mod_and_empty_save_folders_remain(self):
        m=self.manager(copy_limit=0);p=m.copy(self.home/'Library/Application Support/LOVE/ula-test-qa/mods/german_rom_source')
        source=self.put(p/'main.lua');self.put(p/'manifest.json',b'{"id":"foreign"}');m.close();self.assertTrue(source.exists())
        n=self.manager(copy_limit=0);base=n.copy(self.root/'.local/baseline');self.put(base/'a.lua');empty=base/'baseroms/empty';empty.mkdir(parents=True)
        n.close();self.assertTrue(empty.is_dir())

    def test_gen1_generated_payloads_are_bounded_without_touching_saves(self):
        m=self.manager(import_limit=0);profile=m.destination(self.home/'Library/Application Support/LOVE/ula-test-qa')
        payload=self.put(profile/'gold/assets/generated/sprite.png');save=self.put(profile/'gold/save/player.lua')
        m.close();self.assertFalse(payload.exists());self.assertTrue(save.exists())

    def test_legacy_zip_argument_is_pinned_before_destination_collection(self):
        writer=self.manager(copy_limit=100000);p=writer.copy(self.root/'dist/Origami-Ascendant-Gen2Recomped-test-candidate.zip');self.put(p);writer.close()
        with patch.object(sys,'argv',['qa.py','--zip',str(p)]):reader=self.manager(copy_limit=0)
        reader.sweep();self.assertTrue(p.exists())
        reader.close(collect=False);self.manager(copy_limit=0).sweep();self.assertFalse(p.exists())

    def test_unmanaged_native_identity_protects_sibling_host_engine(self):
        writer=self.manager(copy_limit=100000);run=self.root/'.local/qa/gen2recomp-qa-ruby-20261025000000'
        writer.cache(run);source=self.put(run/'engine/main.lua');writer.close()
        profile=self.home/'Library/Application Support/LOVE'/run.name
        self.activity.stop()
        with patch('qa_legacy_storage.LiveUse.busy',side_effect=lambda p:p==profile):
            self.manager(copy_limit=0).sweep();self.assertTrue(source.exists())
        self.activity.start()

    def test_maintenance_install_uses_stable_package_and_smokes_without_real_home(self):
        plist,package=install([self.root],home=self.home,load=False,python=sys.executable)
        cfg=plistlib.loads(plist.read_bytes());self.assertEqual(cfg['StartInterval'],900)
        self.assertTrue(str(package).startswith(str(self.home/'.local/lib/')))
        completed=subprocess.run(cfg['ProgramArguments'],env=dict(os.environ,HOME=str(self.home)),capture_output=True,text=True)
        self.assertEqual(completed.returncode,0,completed.stderr)
        self.assertTrue((self.home/'.cache/origami-qa-storage/maintenance.log').is_file())


if __name__=='__main__':unittest.main()
