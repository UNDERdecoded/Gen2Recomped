"""Explicit disposable copy layouts, with durable source/model preservation."""
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile
import time

PROTECTED_DIRS = {'.git', 'baseroms', 'save', 'saves', 'savegames', 'savestates', 'preferences'}
PROTECTED_EXTS = {'.sav', '.srm', '.state', '.gb', '.gbc', '.gba', '.nds', '.rom'}
MODS = {'german_rom_source', 'ORIGAMI_ASCENDANT', 'ORIGAMI_ASCENDANT_GEN2_PREP', 'kanto_ascendant', 'VOXEL_ASCENDANT'}
BASELINES = {'angles-baseline', 'camera-baseline', 'entry-baseline', 'main-baseline', 'perf-baseline', 'rs-baseline', 'wide-baseline', 'baseline'}
RUN_GROUPS = {'black-frame-investigation', 'emerald-metal-cpu', 'firered-frame-jitter', 'firered-gl-cpu', 'fr-gl-copy', 'fr-gl-pipeline', 'fr-gl-spikes', 'palette-gpu', 'palette-rebake-performance', 'window-frame-performance', 'vasc2-check'}
EXPLICIT_PROFILES = {'german-rom-mod-comparison', 'ula-language-root-preflight', 'ula-live-switch-ui-check', *(f'ula-live-switch-suite-{n}' for n in range(3))}
NATIVE_QA = re.compile(r'gen2recomp-qa-(?:firered|leafgreen|ruby|sapphire|emerald)-[0-9]+\Z')


def qa_profile(name):
    return (name in EXPLICIT_PROFILES or NATIVE_QA.fullmatch(name) is not None or
            (re.fullmatch(r'(?:oasc|ula|german-rom-mod|uni-language)-[A-Za-z0-9_-]+', name) is not None
             and re.search(r'(?:^|-)(?:qa|test)(?:-|$)', name) is not None))


def identify(path, root, home):
    """Return the exact disposable root, including for a child/source path."""
    path, root, home = map(Path, (path, root, home))
    love = home/'Library/Application Support/LOVE'
    if path.is_relative_to(love):
        parts = path.relative_to(love).parts
        if len(parts) >= 3 and qa_profile(parts[0]) and parts[1] == 'mods' and parts[2] in MODS:
            # Modern OASC installations are already owned by the import resource.
            if parts[0].startswith('oasc-') and re.search(r'(?:^|-)qa(?:-|$)', parts[0]) and parts[2] in {'ORIGAMI_ASCENDANT', 'ORIGAMI_ASCENDANT_GEN2_PREP'}:
                return None
            return love/parts[0]/'mods'/parts[2]
    local = root/'.local'
    if path.is_relative_to(local):
        parts = path.relative_to(local).parts
        if parts and parts[0] in BASELINES | RUN_GROUPS:
            return local/parts[0]
        if len(parts) >= 2 and parts[0] == 'engine-parity':
            return local/'engine-parity'/parts[1]
        if len(parts) >= 3 and parts[0] == 'qa' and NATIVE_QA.fullmatch(parts[1]) and parts[2] == 'engine':
            return local/'qa'/parts[1]/'engine'
        if len(parts) >= 3 and parts[0] == 'qa' and parts[2] in {'reference', 'baseline', 'candidate', 'source', 'unit', 'identity-unit-host'}:
            return local/'qa'/parts[1]/parts[2]
    if path.parent == root/'dist' and re.fullmatch(r'Origami-Ascendant-Gen2Recomped-[A-Za-z0-9-]+-candidate\.zip', path.name):
        return path
    return None


def candidates(root, home):
    local = root/'.local'
    for name in sorted(BASELINES | RUN_GROUPS):
        yield local/name
    if (local/'engine-parity').is_dir():
        yield from (local/'engine-parity').iterdir()
    for run in (local/'qa').glob('*'):
        if not run.is_dir() or run.is_symlink():continue
        if NATIVE_QA.fullmatch(run.name):yield run/'engine'
        for name in ('reference', 'baseline', 'candidate', 'source', 'unit', 'identity-unit-host'):
            yield run/name
    yield from (root/'dist').glob('Origami-Ascendant-Gen2Recomped-*-candidate.zip')
    love = home/'Library/Application Support/LOVE'
    for profile in love.glob('*'):
        if not qa_profile(profile.name):continue
        for name in MODS:
            mod = profile/'mods'/name
            try:manifest = json.loads((mod/'manifest.json').read_text())
            except (OSError, ValueError):continue
            if manifest.get('id') == name:yield mod


def dependencies(path, root, home):
    local = root/'.local/qa'
    if path.is_relative_to(local):
        parts = path.relative_to(local).parts
        yield local/parts[0]
        if NATIVE_QA.fullmatch(parts[0]):
            yield home/'Library/Application Support/LOVE'/parts[0]
    love = home/'Library/Application Support/LOVE'
    if path.is_relative_to(love):
        profile = love/path.relative_to(love).parts[0]
        yield profile
        yield profile/'modstorage/german_rom_source/compiled'


def kept(path):
    if path.is_symlink() or path.resolve() != path:return True
    if path.name in MODS and path.parent.name=='mods':
        try:
            if json.loads((path/'manifest.json').read_text()).get('id')!=path.name:return True
        except FileNotFoundError:pass
        except (OSError,ValueError):return True
    if path.is_file():return (path.parent/'.qa-keep').exists()
    for folder, dirs, names in os.walk(path, followlinks=False):
        folder = Path(folder)
        if '.git' in dirs or '.git' in names:return True
        # Keep markers protect their subtree; an outer marker protects all.
        dirs[:] = [d for d in dirs if d not in PROTECTED_DIRS and not (folder/d).is_symlink()]
    return (path/'.qa-keep').exists() or (path.parent/'.qa-keep').exists()


