#!/usr/bin/env python3
"""Exercise real LOVE worker HTTP against only a task-owned loopback server."""
import argparse, http.server, os, pathlib, subprocess, threading, time, tempfile, shutil, uuid
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_GET(self):
        path=self.path.split('?')[0]
        if path=='/slow': time.sleep(1.25)
        if path=='/missing': self.send_error(404); return
        body=b'\x00\xff\r\nGET binary' if path=='/binary' else b'slow' if path=='/slow' else b'x'*4096
        self.send_response(200)
        if path!='/chunk': self.send_header('Content-Length',str(len(body)))
        self.end_headers()
        try: self.wfile.write(body)
        except (BrokenPipeError,ConnectionResetError): pass
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--love',required=True);args=p.parse_args()
    root=pathlib.Path(__file__).resolve().parents[1]
    temporary=tempfile.TemporaryDirectory(prefix='gen2recomp-get-check-')
    project=pathlib.Path(temporary.name)
    for name in ('src/net/Fetch.lua','src/net/AsyncGet.lua','src/net/get_worker.lua','src/mods/Net.lua','src/core/HostShell.lua'):
        target=project/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(root/name,target)
    for name in ('main.lua','conf.lua'): shutil.copy2(root/'tools/async-get-check'/name,project/name)
    server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
    thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    try:
        env=os.environ.copy();env.update(GET_TEST_IDENTITY='Gen2Recomp-Async-GET-Check-'+uuid.uuid4().hex,GET_TEST_URL=f'http://127.0.0.1:{server.server_port}')
        result=subprocess.run([str(pathlib.Path(args.love).resolve()),str(project)],env=env,cwd=root,timeout=45)
        raise SystemExit(result.returncode)
    finally: server.shutdown();server.server_close();temporary.cleanup()
