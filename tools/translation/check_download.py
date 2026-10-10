"""Exercise streamed download events without a network request or model."""
import importlib.util
import io
import tempfile
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("offline", Path(__file__).with_name("offline_translate.py"))
offline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(offline)
payload = b"model" * 200000
for size in (len(payload), 0):
    response = io.BytesIO(payload)
    response.headers = {"Content-Length": str(size)}
    events = []
    Path("tmp").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(dir="tmp") as folder:
        dest = Path(folder) / "model.bin"
        with patch.object(offline.urllib.request, "urlopen", return_value=response), patch.object(offline, "emit", side_effect=lambda **event: events.append(event)):
            offline.fetch("https://example.test/model", dest)
        assert dest.read_bytes() == payload
        assert events[0]["done"] == 0
        assert events[-1]["done"] == len(payload)
        assert all(event["total"] == size and event["unit"] == "bytes" for event in events)
        assert not dest.with_suffix(".bin.part").exists()
print("PASS streamed download progress with known and unknown lengths")

# GPU detection/initialization failures must preserve a usable CPU translator.
class Runtime:
    def __init__(self, fail=False): self.devices=[]; self.fail=fail
    def get_cuda_device_count(self): return 1
    def Translator(self, path, **kwargs):
        self.devices.append(kwargs["device"])
        if kwargs["device"]=="cuda" and self.fail: raise RuntimeError("missing CUDA library")
        return object()
with patch.object(offline,"prepare_cuda"), patch.object(offline,"emit"):
    runtime=Runtime()
    _,device=offline.make_engine(runtime,Path("model"),{"hardware":"auto"})
    assert device=="cuda" and runtime.devices==["cuda"]
    runtime=Runtime(fail=True)
    _,device=offline.make_engine(runtime,Path("model"),{"hardware":"auto"})
    assert device=="cpu" and runtime.devices==["cuda","cpu"]
    runtime=Runtime()
    _,device=offline.make_engine(runtime,Path("model"),{"hardware":"cpu"})
    assert device=="cpu" and runtime.devices==["cpu"]
print("PASS GPU selection, CPU override and missing-runtime fallback")
if offline.os.name=="nt":
    import hashlib, json, zipfile
    archive=io.BytesIO()
    with zipfile.ZipFile(archive,"w") as package:
        for name in ["cublasLt64_12.dll","cublas64_12.dll"]:package.writestr("nvidia/cublas/bin/"+name,b"test library")
        package.writestr("nvidia/cublas/License.txt",b"test license")
    payload=archive.getvalue()
    metadata={"urls":[{"filename":"cuda-win_amd64.whl","url":"https://example.test/cuda","digests":{"sha256":hashlib.sha256(payload).hexdigest()}}]}
    def download(url,dest,**kwargs):
        dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(payload)
    with tempfile.TemporaryDirectory(dir="tmp") as folder:
        with patch.object(offline.urllib.request,"urlopen",side_effect=lambda *a,**k:io.BytesIO(json.dumps(metadata).encode())), patch.object(offline,"fetch",side_effect=download), patch.object(offline.ctypes,"WinDLL",return_value=object()), patch.dict(offline.os.environ), patch.object(offline,"emit"):
            offline.prepare_cuda({"hardware":"gpu","models":folder})
        root=Path(folder)/"cuda"
        assert (root/"cublas64_12.dll").read_bytes()==b"test library"
        assert (root/"NVIDIA-LICENSE.txt").is_file() and not (root/"cublas.whl").exists()
        (root/"cublas64_12.dll").unlink()
        metadata["urls"][0]["digests"]["sha256"]="invalid"
        with patch.object(offline.urllib.request,"urlopen",side_effect=lambda *a,**k:io.BytesIO(json.dumps(metadata).encode())), patch.object(offline,"fetch",side_effect=download), patch.object(offline,"emit"):
            try:offline.prepare_cuda({"hardware":"gpu","models":folder})
            except ValueError:pass
            else:raise AssertionError("Bad GPU checksum was accepted")
    print("PASS GPU runtime download verification, extraction and license retention")
