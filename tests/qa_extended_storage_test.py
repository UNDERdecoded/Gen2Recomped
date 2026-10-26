"""Regression checks for pruning QA copies while retaining exact source/model bytes."""
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from qa_storage import Storage
from qa_preserved import Vault


class ExtendedStorage(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.home=Path(self.temp.name).resolve();self.root=self.home/'Documents/repo';self.root.mkdir(parents=True)
        self.state=self.home/'registry'

    def manager(self,**options):
        m=Storage(self.root,home=self.home,state=self.state,min_free=0,**options)
        self.addCleanup(m.close);return m

    def put(self,path,data=b'payload'*2000):
        path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data);return path

    def profile(self,name='oasc-gen2recomp-qa-full109-20261025000000-firered'):
        return self.home/'Library/Application Support/LOVE'/name

    def runpath(self,name='oasc-gen2recomp-qa-full109-20261025000000-firered'):
        return self.root/'.local/qa/gen2-edition-mod'/name

    def show(self,proof,path):
        return subprocess.check_output(['git','--git-dir='+proof['git'],'show',proof['commit']+':snapshot/'+path])

    def test_ula_only_removes_compiled_cache(self):
        m=self.manager(ula_limit=0)
        profile=self.home/'Library/Application Support/LOVE/ula-gen2-native-qa'
        compiled=m.ula(profile/'modstorage/german_rom_source/compiled')
        old=self.put(compiled/'key/payload.bin')
        protected=[self.put(profile/name) for name in ['red/save.lua','options.lua','mods/german_rom_source/main.lua','mods/german_rom_source/baseroms/rom.gbc','modstorage/german_rom_source/preferences.bin']]
        m.close();self.assertFalse(old.exists());self.assertTrue(all(p.exists() for p in protected))

    def test_ula_rejects_player_profile_and_symlink(self):
        m=self.manager()
        with self.assertRaises(ValueError):m.ula(self.home/'Library/Application Support/LOVE/player/modstorage/german_rom_source/compiled')
        source=self.put(self.home/'original/source.lua')
        target=self.home/'Library/Application Support/LOVE/ula-test-qa/modstorage/german_rom_source/compiled'
        target.parent.mkdir(parents=True);target.symlink_to(source.parent,target_is_directory=True)
        with self.assertRaises(ValueError):m.ula(target)
        self.assertTrue(source.exists())

    def test_ula_adopts_legacy_keys_before_starting_a_child(self):
        path=self.home/'Library/Application Support/LOVE/ula-test-qa/modstorage/german_rom_source/compiled'
        old=self.put(path/'legacy/assets/1.bin')
        m=self.manager(ula_limit=0);m.ula(path)
        self.assertFalse(old.exists())

    def test_live_ula_lease_blocks_other_collectors(self):
        first=self.manager(ula_limit=0)
        target=first.ula(self.home/'Library/Application Support/LOVE/ula-test-qa/modstorage/german_rom_source/compiled')
        file=self.put(target/'key/file.bin');other=self.manager(ula_limit=0)
        other.sweep();self.assertTrue(file.exists());first.close();self.assertFalse(file.exists())

    def test_installation_removed_after_source_and_models_are_preserved(self):
        m=self.manager(import_limit=0)
        profile=m.destination(self.profile());mod=profile/'mods/ORIGAMI_ASCENDANT_GEN2_PREP'
        self.put(mod/'manifest.json',b'{"id":"ORIGAMI_ASCENDANT_GEN2_PREP"}')
        self.put(mod/'main.lua',b'return "source"');self.put(mod/'models/one.bin',b'model\x00bytes')
        original=self.put(self.home/'authored/source.lua',b'original')
        (mod/'outside').symlink_to(original)
        save=self.put(profile/'firered/save/save.lua');custom=self.put(profile/'mods/custom/source.lua')
        m.close();self.assertFalse(mod.exists());self.assertTrue(save.exists() and custom.exists() and original.exists())
        proof=json.loads((profile/'qa-preserved-sources.json').read_text())['mods/ORIGAMI_ASCENDANT_GEN2_PREP']
        self.assertEqual(self.show(proof,'main.lua'),b'return "source"')
        self.assertEqual(self.show(proof,'models/one.bin'),b'model\x00bytes')
        self.assertEqual(self.show(proof,'outside'),os.fsencode(original))
        subprocess.run(['git','--git-dir='+proof['git'],'fsck','--full'],check=True,capture_output=True)

    def test_frozen_copy_retains_evidence_and_exact_recoverable_sources(self):
        m=self.manager(copy_limit=0)
        run=m.cache(self.runpath())
        self.put(run/'engine/source.lua',b'engine source');self.put(run/'engine/model.png',b'model')
        self.put(run/'input-mod.zip',b'archived input')
        reports=[self.put(run/name) for name in ['driver.lua','verification.json','native.log','view.png','result.json']]
        m.close();self.assertFalse((run/'engine').exists());self.assertFalse((run/'input-mod.zip').exists())
        self.assertTrue(all(p.exists() for p in reports))
        proof=json.loads((run/'qa-preserved-sources.json').read_text())
        self.assertEqual(self.show(proof['engine'],'source.lua'),b'engine source')
        self.assertEqual(self.show(proof['input-mod.zip'],'input-mod.zip'),b'archived input')

    def test_profile_input_lease_protects_the_corresponding_engine_copy(self):
        owner=self.manager(copy_limit=10**8);run=owner.cache(self.runpath())
        source=self.put(run/'engine/source.lua');owner.close()
        reader=self.manager(copy_limit=10**8);reader.source(self.profile())
        cleaner=self.manager(copy_limit=0);cleaner.sweep();self.assertTrue(source.exists())
        reader.close();cleaner.sweep();self.assertFalse(source.exists())

    def test_legacy_group_lease_protects_copies_from_older_runners(self):
        owner=self.manager(copy_limit=10**8);run=owner.cache(self.runpath())
        source=self.put(run/'engine/source.lua');owner.close()
        with (self.state/(owner._key(run.parent)+'.lock')).open('a+') as lock:
            fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            self.manager(copy_limit=0).sweep();self.assertTrue(source.exists())
        self.manager(copy_limit=0).sweep();self.assertFalse(source.exists())

    def test_preservation_failure_keeps_runtime_copies(self):
        m=self.manager(copy_limit=0);run=m.cache(self.runpath());source=self.put(run/'engine/source.lua')
        with patch('qa_preserved.Vault.capture',side_effect=OSError('simulated archive failure')):m.close()
        self.assertTrue(source.exists())

    def test_source_checkouts_and_keep_markers_are_not_disposable(self):
        m=self.manager(copy_limit=0)
        run=m.cache(self.runpath());source=self.put(run/'engine/source.lua')
        (run/'.qa-keep').touch();m.close();self.assertTrue(source.exists())
        other=self.manager(copy_limit=0);other.cache(self.root/'.local/qa/reference');original=self.put(self.root/'.local/qa/reference/engine/main.lua')
        other.close();self.assertTrue(original.exists())

    def test_geometry_collection_does_not_treat_engine_models_as_payloads(self):
        m=self.manager(geometry_limit=0)
        path=m.cache(self.root/'.local/qa/reference')
        model=self.put(path/'engine/models'/('a'*64+'.data'))
        generated=self.put(path/'bake'/('b'*64+'.data'))
        m.close();self.assertTrue(model.exists());self.assertFalse(generated.exists())

    def test_vault_deduplicates_without_mutable_source_aliases(self):
        a=self.put(self.home/'a/model.bin',b'unique-model');b=self.put(self.home/'b/model.bin',b'unique-model')
        with Vault(self.home) as vault:
            first=vault.capture(a.parent);second=vault.capture(b.parent)
            oid1=vault.git('rev-parse',first['commit']+':snapshot/model.bin')
            oid2=vault.git('rev-parse',second['commit']+':snapshot/model.bin')
            self.assertEqual(oid1,oid2)
        a.write_bytes(b'changed');self.assertEqual(self.show(first,'model.bin'),b'unique-model');self.assertEqual(b.read_bytes(),b'unique-model')

    def test_native_hashing_preserves_raw_bytes_names_and_executable_mode(self):
        folder=self.home/'raw'
        self.put(folder/'.gitattributes',b'* text eol=lf\n')
        name='Grüße "quoted"\nmodel.bin'
        self.put(folder/name,b'raw\r\nbytes\x00')
        executable=self.put(folder/'run.sh',b'#!/bin/sh\n');executable.chmod(0o755)
        with Vault(self.home) as vault:proof=vault.capture(folder)
        self.assertEqual(self.show(proof,name),b'raw\r\nbytes\x00')
        mode=subprocess.check_output(['git','--git-dir='+proof['git'],'ls-tree',proof['commit'],'snapshot/run.sh'])
        self.assertTrue(mode.startswith(b'100755 '))


if __name__=='__main__':unittest.main()
