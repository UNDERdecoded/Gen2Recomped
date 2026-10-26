"""Bound disposable QA imports and render caches; never prune saves or evidence.

All participating worktrees share OS file locks. Child processes inherit the
leases, so killing a Python runner cannot expose a still-running LÖVE cache.
Only explicitly registered QA resources are eligible for collection.
"""
import atexit
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import shutil
import stat
import subprocess
import sys
import time
import threading
import qa_legacy_storage as legacy
from contextlib import contextmanager

GIB = 1024 ** 3
EDITIONS = ("firered", "leafgreen", "emerald", "ruby", "sapphire")
QA_EDITIONS = (*EDITIONS, "red", "blue", "yellow", "gold", "silver", "crystal")
PAYLOAD = re.compile(r"[0-9a-f]{64}\.data\Z")
QA_MODS = ('ORIGAMI_ASCENDANT_GEN2_PREP', 'ORIGAMI_ASCENDANT')


class Storage:
    def __init__(self, root, *, home=None, state=None, import_limit=2 * GIB,
                 geometry_limit=4 * GIB, max_age=86400, min_free=20 * GIB,
                 copy_limit=4 * GIB, ula_limit=2 * GIB,
                 clock=time.time):
        self.root = Path(root).resolve()
        self.home_alias = Path(os.path.abspath(home or Path.home()))
        self.home = self.home_alias.resolve()
        self.state = Path(state or self.home / ".cache/origami-qa-storage")
        self.state.mkdir(parents=True, exist_ok=True)
        # Persist only the worktree location, never mark its import templates
        # disposable. Resolve its aliases again on each collection.
        pointer = self.state / (self._key(self.root) + '.inputs')
        temp = pointer.with_suffix('.' + str(os.getpid()) + '.tmp')
        temp.write_text(str(self.root))
        temp.replace(pointer)
        self.limits = {"imports": import_limit, "geometry": geometry_limit,
                       "testcopies": copy_limit, "legacy": copy_limit, "ula": ula_limit}
        self.max_age, self.min_free, self.clock = max_age, min_free, clock
        self.held = {}
        self.lease_info = {}
        self.inherited = set()
        self.inherited_owned = set()
        self.started = False
        self._legacy_live = legacy.LiveUse()
        self.closed = False
        self._adopt_leases()
        # Existing runners use this local alias when --cache-root is omitted.
        # Pin it before the first collection, including when it points to QA imports.
        self.source(self.root / ".local/imports")
        # Legacy launchers often use Path argparse types. Protect their inputs
        # before ANY destination call can trigger the first collection.
        for option in ('--zip','--engine-source','--reference-root','--cache-root','--baseline-root'):
            if option in sys.argv and sys.argv.index(option)+1<len(sys.argv):
                self.source(Path(sys.argv[sys.argv.index(option)+1]))
        if '--cache-identity' in sys.argv and sys.argv.index('--cache-identity')+1<len(sys.argv):
            self.source(self.home/'Library/Application Support/LOVE'/sys.argv[sys.argv.index('--cache-identity')+1])

    def _absolute(self, path):
        path = Path(os.path.abspath(path))
        if path.is_relative_to(self.home_alias):
            path = self.home / path.relative_to(self.home_alias)
        return path

    def _profile(self, path):
        path = self._absolute(path)
        for base in (self.home / "Library/Application Support/LOVE",
                     self.home / "Library/Application Support"):
            if not path.is_relative_to(base):
                continue
            parts = path.relative_to(base).parts
            if not parts or parts[0] == "LOVE":
                continue
            name = parts[0]
            if not legacy.qa_profile(name):
                raise ValueError("Only explicitly named QA identities are disposable")
            profile = base / name
            if profile.resolve() != profile:
                raise ValueError("A QA profile must not alias another directory")
            return profile
        return None

    @staticmethod
    def _key(path):
        return hashlib.sha256(os.fsencode(str(path))).hexdigest()

    def _write(self, key, entry):
        target = self.state / (key + ".json")
        temp = self.state / (key + "." + str(os.getpid()) + ".tmp")
        temp.write_text(json.dumps(entry))
        temp.replace(target)

    def _adopt_leases(self):
        raw = os.environ.get("ORIGAMI_QA_LEASES")
        if not raw:
            return
        data = json.loads(raw)
        if Path(data["state"]).resolve() != self.state.resolve():
            return
        for item in data["leases"]:
            key, fd = item["key"], item["fd"]
            path = Path(item["path"])
            if key != self._key(path):
                raise ValueError("Invalid inherited QA lease")
            expected = (self.state / (key + ".lock")).stat()
            actual = os.fstat(fd)
            if (actual.st_dev, actual.st_ino) != (expected.st_dev, expected.st_ino):
                raise ValueError("Inherited QA descriptor does not name its lock")
            record = self.state / (key + ".json")
            entry = json.loads(record.read_text()) if record.exists() else None
            lock = os.fdopen(os.dup(fd), "a+")
            self.held[key] = (lock, entry, False)
            self.lease_info[key] = (item["kind"], path)
            self.inherited.add(key)
            if item["exclusive"]:
                self.inherited_owned.add(key)

    def _take(self, kind, path, owned):
        key = self._key(path)
        held = self.held.get(key)
        if held:
            if key in self.inherited:
                if owned and key not in self.inherited_owned:
                    raise ValueError("A borrowed input cannot become a child test's output")
                return path
            if owned and not held[2]:
                fcntl.flock(held[0], fcntl.LOCK_EX)
            else:
                return path
        else:
            lock = (self.state / (key + ".lock")).open("a+")
            fcntl.flock(lock, fcntl.LOCK_EX if owned else fcntl.LOCK_SH)
            held = (lock, None, False)
        entry = None
        if owned:
            entry = dict(kind=kind, path=str(path), root=str(self.root),
                         updated=self.clock(), running=True)
            self._write(key, entry)
        self.held[key] = (held[0], entry, owned)
        self.lease_info[key] = (kind, path)
        return path

    def _begin(self):
        if not self.started:
            self.started = True
            self.sweep()
        self.check_space()

    def identity(self, name):
        if not legacy.qa_profile(name):
            raise ValueError("Invalid QA identity")
        self.destination(self.home / "Library/Application Support/LOVE" / name)
        return name

    def destination(self, path):
        original = Path(path)
        profile = self._profile(original)
        if profile is not None:
            self._take("imports", profile, True)
            self._begin()
        return original

    def _qa_group(self, path, root=None):
        root = Path(root or self.root)
        base = root / ".local/qa"
        path = self._absolute(path)
        if not path.is_relative_to(base):
            return None
        parts = path.relative_to(base).parts
        if not parts:
            raise ValueError("Register a QA run, not the entire QA directory")
        group = base / parts[0]
        if group.resolve() != group:
            raise ValueError("A disposable QA output must not alias source data")
        return group

    def cache(self, path):
        original = Path(path)
        group = self._qa_group(original)
        if group is not None:
            self._take("geometry", group, True)
            run = self._copy_run(original)
            if run is not None:
                self._take('testcopies', run, True)
            candidate = legacy.identify(group/'engine', self.root, self.home)
            if candidate is not None:self._take('legacy', candidate, True)
            self._begin()
        return original

    def copy(self, path):
        original = Path(path)
        target = legacy.identify(self._absolute(original), self.root, self.home)
        if target is None or target.resolve() != target:
            raise ValueError('Only known disposable test-copy layouts are accepted')
        self._take('legacy', target, True)
        self._begin()
        return original

    def _copy_run(self, path, root=None):
        root = Path(root or self.root)
        path = self._absolute(path)
        base = root / '.local/qa'
        if not path.is_relative_to(base):return None
        parts = path.relative_to(base).parts
        if len(parts)<2:return None
        if not re.fullmatch(r'gen2-(?:native|edition)-mod(?:-[a-z0-9]+)*',parts[0]):return None
        if not re.fullmatch(r'oasc-gen2recomp-qa-full109-[0-9]+-(?:firered|leafgreen|ruby|sapphire|emerald)',parts[1]):return None
        run = base / parts[0] / parts[1]
        if run.resolve()!=run:raise ValueError('Disposable copies cannot alias source trees')
        return run

    def _ula_path(self, path):
        path = self._absolute(path)
        base = self.home / 'Library/Application Support/LOVE'
        if not path.is_relative_to(base):return None
        parts = path.relative_to(base).parts
        if (len(parts)!=4 or parts[1:]!=('modstorage','german_rom_source','compiled') or
                not parts[0].startswith(('ula-','german-rom-mod-','uni-language-')) or
                not legacy.qa_profile(parts[0])):return None
        if path.resolve()!=path:raise ValueError('ULA cache aliases another directory')
        return path

    def ula(self, path):
        path = Path(path)
        target = self._ula_path(path)
        if target is None:raise ValueError('Only compiled ULA QA caches are disposable')
        first=self._key(target) not in self.held
        self._take('ula',target,True)
        if first:self._trim_ula(target)
        self._begin()
        return path

    def _trim_ula(self, path):
        """Adopt old unledgered compiled keys before launching the first child."""
        if not path.is_dir() or (path/'.qa-keep').exists():return
        rows=[]
        for child in path.iterdir():
            if not re.fullmatch(r'[A-Za-z0-9_-]+',child.name) or not child.is_dir() or child.is_symlink():continue
            size=0;updated=child.stat().st_mtime
            for _,info in self._walk(child):
                size+=info.st_blocks*512;updated=max(updated,info.st_mtime)
            rows.append((updated,str(child),size))
        total=sum(size for _,_,size in rows);changed=False
        for updated,name,size in sorted(rows):
            if total>self.limits['ula'] or self.clock()-updated>=self.max_age:
                self._remove_tree(Path(name));total-=size;changed=True
        if changed:
            for name in ('retention-v1.lua','retention-v1.lua.bin'):
                (path/name).unlink(missing_ok=True)

    def source(self, path):
        original = Path(path).expanduser()
        resolved = original.resolve()
        # Import roots often contain one symlink per edition, rather than
        # being a symlink to a single QA profile themselves.
        candidates = [resolved] + [(original / edition).resolve()
                                   for edition in QA_EDITIONS
                                   if (original / edition).is_symlink()]
        for candidate in candidates:
            try:
                profile = self._profile(candidate)
            except ValueError:
                profile = None  # Player inputs are never registered for deletion.
            if profile is not None:
                self._take("imports", profile, False)
        for root in set(self._registered_roots()):
            target = legacy.identify(resolved, root, self.home)
            if target is not None:self._take('legacy', target, False)
        # Pin a QA path before consulting the registry: a collector in another
        # worktree must not remove its record between discovery and locking.
        for parent in (resolved, *resolved.parents):
            if parent.parent.name == 'qa' and parent.parent.parent.name == '.local':
                self._take("geometry", parent, False)
                break
        for file in self.state.glob("*.json"):
            try:
                entry = json.loads(file.read_text())
            except FileNotFoundError:
                continue  # Another runner just collected this idle entry.
            if entry.get("kind") == "geometry":
                group = Path(entry["path"])
                if resolved.is_relative_to(group):
                    self._take("geometry", group, False)
            elif entry.get('kind')=='testcopies' and profile is not None and Path(entry['path']).name==profile.name:
                self._take('testcopies',Path(entry['path']),False)
        return original

    def check_space(self):
        free = shutil.disk_usage(self.root)[2]
        if free < self.min_free:
            raise RuntimeError("QA stopped before allocating more data: only %.1f GiB free; "
                               "the safety reserve is %.1f GiB" %
                               (free / GIB, self.min_free / GIB))

    def _prepare(self, args, kwargs):
        env = kwargs.get("env")
        if env is None:
            env = os.environ
        identity = env.get("OA_QA_IDENTITY") or env.get("POKEPORT_IDENTITY")
        command = args[0] if args else kwargs.get('args')
        if isinstance(command, (list, tuple)) and '--qa-identity' in command:
            identity = command[command.index('--qa-identity') + 1]
        for key in ('QA_REFERENCE_ROOT','QA_CACHE_ROOT','QA_BASELINE_ROOT','QA_ENGINE_SOURCE','ENGINE_SOURCE','REFERENCE_ROOT','CACHE_ROOT','QA_REPO'):
            if env.get(key):self.source(Path(env[key]))
        if isinstance(command, (list, tuple)):
            for option in ('--zip','--engine-source','--cache-root','--reference-root','--baseline-root'):
                if option in command and command.index(option)+1<len(command):
                    self.source(Path(command[command.index(option)+1]))
        already_held = any(kind == "imports" and path.name == identity
                           for kind, path in self.lease_info.values())
        if identity and legacy.qa_profile(identity) and not already_held:
            self.identity(identity)
        if identity and identity.startswith(('ula-','german-rom-mod-','uni-language-')) and legacy.qa_profile(identity):
            self.ula(self.home/'Library/Application Support/LOVE'/identity/'modstorage/german_rom_source/compiled')
        for key in ("OUT", "QA_OUT", "FINAL_AUDIT_OUT"):
            if env.get(key):
                self.cache(Path(env[key]))
        self._begin()
        # Keep leases alive through shells/exec and if the runner is killed.
        inherited = set(kwargs.pop("pass_fds", ()))
        inherited.update(lock.fileno() for lock, _, _ in self.held.values())
        kwargs["pass_fds"] = tuple(sorted(inherited))
        child_env = dict(env)
        child_env["ORIGAMI_QA_LEASES"] = json.dumps(dict(
            state=str(self.state.resolve()), leases=[dict(
                key=key, fd=lock.fileno(), kind=self.lease_info[key][0],
                path=str(self.lease_info[key][1]),
                exclusive=owned or key in self.inherited_owned)
                for key, (lock, _, owned) in self.held.items()]))
        inherited_group = bool(self.inherited) and env.get("ORIGAMI_QA_JOB") == "isolated"
        own_group = kwargs.setdefault("start_new_session", not inherited_group)
        inherited_group = inherited_group and not own_group
        if own_group or inherited_group:
            child_env["ORIGAMI_QA_JOB"] = "isolated"
        kwargs["env"] = child_env
        return kwargs, own_group, inherited_group

    def popen(self, *args, _watch=True, **kwargs):
        kwargs, own_group, inherited_group = self._prepare(args, kwargs)
        process = subprocess.Popen(*args, **kwargs)
        process._qa_own_group = own_group
        process._qa_inherited_group = inherited_group
        process._qa_disk_full = False
        if _watch and self.min_free:
            def watch():
                while process.poll() is None:
                    try:
                        process.wait(timeout=.5)
                    except subprocess.TimeoutExpired:
                        if shutil.disk_usage(self.root)[2] < self.min_free:
                            process._qa_disk_full = True
                            print("[qa-storage] stopping this QA job: free-disk reserve reached",
                                  file=sys.stderr)
                            try:
                                if own_group or inherited_group:
                                    os.killpg(process.pid if own_group else os.getpgrp(), signal.SIGKILL)
                                else:
                                    process.kill()
                            except ProcessLookupError:
                                pass
                            process.wait()
                            return
            threading.Thread(target=watch, daemon=True, name="qa-storage-guard").start()
            return GuardedProcess(process)
        return process

    def run(self, *args, **kwargs):
        timeout, check = kwargs.pop("timeout", None), kwargs.pop("check", False)
        data, capture = kwargs.pop("input", None), kwargs.pop("capture_output", False)
        if data is not None:
            if kwargs.get("stdin") is not None:
                raise ValueError("stdin and input are mutually exclusive")
            kwargs["stdin"] = subprocess.PIPE
        if capture:
            if kwargs.get("stdout") is not None or kwargs.get("stderr") is not None:
                raise ValueError("capture_output conflicts with stdout/stderr")
            kwargs.update(stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        deadline = time.monotonic() + timeout if timeout is not None else None
        with self.popen(*args, _watch=False, **kwargs) as process:
            own_group = process._qa_own_group
            inherited_group = process._qa_inherited_group
            try:
                while True:
                    remaining = deadline - time.monotonic() if deadline is not None else .5
                    try:
                        stdout, stderr = process.communicate(data, timeout=max(0, min(.5, remaining)))
                        break
                    except subprocess.TimeoutExpired:
                        data = None
                        if deadline is not None and time.monotonic() >= deadline:
                            if own_group:
                                os.killpg(process.pid, signal.SIGKILL)
                            else:
                                process.kill()
                            stdout, stderr = process.communicate()
                            raise subprocess.TimeoutExpired(process.args, timeout,
                                                            output=stdout, stderr=stderr)
                        if shutil.disk_usage(self.root)[2] < self.min_free:
                            # Stop only this newly launched QA job and its children;
                            # never terminate unrelated tests or applications.
                            if own_group or inherited_group:
                                os.killpg(process.pid if own_group else os.getpgrp(), signal.SIGKILL)
                            else:
                                process.kill()
                            process.wait()
                            raise RuntimeError("QA stopped: the free-disk safety reserve was reached")
            except BaseException:
                if process.poll() is None:
                    if own_group:
                        os.killpg(process.pid, signal.SIGKILL)
                    else:
                        process.kill()
                    process.wait()
                raise
            result = subprocess.CompletedProcess(process.args, process.returncode, stdout, stderr)
            if check:
                result.check_returncode()
            return result

    def _valid(self, entry):
        path, root = Path(entry["path"]), Path(entry["root"])
        if not root.is_absolute() or not root.is_relative_to(self.home):
            raise ValueError("QA registry root is outside the user workspace")
        if entry["kind"] == "imports":
            if self._profile(path) != path:
                raise ValueError("Invalid import resource")
        elif entry["kind"] == "geometry":
            if self._qa_group(path, root) != path:
                raise ValueError("Invalid geometry resource")
        elif entry['kind']=='testcopies':
            if self._copy_run(path,root)!=path:raise ValueError('Invalid test-copy resource')
        elif entry['kind']=='ula':
            if self._ula_path(path)!=path:raise ValueError('Invalid ULA cache resource')
        elif entry['kind']=='legacy':
            if legacy.identify(path,root,self.home)!=path or path.resolve()!=path:
                raise ValueError('Invalid legacy test-copy resource')
        else:
            raise ValueError("Unknown QA resource kind")
        return path, root

    @staticmethod
    def _walk(path, name_filter=None, skip_dirs=()):
        if not path.is_dir() or path.is_symlink() or path.resolve() != path:
            return
        for root, dirs, files in os.walk(path, followlinks=False):
            dirs[:] = [d for d in dirs if d not in skip_dirs and not (Path(root) / d).is_symlink()]
            for name in files:
                # Geometry GC owns only hash-named .data payloads. Frozen
                # engines, ZIPs, images and logs need no per-file stat.
                if name_filter is not None and not name_filter(name):
                    continue
                file = Path(root) / name
                info = file.lstat()
                if stat.S_ISREG(info.st_mode):
                    yield file, info

    def _registered_roots(self):
        yield self.root
        for pointer in self.state.glob('*.inputs'):
            root = Path(pointer.read_text())
            if root.is_absolute() and root.is_relative_to(self.home):
                yield root

    def _files(self, entry):
        path, root = self._valid(entry)
        if entry["kind"] == "imports":
            for edition in QA_EDITIONS:
                for relative in ("data/generated", "assets/generated"):
                    yield from self._walk(path / edition / relative)
            for target in self._mod_targets(path):yield from self._walk(target)
            return
        if entry['kind']=='ula':
            yield from self._walk(path);return
        if entry['kind']=='legacy':
            yield from legacy.files(path);return
        if entry['kind']=='testcopies':
            for target in self._copy_targets(path):
                if target.is_dir():yield from self._walk(target)
                else:yield target,target.stat()
            return
        # An installed/published render cache remains game data, even when its
        # bake directory happens to be under .local/qa.
        protected = [installed.resolve()
                     for workspace in {root, *self._registered_roots()}
                     if (installed := workspace / 'gen3/render-cache').exists()]
        if (path / ".qa-keep").exists():
            return
        for file, info in self._walk(path, PAYLOAD.fullmatch,('engine','host','installer','importer','mods','reference','baseline','candidate','source','unit','identity-unit-host')):
            if PAYLOAD.fullmatch(file.name) and not any(
                    file.is_relative_to(installed) for installed in protected):
                yield file, info

    @staticmethod
    def _mod_targets(profile):
        if not profile.name.startswith('oasc-') or not re.search(r'(?:^|-)qa(?:-|$)', profile.name):return
        for name in QA_MODS:
            path=profile/'mods'/name
            if not path.is_dir() or path.is_symlink() or path.resolve()!=path or (path/'.git').exists():continue
            try:manifest=json.loads((path/'manifest.json').read_text())
            except (OSError,ValueError):continue
            if manifest.get('id')==name:yield path

    @staticmethod
    def _copy_targets(run):
        for name in ('engine','input-mod.zip'):
            path=run/name
            if (path.exists() and not path.is_symlink() and path.resolve()==path
                    and not (path.is_dir() and (path/'.git').exists())):yield path

    def _preserve_copies(self, parent, targets):
        from qa_preserved import Vault
        targets=list(targets)
        if not targets:return
        receipt=parent/'qa-preserved-sources.json'
        previous=json.loads(receipt.read_text()) if receipt.exists() else {}
        with Vault(self.home) as vault:
            for target in targets:
                # Persist an independently readable source/model snapshot and
                # its restoration receipt BEFORE removing any runtime copy.
                previous[str(target.relative_to(parent))]=vault.capture(target)
                temp=receipt.with_suffix('.tmp');temp.write_text(json.dumps(previous,indent=2));temp.replace(receipt)
                if target.is_dir():self._remove_tree(target)
                else:target.unlink()

    @contextmanager
    def _dependencies(self, entry):
        handles=[]
        try:
            if entry['kind']=='legacy':
                path,root=self._valid(entry)
                for dependency in legacy.dependencies(path,root,self.home):
                    key=self._key(dependency)
                    if key in self.held:yield False;return
                    lock=(self.state/(key+'.lock')).open('a+');handles.append(lock)
                    try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
                    except BlockingIOError:yield False;return
            if entry['kind']=='testcopies':
                run,root=self._valid(entry)
                paths=[run.parent]
                paths.extend(base/run.name for base in
                    (self.home/'Library/Application Support/LOVE',self.home/'Library/Application Support'))
                for path in paths:
                    key=self._key(path)
                    if key in self.held:yield False;return
                    lock=(self.state/(key+'.lock')).open('a+');handles.append(lock)
                    try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
                    except BlockingIOError:yield False;return
            yield True
        finally:
            for handle in handles:handle.close()

    def _kept(self, entry, protected):
        path,root=self._valid(entry)
        if (path/'.qa-keep').exists():return True
        if entry['kind']=='legacy':
            if legacy.kept(path) or self._legacy_live.busy(path):return True
            if any(self._legacy_live.busy(p) for p in legacy.dependencies(path,root,self.home)):return True
            if entry.get('discovered') and path.exists():
                updated=max([path.stat().st_ctime,*(max(info.st_ctime,info.st_mtime) for _,info in legacy.files(path))])
                if self.clock()-updated<3600:return True
            return False
        if entry['kind']=='imports':return path in protected
        if entry['kind']=='testcopies':
            return ((path.parent/'.qa-keep').exists() or any(p.name==path.name for p in protected))
        return False

    @staticmethod
    def _remove_tree(path):
        if not path.exists() or path.is_symlink() or path.resolve() != path:
            return
        # Some immutable QA fixtures intentionally make generated directories
        # read-only. Change only owned generated-cache directories.
        for root, dirs, _ in os.walk(path, followlinks=False):
            dirs[:] = [d for d in dirs if not (Path(root) / d).is_symlink()]
            info = os.lstat(root)
            if info.st_uid != os.getuid():
                raise PermissionError("Foreign-owned QA cache")
            os.chmod(root, stat.S_IMODE(info.st_mode) | 0o700)
        parent = path.parent
        info = parent.stat()
        if info.st_uid != os.getuid():
            raise PermissionError("Foreign-owned QA cache parent")
        parent.chmod(stat.S_IMODE(info.st_mode) | 0o700)
        shutil.rmtree(path)

    def _remove(self, entry):
        path, _ = self._valid(entry)
        if entry["kind"] == "imports":
            self._preserve_copies(path,self._mod_targets(path))
            for edition in QA_EDITIONS:
                cache = path / edition
                targets = [cache / part for part in ("data/generated", "assets/generated")]
                safe = [p for p in targets if p.is_dir() and not p.is_symlink()
                        and p.resolve() == p]
                if safe:
                    (cache / "rom-cache.complete").unlink(missing_ok=True)
                    for target in safe:
                        self._remove_tree(target)
        elif entry['kind']=='testcopies':
            self._preserve_copies(path,self._copy_targets(path))
        elif entry['kind']=='ula':
            self._remove_tree(path)
        elif entry['kind']=='legacy':
            legacy.preserve(path,self.home,active=self._legacy_live.busy)
        else:
            for file, _ in self._files(entry):
                file.unlink()

    def _discover_legacy(self):
        stamp=self.state/'legacy-discovery.stamp'
        try:
            if self.clock()-float(stamp.read_text())<300:return
        except (OSError,ValueError):pass
        seen=set()
        for root in set(self._registered_roots()):
            try:paths=list(legacy.candidates(root,self.home))
            except OSError:continue
            for path in paths:
                if path in seen:continue
                seen.add(path)
                try:
                    if not path.exists() or path.is_symlink() or legacy.identify(path,root,self.home)!=path:continue
                    key=self._key(path)
                    if key in self.held or (self.state/(key+'.json')).exists():continue
                    with (self.state/(key+'.lock')).open('a+') as lock:
                        try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
                        except BlockingIOError:continue
                        if legacy.kept(path):continue
                        rows=list(legacy.files(path))
                        if not rows:continue
                        # copy2 preserves mtimes; ctime protects freshly copied
                        # or still-changing snapshots from legacy discovery.
                        updated=max(max(info.st_mtime,info.st_ctime) for _,info in rows)
                        updated=max(updated,path.stat().st_ctime)
                        if self.clock()-updated<3600:continue
                        self._write(key,dict(kind='legacy',path=str(path),root=str(root),updated=updated,running=False,discovered=True))
                except OSError:
                    continue  # A builder can rename/delete files while scanned.
        stamp.write_text(str(self.clock()))

    @staticmethod
    def _budget(kind):
        return 'testcopies' if kind=='legacy' else kind

    def sweep(self):
        """Collect idle registered resources under one global, nonblocking GC lock."""
        removed = 0
        with (self.state / "collection.lock").open("a+") as collector:
            try:
                fcntl.flock(collector, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return 0
            self._legacy_live = legacy.LiveUse()
            self._discover_legacy()
            protected_imports = set()
            for root in self._registered_roots():
                imports = root / '.local/imports'
                for alias in (imports, *(imports / edition for edition in QA_EDITIONS)):
                    try:
                        profile = self._profile(alias.resolve())
                    except ValueError:
                        continue
                    if profile is not None:
                        protected_imports.add(profile)
            entries = []
            for file in self.state.glob("*.json"):
                key = file.stem
                if key in self.held:
                    continue
                with (self.state / (key + ".lock")).open("a+") as lock:
                    try:
                        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    except BlockingIOError:
                        continue
                    try:
                        entry = json.loads(file.read_text())
                        if self._kept(entry,protected_imports):
                            continue
                        with self._dependencies(entry) as available:
                            if not available:continue
                            size = sum(info.st_blocks * 512 for _, info in self._files(entry))
                        entries.append((entry["updated"], key, entry, size))
                    except (OSError, ValueError, KeyError) as error:
                        print("[qa-storage] retained invalid/unreadable resource:", error,
                              file=sys.stderr)
            totals = {kind: sum(size for _, _, e, size in entries if self._budget(e["kind"]) == kind)
                      for kind in self.limits if kind != "legacy"}
            for _, key, entry, size in sorted(entries):
                expired = self.clock() - entry["updated"] >= self.max_age
                if not (entry["running"] or expired or totals[self._budget(entry["kind"])] > self.limits[self._budget(entry["kind"])]):
                    continue
                file = self.state / (key + ".json")
                with (self.state / (key + ".lock")).open("a+") as lock:
                    try:
                        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    except BlockingIOError:
                        continue
                    if not file.exists():
                        continue
                    current = json.loads(file.read_text())
                    if current["updated"] != entry["updated"]:
                        continue
                    try:
                        if self._kept(current,protected_imports):continue
                    except OSError:continue
                    with self._dependencies(current) as available:
                        if not available:continue
                        try:self._remove(current)
                        except (OSError,ValueError,RuntimeError,subprocess.SubprocessError) as error:
                            print('[qa-storage] retained copy; preservation/cleanup will retry:',error,file=sys.stderr)
                            continue
                    remaining = sum(info.st_blocks * 512 for _, info in self._files(current))
                    totals[self._budget(entry["kind"])] -= size - remaining
                    removed += size - remaining
                    retained_payload = current['kind'] == 'geometry' and any(
                        PAYLOAD.fullmatch(file.name)
                        for file, _ in self._walk(Path(current['path']), PAYLOAD.fullmatch))
                    if not remaining and not retained_payload:
                        file.unlink()
            if removed:
                print("[qa-storage] reclaimed %.1f MiB of idle test caches" %
                      (removed / 1024 ** 2), file=sys.stderr)
        return removed

    def close(self, *, collect=True):
        if self.closed:
            return
        self.closed = True
        try:
            for key, (lock, entry, owned) in self.held.items():
                if owned:
                    entry.update(updated=self.clock(), running=False)
                    self._write(key, entry)
                # Closing (not LOCK_UN) preserves leases inherited by a child
                # that is still alive if an interrupted runner is unwinding.
                lock.close()
            self.held.clear()
            if collect:self.sweep()
        except OSError as error:
            print("[qa-storage] cleanup will retry at the next test:", error,
                  file=sys.stderr)


class GuardedProcess:
    """Usual Popen operations, with an explicit error after a disk-guard stop."""
    def __init__(self, process):
        self.process = process

    def __getattr__(self, name):
        return getattr(self.process, name)

    def _check(self):
        if self.process._qa_disk_full:
            raise RuntimeError("QA stopped: the free-disk safety reserve was reached")

    def poll(self):
        self._check()
        return self.process.poll()

    def wait(self, *args, **kwargs):
        result = self.process.wait(*args, **kwargs)
        self._check()
        return result

    def communicate(self, *args, **kwargs):
        result = self.process.communicate(*args, **kwargs)
        self._check()
        return result

    def __enter__(self):
        self.process.__enter__()
        return self

    def __exit__(self, *args):
        return self.process.__exit__(*args)


_storage = None


def _manager():
    global _storage
    if _storage is None:
        _storage = Storage(Path(__file__).resolve().parents[1])
        atexit.register(_storage.close)
    return _storage


def qa_destination(path):
    return _manager().destination(path)


def qa_source(path):
    return _manager().source(Path(path))


def qa_source_identity(name):
    if (not re.fullmatch(r"oasc-[A-Za-z0-9_-]+", name) or
            not ("-qa-" in name or name.endswith("-qa"))):
        raise ValueError("Invalid QA cache source identity")
    manager = _manager()
    for base in (manager.home / "Library/Application Support/LOVE",
                 manager.home / "Library/Application Support"):
        manager.source(base / name)
    return name


def qa_cache(path):
    return _manager().cache(path)


def qa_copy(path):
    return _manager().copy(path)


def qa_profile(path):
    return _manager().destination(path)


def qa_ula(path):
    return _manager().ula(path)


def qa_run(*args, **kwargs):
    return _manager().run(*args, **kwargs)


def qa_popen(*args, **kwargs):
    return _manager().popen(*args, **kwargs)


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--sweep', action='store_true', help='Discover and collect idle QA copies without starting a test')
    parser.add_argument('command', nargs=argparse.REMAINDER)
    options = parser.parse_args()
    command = options.command
    if command[:1] == ['--']:
        command = command[1:]
    if not command and not options.sweep:
        parser.error('Provide a QA command after --')
    storage = Storage(options.root)
    try:
        if options.sweep:
            storage.sweep()
        else:
            raise SystemExit(storage.run(command).returncode)
    finally:
        storage.close(collect=not options.sweep)
