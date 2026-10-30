# Gen2Recomped — Trailer (shot-matched script)

Every shot below is **real footage recorded by the harness**. Nothing is mocked up.
`tools/trailer/capture_all.ps1` writes each shot as `<Out>/<version>_<shot>.mp4`
(30 fps 1920×1080 H.264). Frames stream straight into ffmpeg, so no PNGs are written.
Every Gen 2 and Gen 3 shot is recorded with the DramaticShapes voxel diorama on.
Platinum is natively 3D. It is recorded on the cartridge camera (CAM TILT rung 1) with the bottom screen off; its `third_person` shot uses rung 9.
Default output: `G:\Gen2Recomped\trailer_footage`.

Capture identity: `%APPDATA%\LOVE\trailer_cap\options.lua`, a copy of your options with these changes:
- dataDir `G:\Gen2Recomped`
- DramaticShapes on, with DAYTIME = SYNC so the harness's pinned hour drives day, dusk and night
- BATTLE_ART_VOXEL_GEN2 off

Your own options are untouched.

Target length is **~90 s** at 30 fps. Music: one rising track that hits a beat at 0:20 (the voxel reveal) and at 1:05 (the "coming soon" card).

| Time | Shot | On screen | Text / VO |
|---|---|---|---|
| 0:00–0:04 | — | Black. A Game Boy start-up chime. Logo fades in. | **GEN2RECOMPED** |
| 0:04–0:12 | `crystal_voxel_reveal` (first half) | New Bark Town, flat, exactly as it shipped in 2000. | *"You remember it like this."* |
| 0:12–0:20 | `crystal_voxel_reveal` (second half) | Mid-walk the town lifts into 3D voxels and the camera pulls back. | *"Now walk back in."* |
| 0:20–0:26 | `crystal_newbark_day` → `crystal_newbark_night` | Same town, day cross-fading to night. | REAL DAY / NIGHT |
| 0:26–0:32 | `crystal_ecruteak_dusk`, `crystal_goldenrod` | Two quick cuts through Johto cities. | |
| 0:32–0:38 | `crystal_first_person` | First person, walking down the river. | **FIRST PERSON** |
| 0:38–0:44 | `crystal_third_person` | Over-the-shoulder run through Cherrygrove. | **THIRD PERSON** |
| 0:44–0:52 | `crystal_battle_shiny` | Shiny Gyarados, fought on the map itself. | **BATTLES IN THE WORLD** |
| 0:52–0:56 | `crystal_overview` | Full diorama view of Violet City. | |
| 0:56–1:02 | `firered_voxel_reveal`, `firered_pallet`, `firered_battle` | Kanto in voxels. | GEN I · GEN II · GEN III |
| 1:02–1:08 | `emerald_slateport`, `emerald_lilycove`, `emerald_first_person` | Hoenn. | |
| 1:08–1:16 | `platinum_jubilife`, `platinum_third_person`, `platinum_snowpoint`, `platinum_hearthome`, `platinum_battle` | Sinnoh, native 3D, single screen. | **GEN IV** |
| 1:16–1:22 | title cards | HeartGold / SoulSilver / Black / White logos, silhouetted. | **COMING SOON** |
| 1:22–1:27 | launcher capture (see below) | Mod list and mod toggles. | **BUILT TO BE MODDED** |
| 1:27–1:30 | end card | Logo, platforms, links. | Discord · Tilt Rips referral |

End-card text:
- Red · Blue · Yellow · Gold · Silver · Crystal · FireRed · Emerald · Platinum
- Windows · macOS · Linux · Steam Deck · Android · Switch · iOS
- "Rip packs with us on Tilt Rips — tiltrips.com/r/GEN2RECOMP" (Tilt Rips is a pack-opening site)
- discord.gg/VswK7HpYab

Not captured by the harness yet:
- **Gen I (Red/Blue/Yellow):** import a Red ROM first, then add a `red` block to `capture.lua`.
- **Launcher / mod menu:** record with OBS (Win+Alt+R also works) for 5 s.
- **HGSS / BW title cards:** made in the editor.

## Re-recording

```powershell
powershell -ExecutionPolicy Bypass -File tools/trailer/capture_all.ps1 -Versions crystal -Only voxel_reveal,first_person
```

Environment knobs are listed in the header of `tools/trailer/capture.lua`. ffmpeg lives in
`G:\Tools\ffmpeg-9.0.2-essentials_build\bin` (`-Ffmpeg` overrides the path).

## Editing: Remotion

`tools/trailer/remotion` is the cut as code. `src/Trailer.tsx` follows the beat sheet above, and
`public/footage` is a junction to `G:\Gen2Recomped\trailer_footage`.

```powershell
cd tools/trailer/remotion
npx remotion studio src/index.ts     # preview and scrub in the browser
npx remotion render src/index.ts Trailer out/trailer.mp4 --crf 16
```

Remotion writes full-range color (`yuvj420p`). Make the copy for Clipchamp and uploads with:

```powershell
G:\Tools\ffmpeg-9.0.2-essentials_build\bin\ffmpeg.exe -i out/trailer.mp4 -vf "scale=in_range=full:out_range=tv,format=yuv420p" -c:v libx264 -preset slow -crf 18 -movflags +faststart out/trailer_share.mp4
```

To add music, put `public/music.mp3` in place and set `MUSIC = true` in `Trailer.tsx`.
Remotion is free for individuals and companies of up to 3 people; larger teams need a company license.

## Finishing in Clipchamp

Clipchamp has no scripting API, so the handoff is files:
- Import `out/trailer.mp4` for music, voice-over and Clipchamp's own effects.
- Or import the per-shot MP4s from `G:\Gen2Recomped\trailer_footage` and cut by hand, using the table above as the edit list.
