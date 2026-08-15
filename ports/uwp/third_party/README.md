# UWP dependencies

This directory contains the complete x64 UWP Release dependency bundle used by the package build:

- `love` contains the LÖVE 11.5 and LuaJIT binaries.
- `sdl2` contains the matching SDL headers, import library, and runtime.
- `angle` contains the EGL and GLES runtime.
- `runtime` contains the codec, font, compression, and audio DLLs used by LÖVE.
- `licenses` contains the corresponding third party notices.

`manifest.json` pins the source revisions and SHA-256 hashes. Run `scripts/xbox-uwp/verify_dependencies.ps1` from the repository root after updating any dependency.
