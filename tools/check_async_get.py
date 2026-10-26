#!/usr/bin/env python3
"""Exercise real LOVE worker HTTP against only a task-owned loopback server."""
import argparse, http.server, os, pathlib, subprocess, threading, time, tempfile, shutil, uuid
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_GET(self):
        path=self.path.split('?')[0]
        if path=='/slow': time.sleep(1.25)
        if path=='/missing': self.send_error(404); return
        if path=='/redirect':
            self.send_response(302);self.send_header('Location','/binary');self.end_headers();return
        if path=='/empty':
            self.send_response(204);self.send_header('Content-Length','0');self.end_headers();return
        if path=='/stream':
            self.send_response(200);self.send_header('Content-Length',str(4*65536));self.end_headers()
            try:
                for _ in range(4):self.wfile.write(bytes(range(256))*256);self.wfile.flush();time.sleep(.25)
            except (BrokenPipeError,ConnectionResetError,ConnectionAbortedError):pass
            return
        if path=='/partial':
            self.send_response(200);self.send_header('Content-Length','999');self.end_headers();self.wfile.write(b'short');return
        if path=='/large':
            self.send_response(200);self.send_header('Content-Length',str(17*1024*1024));self.end_headers()
            try:
                for _ in range(272):self.wfile.write(bytes(range(256))*256)
            except (BrokenPipeError,ConnectionResetError,ConnectionAbortedError):pass
            return
        body=b'\x00\xff\r\nGET binary' if path=='/binary' else b'slow' if path=='/slow' else b'x'*4096
        self.send_response(200)
        if path!='/chunk': self.send_header('Content-Length',str(len(body)))
        self.end_headers()
        try: self.wfile.write(body)
        except (BrokenPipeError,ConnectionResetError,ConnectionAbortedError): pass
def main():
    p=argparse.ArgumentParser();p.add_argument('--love',required=True);p.add_argument('--source-root',type=pathlib.Path);args=p.parse_args()
    root=pathlib.Path(__file__).resolve().parents[1]
    source=(args.source_root or root).resolve()
    executable=pathlib.Path(args.love).resolve()
    token=uuid.uuid4().hex
    identity='oasc-native-http-qa-'+token
    temporary=None
    run=subprocess.run
    # Local participating checkouts use the shared storage leases. Standalone
    # upstream/ephemeral CI uses its own isolated temporary project instead.
    if os.name!='nt' and not os.getenv('GITHUB_ACTIONS') and (root/'tools/qa_storage.py').is_file():
        from qa_storage import qa_source,qa_copy,qa_profile,qa_run
        qa_source(root);qa_source(source);qa_source(executable)
        project=qa_copy(root/'.local/qa'/('native-http-test-'+token)/'unit')
        profile=(pathlib.Path.home()/'Library/Application Support/LOVE'/identity if os.uname().sysname=='Darwin'
                 else pathlib.Path.home()/'.local/share/love'/identity)
        qa_profile(profile)
        run=qa_run
        project.mkdir(parents=True)
    else:
        temporary=tempfile.TemporaryDirectory(prefix='gen2recomp-get-check-')
        project=pathlib.Path(temporary.name)
    for name in ('src/net/Fetch.lua','src/net/AsyncGet.lua','src/net/get_worker.lua',
                 'src/net/AsyncDownload.lua','src/net/DownloadTransport.lua','src/net/DownloadPublish.lua','src/net/download_worker.lua',
                 'src/mods/Net.lua','src/core/HostShell.lua'):
        target=project/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source/name,target)
    for name in ('main.lua','conf.lua','download_test_worker.lua'):shutil.copy2(root/'tools/async-get-check'/name,project/name)
    server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
    thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    try:
        env=os.environ.copy();env.update(GET_TEST_IDENTITY=identity,GET_TEST_URL=f'http://127.0.0.1:{server.server_port}')
        result=run([str(executable),str(project)],env=env,cwd=root,timeout=45)
        return result.returncode
    finally:
        server.shutdown();server.server_close()
        if temporary is not None:temporary.cleanup()

if __name__=='__main__':raise SystemExit(main())