def files(path):
    if path.is_file() and not path.is_symlink():
        yield path, path.stat();return
    if not path.is_dir() or path.is_symlink():return
    for folder, dirs, names in os.walk(path, followlinks=False):
        folder = Path(folder)
        if (folder/'.qa-keep').exists():dirs[:] = [];continue
        for name in list(dirs):
            item = folder/name
            if name in PROTECTED_DIRS:dirs.remove(name)
            elif item.is_symlink():
                dirs.remove(name);yield item, item.lstat()
        for name in names:
            if name == 'qa-preserved-sources.json' or Path(name).suffix.lower() in PROTECTED_EXTS:continue
            item = folder/name;info = item.lstat()
            if stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode):yield item, info


class LiveUse:
    """Fallback for older launchers that have not acquired shared QA leases."""
    def __init__(self):self.loaded = False;self.loaded_at = 0

    def busy(self, path):
        if not self.loaded or time.monotonic()-self.loaded_at>5:self._load()
        if self.failed:return True
        text = str(path)
        if any(text in cmd for cmd in self.commands):return True
        if any(name == text or name.startswith(text+'/') for name in self.opened):return True
        love = '/Library/Application Support/LOVE/'
        if love in text:
            profile = text.split(love, 1)[1].split('/', 1)[0]
            if profile in self.identities:return True
        return False

    def _load(self):
        self.loaded = True;self.loaded_at = time.monotonic();self.commands = [];self.opened = [];self.identities = set()
        try:
            rows = subprocess.check_output(['ps', '-Ao', 'pid=,args='], text=True).splitlines()
            for row in rows:
                pid, _, cmd = row.strip().partition(' ')
                if not pid.isdigit() or int(pid) == os.getpid():continue
                self.commands.append(cmd)
                if re.search(r'(?:MacOS/[^ /]+|/love)(?: |$)', cmd):
                    result = subprocess.run(['ps', 'eww', '-p', pid, '-o', 'command='], text=True, capture_output=True)
                    if result.returncode:continue  # Process may have just exited.
                    env = result.stdout
                    for key in ('POKEPORT_IDENTITY', 'OA_QA_IDENTITY', 'OASC_IDENTITY', 'LOVE_IDENTITY'):
                        match = re.search(r'(?:^|\s)'+key+r'=([^\s]+)', env)
                        if match:self.identities.add(match.group(1))
            result = subprocess.run(['lsof', '-nP', '-Fpn'], text=True, capture_output=True, timeout=30)
            pid = None
            for row in result.stdout.splitlines():
                if row.startswith('p'):pid = row[1:]
                elif row.startswith('n/') and pid != str(os.getpid()):self.opened.append(row[1:])
            if result.returncode not in (0, 1):raise RuntimeError('Cannot inspect live QA files')
        except (OSError, subprocess.SubprocessError, RuntimeError):
            # Fail closed if process inspection is unavailable.
            self.commands = ['/'];self.opened = ['/'];self.failed = True
        else:self.failed = False


def preserve(path, home, *, active=lambda path: False):
    """Archive independent bytes, then unlink only the exact files captured."""
    from qa_preserved import Vault
    if kept(path):raise ValueError('Retain source checkout, symlink or keep marker')
    plan = list(files(path))
    if not plan:return
    root_info = path.lstat()
    with tempfile.TemporaryDirectory(prefix='qa-source-preserve-') as tmp:
        source = path
        if path.is_dir():
            source = Path(tmp)/'snapshot';source.mkdir()
            for item, info in plan:
                dest = source/item.relative_to(path);dest.parent.mkdir(parents=True, exist_ok=True)
                if stat.S_ISLNK(info.st_mode):dest.symlink_to(os.readlink(item))
                else:os.link(item, dest)
        with Vault(home) as vault:proof = vault.capture(source)
        if active(path):raise RuntimeError('Copy became active during preservation')
        if kept(path) or path.lstat().st_ino != root_info.st_ino:raise RuntimeError('Copy changed during preservation')
        for item, info in plan:
            current = item.lstat()
            if (current.st_ino, current.st_size, current.st_mtime_ns) != (info.st_ino, info.st_size, info.st_mtime_ns):
                raise RuntimeError('Source changed during preservation: '+str(item))
            if item.parent.resolve() != item.parent:raise RuntimeError('Copy ancestor became a symlink')
        receipt = path.parent/'qa-preserved-sources.json'
        previous = json.loads(receipt.read_text()) if receipt.exists() else {}
        previous[path.name] = proof
        temporary = receipt.with_suffix('.'+str(os.getpid())+'.tmp')
        temporary.write_text(json.dumps(previous, indent=2));temporary.replace(receipt)
        for item, info in plan:
            parent_info = item.parent.stat()
            if parent_info.st_uid != os.getuid():raise PermissionError('Foreign-owned copy')
            item.parent.chmod(stat.S_IMODE(parent_info.st_mode)|0o700)
            item.unlink()
        if path.is_dir():
            # Preserve baseroms/saves/keep subtrees and any newly created files.
            parents = {parent for item, _ in plan for parent in item.parents
                       if parent == path or parent.is_relative_to(path)}
            for folder in sorted(parents, key=lambda p: len(p.parts), reverse=True):
                if folder.is_dir() and not any(folder.iterdir()) and folder.name not in PROTECTED_DIRS:folder.rmdir()
