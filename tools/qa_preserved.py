"""Keep exact source/model bytes once in a local Git vault before pruning copies."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import time


class Vault:
    def __init__(self, home):
        self.path = Path(home) / '.local/share/origami-qa-preserved.git'
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.lock = self.path.with_suffix('.lock').open('a+')
        fcntl.flock(self.lock, fcntl.LOCK_EX)
        if not self.path.exists():
            subprocess.run(['git', 'init', '--bare', '--object-format=sha1', '--quiet', str(self.path)], check=True)
            self.git('symbolic-ref','HEAD','refs/heads/retained')
        self.known = set(self.git('cat-file', '--batch-all-objects', '--batch-check=%(objectname)').decode().splitlines())
        self.marks = {}
        self.serial = 0
        self.errors = tempfile.TemporaryFile()
        self.process = subprocess.Popen(['git', '--git-dir='+str(self.path), 'fast-import', '--quiet'],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.errors)
        tip = subprocess.run(['git', '--git-dir='+str(self.path), 'rev-parse', '--verify', 'refs/heads/retained'],
                             capture_output=True, text=True)
        self.tip = tip.stdout.strip() if tip.returncode == 0 else None

    def git(self, *args):
        return subprocess.check_output(['git', '--git-dir='+str(self.path), *args])

    def send(self, data):
        self.process.stdin.write(data.encode() if isinstance(data, str) else data)

    def mark(self):
        self.serial += 1
        return ':'+str(self.serial)

    def capture(self, source):
        source = Path(source)
        records = []
        files = 0
        logical = 0
        candidates = [source] if source.is_file() or source.is_symlink() else None
        if candidates is None:
            candidates = []
            for folder, dirs, names in os.walk(source, followlinks=False):
                # Save symlink text, never the linked source tree.
                for name in list(dirs):
                    item = Path(folder)/name
                    if item.is_symlink():
                        candidates.append(item);dirs.remove(name)
                candidates.extend(Path(folder)/name for name in names)
        # Hash ordinary files in Git's native batch reader. Large frozen
        # engines contain thousands of tiny source files; opening every one
        # through Python makes preserving each test copy needlessly slow.
        infos = {path: path.lstat() for path in candidates}
        regular = [path for path in candidates if stat.S_ISREG(infos[path].st_mode)]
        digests = {}
        if regular:
            paths = ''.join(json.dumps(str(path), ensure_ascii=False)+'\n' for path in regular)
            output = subprocess.check_output(['git', '--git-dir='+str(self.path),
                'hash-object', '--no-filters', '--stdin-paths'], input=paths.encode())
            hashes = output.decode().splitlines()
            if len(hashes) != len(regular):
                raise RuntimeError('Incomplete source hashing')
            digests = dict(zip(regular, hashes))
        for path in sorted(candidates):
            info = infos[path]
            if stat.S_ISLNK(info.st_mode):
                data = os.fsencode(os.readlink(path));mode = '120000'
                digest = hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
                size = len(data)
            elif stat.S_ISREG(info.st_mode):
                size = info.st_size
                digest = digests[path];mode = '100755' if info.st_mode & 0o111 else '100644'
                data = None
            else:
                raise ValueError('Retain unsupported special source: '+str(path))
            reference = self.marks.get(digest) or digest
            if digest not in self.known:
                reference = self.mark();self.marks[digest] = reference;self.known.add(digest)
                self.send('blob\nmark '+reference+'\ndata '+str(size)+'\n')
                if data is not None:self.send(data)
                else:
                    with path.open('rb') as stream:
                        for chunk in iter(lambda: stream.read(1024*1024), b''):self.send(chunk)
                self.send('\n')
            current = path.lstat()
            if (current.st_ino,current.st_size,current.st_mtime_ns)!=(info.st_ino,info.st_size,info.st_mtime_ns):
                raise RuntimeError('Source changed during preservation: '+str(path))
            rel = path.name if source.is_file() else str(path.relative_to(source))
            records.append('M '+mode+' '+reference+' '+json.dumps('snapshot/'+rel,ensure_ascii=False)+'\n')
            files += 1;logical += size
        commit = self.mark()
        message = 'Preserved QA copy: '+str(source)+'\n'
        self.send('commit refs/heads/retained\nmark '+commit+'\ncommitter QA Storage <qa-storage@localhost> '+str(int(time.time()))+' +0000\ndata '+str(len(message.encode()))+'\n'+message)
        if self.tip:self.send('from '+self.tip+'\n')
        self.send('deleteall\n'+''.join(records)+'\ncheckpoint\nget-mark '+commit+'\n')
        self.process.stdin.flush()
        oid = self.process.stdout.readline().decode().strip()
        if len(oid) != 40 or self.git('cat-file','-t',oid).strip()!=b'commit':
            raise RuntimeError('Source preservation did not commit: '+oid)
        self.tip = oid
        return dict(git=str(self.path), commit=oid, tree='snapshot', files=files, logical_bytes=logical)

    def close(self):
        try:
            self.process.stdin.close()
            if self.process.wait() != 0:
                self.errors.seek(0)
                raise RuntimeError('Preservation failed: '+self.errors.read(2000).decode(errors='replace'))
            # Checkpoints make each receipt durable. Consolidate their packs
            # periodically so ZIP/source versions can also share Git deltas.
            counts = dict(line.split(': ', 1) for line in
                          self.git('count-objects', '-v').decode().splitlines())
            # A few large source ZIPs can fill gigabytes long before Git's
            # default loose-object COUNT threshold triggers automatic GC.
            if int(counts.get('packs', 0)) > 40:
                subprocess.run(['git','--git-dir='+str(self.path),'-c','gc.autoDetach=false','gc'],check=True)
            elif int(counts.get('size', 0)) > 256*1024:
                # Pack recent versions without recompressing all historical
                # sources on every test. The pack-count branch merges later.
                subprocess.run(['git','--git-dir='+str(self.path),'repack','-d'],check=True)
        finally:
            self.process.stdout.close();self.errors.close();self.lock.close()

    def __enter__(self):return self
    def __exit__(self, *args):self.close()
