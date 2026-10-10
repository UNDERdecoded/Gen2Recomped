"""Run inside a venv with requirements.txt installed; builds for the host OS."""
import subprocess, sys
subprocess.run([sys.executable, "tools/translation/build_engine_sources.py"],check=True)
subprocess.run([sys.executable, "-m", "PyInstaller", "--noconfirm", "--onefile",
 "--name", "rom-translate", "--distpath", "translation", "--workpath", "tmp/translation-build",
 "--specpath", "tmp/translation-build", "--collect-all", "ctranslate2", "--collect-all", "sentencepiece",
 "tools/translation/offline_translate.py"],check=True)
