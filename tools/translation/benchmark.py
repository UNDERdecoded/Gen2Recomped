"""Benchmark an installed en-es pack; never downloads a model."""
import importlib.util, json, os, shutil, time
from pathlib import Path
import ctranslate2, sentencepiece
spec=importlib.util.spec_from_file_location("offline",Path(__file__).with_name("offline_translate.py"))
offline=importlib.util.module_from_spec(spec);spec.loader.exec_module(offline)
root=Path("tmp/translation-models")
cuda=Path("tmp/translation-cuda/bin")
if cuda.exists():
    (root/"cuda").mkdir(exist_ok=True)
    for file in cuda.glob("*.dll"):shutil.copyfile(file,root/"cuda"/file.name)
processor=sentencepiece.SentencePieceProcessor(model_file=str(root/"en-es/sentencepiece.model"))
samples=["Welcome to the Pokemon Center!","Your Pokemon are feeling better now.","Would you like to save the game?","There is a berry growing on this tree.","You need a Coin Case to play here.","Pikachu learned Thunderbolt!","Choose a language for the launcher.","The train will arrive soon."]*16
tokens=[processor.encode(s,out_type=str) for s in samples]
measurements={}
for mode in ["baseline","cpu","auto"]:
    if mode=="baseline":engine=ctranslate2.Translator(str(root/"en-es/model"),device="cpu",compute_type="int8",intra_threads=2);device="cpu"
    else:engine,device=offline.make_engine(ctranslate2,root/"en-es/model",{"hardware":mode,"models":str(root)})
    engine.translate_batch(tokens[:4],beam_size=2)
    start=time.perf_counter();results=[]
    size=16 if mode=="baseline" else (128 if device=="cuda" else 32)
    for i in range(0,len(tokens),size):
        kwargs={} if mode=="baseline" else {"batch_type":"tokens","max_batch_size":1024}
        results.extend(engine.translate_batch(tokens[i:i+size],beam_size=2,max_decoding_length=512,**kwargs))
    elapsed=time.perf_counter()-start
    assert len(results)==len(samples) and all(r.hypotheses[0] for r in results)
    measurements[mode]={"device":device,"seconds":round(elapsed,3),"segments":len(results)}
    del engine
print(json.dumps(measurements,indent=2))
Path("tmp/translation-benchmark.json").write_text(json.dumps(measurements,indent=2))
