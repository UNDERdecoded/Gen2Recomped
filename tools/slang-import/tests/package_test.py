import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import hashlib
import tempfile
import unittest

spec=importlib.util.spec_from_file_location('shader_package',Path(__file__).resolve().parents[1]/'package.py')
pkg=importlib.util.module_from_spec(spec)
spec.loader.exec_module(pkg)


def binary(system, arch):
    if system=='linux':
        data=bytearray(64);data[:6]=b'\x7fELF\x02\x01';struct.pack_into('<H',data,18,62 if arch=='x86_64' else 183);return data
    if system=='windows':
        data=bytearray(128);data[:2]=b'MZ';struct.pack_into('<I',data,60,64);data[64:68]=b'PE\0\0';struct.pack_into('<H',data,68,0x8664 if arch=='x86_64' else 0xAA64);return data
    data=bytearray(32);data[:4]=b'\xcf\xfa\xed\xfe';struct.pack_into('<I',data,4,0x01000007 if arch=='x86_64' else 0x0100000C);return data


class Packaging(unittest.TestCase):
    def setUp(self):
        self.scratch=tempfile.TemporaryDirectory()
        self.root=Path(self.scratch.name)
    def tearDown(self):
        self.scratch.cleanup()
    def bundle(self, system='linux', arch='x86_64'):
        root=self.root/'bundle';root.mkdir()
        (root/(pkg.NAME+('.exe' if system=='windows' else ''))).write_bytes(binary(system,arch))
        (root/'notices').mkdir();(root/'notices/LICENSE').write_text('license notice')
        (root/'DEPENDENCIES.json').write_text('[]')
        self.receipt(root,system,[arch]);return root
    def receipt(self,root,system,arches):
        files={p.relative_to(root).as_posix():pkg.digest(p) for p in root.rglob('*') if p.is_file() and p.name!='manifest.json'}
        (root/'manifest.json').write_text(json.dumps({'format':1,'tool':pkg.NAME,'platform':system,'architectures':sorted(arches),'files':files}))
    def test_architectures_are_detected_from_bytes_and_mismatch_is_refused(self):
        for system in ['linux','macos','windows']:
            for arch in ['x86_64','aarch64']:
                with self.subTest(system=system,arch=arch):
                    root=self.bundle(system,arch);pkg.verify(root,system,arch)
                    with self.assertRaises(ValueError): pkg.verify(root,system,'aarch64' if arch=='x86_64' else 'x86_64')
                    if system!='macos':
                        with self.assertRaises(ValueError): pkg.verify(root,'macos','universal')
                    import shutil;shutil.rmtree(root)
    def test_universal_requires_both_slices(self):
        root=self.bundle('macos','aarch64')
        with self.assertRaises(ValueError): pkg.verify(root,'macos','universal')
        data=bytearray(112);data[:4]=b'\xca\xfe\xba\xbe';struct.pack_into('>I',data,4,2)
        for i,arch in enumerate(['x86_64','aarch64']):
            offset=48+i*32;struct.pack_into('>IIIII',data,8+i*20,0x01000007 if i==0 else 0x0100000C,0,offset,32,0);data[offset:offset+32]=binary('macos',arch)
        (root/pkg.NAME).write_bytes(data);self.receipt(root,'macos',['aarch64','x86_64']);pkg.verify(root,'macos','universal')
    def test_changed_incomplete_unlisted_and_symlink_bundles_are_refused(self):
        root=self.bundle();exe=root/pkg.NAME;original=exe.read_bytes();exe.write_bytes(original+b'changed')
        with self.assertRaises(ValueError): pkg.verify(root,'linux','x86_64')
        exe.write_bytes(original);extra=root/'private.rom';extra.write_text('must never ship')
        with self.assertRaises(ValueError): pkg.verify(root,'linux','x86_64')
        extra.unlink();(root/'DEPENDENCIES.json').unlink()
        with self.assertRaises(ValueError): pkg.verify(root,'linux','x86_64')
        (root/'DEPENDENCIES.json').write_text('[]');link=root/'link'
        try: link.symlink_to(exe)
        except OSError: return
        with self.assertRaises(ValueError): pkg.verify(root,'linux','x86_64')
    def test_install_is_complete_and_never_replaces_destination(self):
        root=self.bundle();dest=self.root/'app/shader-tools';self.assertTrue(pkg.install(root,dest,'linux','x86_64'))
        pkg.verify(dest,'linux','x86_64');before=(dest/pkg.NAME).read_bytes()
        with self.assertRaises(ValueError): pkg.install(root,dest,'linux','x86_64')
        self.assertEqual((dest/pkg.NAME).read_bytes(),before)
    def test_pinned_notices_survive_windows_git_checkout(self):
        # Exercise Git's real checkout filters, rather than assuming that an
        # LF file read on this host has Windows' worktree representation.
        provenance=json.loads((pkg.TOOL/'licenses/provenance.json').read_text())
        attributes=(pkg.ROOT/'.gitattributes').read_bytes()
        def checkout(name, attrs):
            repo=self.root/name;repo.mkdir()
            subprocess.run(['git','init','-q',str(repo)],check=True)
            files={'.gitattributes':attrs}
            for entry in provenance:
                rel='tools/slang-import/licenses/'+entry['file']
                files[rel]=(pkg.TOOL/'licenses'/entry['file']).read_bytes()
            for rel, data in files.items():
                blob=subprocess.check_output(['git','-C',str(repo),'hash-object','-w','--stdin'],input=data).decode().strip()
                subprocess.run(['git','-C',str(repo),'update-index','--add','--cacheinfo','100644',blob,rel],check=True)
            dest=self.root/(name+'-checkout');dest.mkdir()
            subprocess.run(['git','-C',str(repo),'-c','core.autocrlf=true','-c','core.attributesFile='+str(self.root/'no-global-attributes'),
                'checkout-index','--all','--force','--prefix='+dest.as_posix()+'/'],check=True)
            return [hashlib.sha256((dest/'tools/slang-import/licenses'/e['file']).read_bytes()).hexdigest()for e in provenance]
        expected=[e['sha256']for e in provenance]
        self.assertEqual(checkout('fixed',attributes),expected)
        previous=attributes.replace(b'tools/slang-import/licenses/** -text',b'')
        self.assertNotEqual(checkout('without-pinned-rule',previous),expected)

    def test_optional_missing_bundle_leaves_destination_absent(self):
        dest=self.root/'dest';self.assertFalse(pkg.install(self.root/'absent',dest,'linux','x86_64',True));self.assertFalse(dest.exists())


if __name__=='__main__':
    unittest.main()
