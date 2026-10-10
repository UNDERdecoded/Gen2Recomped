# Offline game-text translation

Launcher settings provide a default target language and the source language of the imported text. The selected game settings also provide an override, including **Use launcher language** and **Original ROM text**. Selecting a target schedules a background translation; **Translate this game** and **Translate imported games** retry missing entries. New imports use the current defaults.

**Launcher language** is a separate launcher setting. It defaults to English and translates the launcher UI locally, with its own cached catalog. It does not change game dialogue. Cached UI translations apply immediately; the first selection applies once its background job finishes. Unicode fonts cover Japanese, Chinese and Cyrillic labels. These UI translations are machine-generated and may leave some labels in English.

**Translation hardware** defaults to Automatic. Desktop translation tries NVIDIA CUDA with INT8/FP16 and falls back to CPU on initialization or inference failure. CPU mode uses up to eight threads and token-limited batches; beam size remains two. NVIDIA GPU mode can download the Windows CUDA 12 cuBLAS support package from NVIDIA's PyPI distribution once (about 435 MB compressed), checks its SHA-256, retains its license, and caches it outside the app package. Automatic uses existing or cached CUDA support. AMD/Intel GPUs and mobile GPU selection are not supported by this runtime; Android continues to use ML Kit. Switching hardware applies to the next queued job.

`benchmark.py` measures an installed English-Spanish pack without downloading it. A local RTX 3060 test on 128 segments measured 3.405 s for the previous CPU configuration, 1.821 s for the new CPU configuration, and 0.185 s for GPU inference. These numbers exclude model download, startup and loading and are not a guarantee for other hardware, languages or text.

The downloaded model runs locally. ROM text is never sent to a translation server. Android uses ML Kit (Android 6.0/API 23 or later); desktop uses the bundled `translation/rom-translate.exe` on Windows. Build the equivalent `rom-translate` with `build_desktop.py` for macOS/Linux. Other platforms retain original text and report that the offline runtime is unavailable.

Models, fonts and text catalogs live in the LOVE save directory under `translations/`. A catalog is keyed by game, source language, target language and exact source text. Importing changed dialogue automatically misses the old entry. Changing to **Original ROM text** restores the source on the next game launch; saves and ROM-derived files are not rewritten. Start the game after the translation job is ready.

Control tokens, format specifiers and page breaks bypass the model. Established localized species/move/item/location names are protected from the model. They are not shipped: the first translation into a language downloads PokeAPI's name tables (`data/v2/csv`, about 1.2 MB) and builds that language's list on the device, in `translations/glossary/<language>.json` (`src/translation/Glossary.lua`). The names are trademarks of Nintendo / The Pokémon Company; PokeAPI's data is BSD-3-Clause. Dialogue is machine translation, not a verified replacement for an official localized ROM. Where an official name is unavailable, the original name is retained. A damaged placeholder causes that text to remain original, with a count in the completion status.

Desktop models are Argos/CTranslate2 language packs. English is used as an intermediate language for pairs without a direct English side. The helper is built with:

```powershell
python -m venv tmp/translation-env
.\tmp\translation-env\Scripts\python.exe -m pip install -r tools/translation/requirements.txt
.\tmp\translation-env\Scripts\python.exe tools/translation/build_desktop.py
```

Include `translation/rom-translate.exe`, `data/localization`, and `src/translation` in desktop release packaging. Android releases use the Java/JNI bridge and do not need the Windows helper. Do not package downloaded model caches, test catalogs, or `tmp/`.

Tests: `tools/translation/check.lua` covers setting precedence, placeholders and read-only source overlays. `check_download.py` covers download progress and GPU fallback. `tools/translation/native_check` runs the real LOVE worker and packaged desktop helper. It downloads an English-Spanish model/font if missing, writes a separate test catalog, and renders the translated text. `launcher_check` translates the real launcher catalog, renders its buttons, and checks restoring English. Android Java compilation and NDK syntax checks cover its bridge; live Android inference still needs a device test.

Sources: [ML Kit translation](https://developers.google.com/ml-kit/language/translation/android), [Argos Translate](https://github.com/argosopentech/argos-translate), [PokeAPI data](https://github.com/PokeAPI/pokeapi), [Noto fonts](https://github.com/notofonts).
