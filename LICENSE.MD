# Licence

This project is licensed in **two parts**. `LICENSE` is the canonical text;
this file is the same terms with the reasoning spelled out.

| | What it covers | Terms |
|---|---|---|
| **Part A** | The Generation I engine this project was forked from, and every shared file since | **MIT**, unchanged, under its original authors' copyright |
| **Part B** | The Generation II (Gold / Silver / Crystal) components written for this project | **Source-available**: read it, and write mods against it |

Part A is the default. A file is Part B **only** if it appears in the
[Part B file list](#part-b-file-list).

---

## Part A — MIT

Copyright 2026 BOIS CLUB GAMES, LLC — Generation I (Red/Blue/Yellow)
recompilation, creation and code, and the engine this project is forked from

Copyright 2026 UNDERdecodedHD — Generation II additions to Part A files

> Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

**Why the Generation II work inside Part A files is also MIT.** Files like
`src/battle/BattleState.lua`, `src/world/Player.lua` and `src/ui/OakSpeech.lua`
came from the Generation I engine and merely gained Generation II branches.
They are derivative works of MIT-licensed code, and splitting one file between
two licences would leave the MIT obligations on the rest of it ambiguous. The
whole file keeps the MIT grant.

---

## Part B — Generation II components: source-available, mods only

**Copyright © 2026 UNDERdecodedHD. All rights reserved.**

The files listed below are **not** covered by Part A. They are published in
source form so that anyone can read them, understand how the Generation II
support works, and write mods against it. That is the whole of the permission
being given.

### You may

- **(a)** view, read and study the Part B source;
- **(b)** run it, unmodified, as part of a distribution obtained from
  UNDERdecodedHD, for your own use;
- **(c)** modify your own copy locally — for private use, for debugging, or to
  develop a mod under (d);
- **(d)** use what you learn from (a) and (c), and the interfaces, hooks,
  registries, data formats and file layouts Part B exposes, to **create, use
  and distribute mods** that load alongside this project — including
  commercially;
- **(e)** quote short excerpts in bug reports, issues, pull requests,
  documentation, reviews and discussion of this project.

The licence in (d) is **irrevocable for any mod already released**. A mod you
publish does not stop being licensed if this document later changes.

### You may not

Except as (d) and (e) allow:

1. copy, redistribute, publish, mirror, host or sublicense the Part B source,
   or any substantial portion of it;
2. distribute a build, port, fork or modified version of Part B, or any work
   derived from it, paid or free;
3. incorporate Part B, or any substantial portion of it, into another project
   or product;
4. sell, rent, licence or charge for access to Part B;
5. remove or alter this notice, the file list, or the copyright notices in the
   Part B files.

A mod distributed under (d) may contain **only the code you wrote**. It must
not bundle Part B source or a build of it, and it must not be Part B
repackaged with changes. Naming Part B functions, hooks and data keys in order
to work with them is expressly permitted and is not "a substantial portion".

### Interoperability

Nothing here restricts any act you are permitted by applicable law to perform
regardless of licence terms — including decompilation or analysis for
interoperability where your jurisdiction grants that right (for example
Article 6 of EU Directive 2009/24/EC, or 17 U.S.C. § 1201(f) in the US).

### Contributions

Send a change to a Part B file and you licence that change to UNDERdecodedHD
on the same terms as the rest of Part B, and confirm you have the right to do
so. You keep the copyright in what you wrote.

### No warranty

Part B is provided "AS IS", without warranty of any kind, express or implied,
including merchantability, fitness for a particular purpose and
non-infringement. In no event shall the copyright holder be liable for any
claim, damages or other liability arising from Part B or its use.

All rights not expressly granted are reserved.

---

## Part B file list

Everything not listed here is Part A (MIT). A file is Part B only where it is
wholly original Generation II work, which is why the shared engine files that
merely gained Generation II branches are absent.

```
src/battle/Gen2AnimPlayer.lua
src/import/Gen2ScriptOps.lua
src/import/RomExtractorGen2.lua
src/pokemon/PicAnim.lua
src/save_convert/Gen2Save.lua
src/script/Gen2Commands.lua
src/script/Gen2Daily.lua
src/script/Gen2Flags.lua
src/script/Gen2ScriptVM.lua
src/ui/Gen2CardFlip.lua
src/ui/Gen2Intro.lua
src/ui/Gen2Slots.lua

data/scripts/elms_lab.lua
data/scripts/mr_pokemons_house.lua
data/scripts/players_house1f.lua

docs/CRYSTAL-INTRO.md
```

**Generated content is not licensed by this document at all.** Everything
under `data/generated/` and `assets/generated/` is produced on the user's own
machine from the user's own cartridge dump. It is not distributed with this
software and nobody here claims it.

---

## Third-party material — covered by neither part

`tools/rom_manifest_gold.json`, `tools/rom_manifest_silver.json` and
`tools/rom_manifest_crystal.json` are symbol tables derived from the
[pret](https://github.com/pret) disassemblies (pokegold, pokecrystal). They
carry no original authorship of this project's and are deliberately **not** in
Part B; they are reproduced with attribution only, and will be removed on
request from their authors.

`data/palettes_gbc.lua` is derived from
[pokered-gbc](https://github.com/Stewmath/pokered-gbc) by FroggestSpirit,
Drenn, and Danny-E. `data/palettes_yellow.lua` is derived from the
[pret/pokeyellow](https://github.com/pret/pokeyellow) disassembly. Neither
upstream project publishes a licence, so those two files are reproduced with
attribution only and are **not** relicensed by this document; they will be
removed on request from their authors.

`mobile/android/love/` vendors LÖVE for Android, SDL2, oboe, and LuaJIT, each
under its own licence as shipped in that subtree.

`mods/` holds separately authored mods, each under the licence in its own
directory.

---

## Fan work notice

This project is an unofficial fan work. It is not affiliated with, endorsed
by, or sponsored by Nintendo, Creatures Inc., or GAME FREAK inc. Pokémon and
all related names are their trademarks.

No game ROM, ROM data, or copyrighted game asset is distributed with this
software; a legally obtained cartridge dump supplied by the user is the only
source of game content, and every byte of it stays on the user's machine.

Nothing in Part B is a claim over Pokémon Gold, Silver or Crystal, over their
data, or over any part of them. Part B claims only the original code written
to read a cartridge the user already owns.
