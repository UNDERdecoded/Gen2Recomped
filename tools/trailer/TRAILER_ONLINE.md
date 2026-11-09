# RetroRecomped: "Play Together" trailer (shot-matched script)

The second trailer, made the same way as the first (`TRAILER.md`).
- **Footage:** every shot is real, recorded by `capture.lua` or another driver.
- **Edit:** `remotion/src/OnlineTrailer.tsx`.
- **Audio:** `audio/make_audio.py` generates the music and sound effects. They are original and procedural, with no licensed samples.

Target: **~100 s**, 30 fps, 1920×1080.
- **Music:** one track with a build, a drop at 0:20 (the online reveal) and a second lift at 1:08 (the voxel section). It ends on a hit at 1:34, the logo slam, then rings out.
- **Sound effects:** whooshes on the big cuts, a riser into each drop, a hit under each title card, UI blips under on-screen menus, and a start-up chime at 0:00.

Footage lands in `G:\Gen2Recomped\trailer_footage` (`<version>_<shot>.mp4`), which is also where `public/footage` points.
- Never copy footage, ROM art, or rendered frames into the repo.

| Time | Footage file | On screen | Card / sound |
|---|---|---|---|
| 0:00–0:03 | — | Black, then the logo. | Chime · **RETRORECOMPED** |
| 0:03–0:07 | `platinum_twinleaf` | Sinnoh on the cartridge camera, quiet. | *"Your adventure was always single player."* |
| 0:07–0:11 | `heartgold_newbark`, `black_nuvema` | Two quick cuts: Johto on DS, Unova. | Riser starts |
| 0:11–0:16 | `online_room` | A link room with other players walking around it. | *"Not anymore."* |
| 0:16–0:20 | `online_host_code` | HOST WITH FRIENDS, then the short share code and QR. | Blips · riser |
| **0:20** | — | **Drop.** | Hit · **ONLINE** |
| 0:20–0:26 | `online_world` | A shared overworld: friends' avatars in your world, with chat bubbles. | **PLAY TOGETHER** |
| 0:26–0:31 | `online_battle` | A link battle between two players. | **LINK BATTLES** |
| 0:31–0:35 | `online_multi` | A 4-player multi battle. | **2v2 MULTI** |
| 0:35–0:40 | `online_gts`, `online_trade` | Depositing on the GTS, then a trade animation. | **TRADE · GTS** |
| 0:40–0:42 | — | Card. | Whoosh · **GEN I – V. ACROSS GENERATIONS.** |
| 0:42–0:48 | `heartgold_goldenrod`, `soulsilver_ecruteak` | Johto on the DS engine, native 3D. | **HEARTGOLD · SOULSILVER** |
| 0:48–0:54 | `black_castelia`, `white_nimbasa` | Unova cities. | **BLACK · WHITE** |
| 0:54–0:58 | `platinum_jubilife` | Sinnoh. | **PLATINUM** |
| 0:58–1:02 | — | Card. | Hit · **NOW AVAILABLE IN THE APP** |
| 1:02–1:05 | `launcher_games` | The launcher's game list with the new games in it. | Blips |
| 1:05–1:08 | `heartgold_first_person`, `black_first_person` | First person through a DS town. | **FIRST PERSON** |
| **1:08** | — | **Second lift.** | |
| 1:08–1:12 | `platinum_third_person`, `soulsilver_third_person` | Over-the-shoulder runs. | **THIRD PERSON** |
| 1:12–1:17 | `walker_screen` | The Monster Walker: steps, watts, a catch. | **MONSTER WALKER** |
| 1:17–1:24 | `minigame_pokeathlon`, `minigame_musical`, `minigame_contest`, `minigame_slots` | Four fast cuts: Pokéathlon, the BW Musical, a Platinum contest, the slots. | Whoosh each · **MINIGAMES** |
| 1:24–1:31 | `emerald3ds_reveal`, `emerald3ds_town`, `emerald3ds_battle` | Hoenn in Emerald 3DS voxels: cast shadows, relief, a 3D battle. | **ZALLAX'S EMERALD 3DS VOXELS** (small: *ported with permission*) |
| 1:31–1:34 | — | Montage of 6 frames, one per game, 8 frames each. | Riser |
| 1:34–1:40 | end card | The logo slam, then supported games, platforms and links. | Final hit, ring-out |

## End card

- **Games:** Red · Blue · Yellow · Gold · Silver · Crystal · FireRed · LeafGreen · Emerald · Platinum · HeartGold · SoulSilver · Black · White
- **Platforms:** Windows · macOS · Linux · Steam Deck · Android · iOS · Switch · Xbox
- **Links:** discord.gg/4VXnEnePT · tiltrips.com/r/GEN2RECOMP
- **Disclaimer (small):** Non-commercial fan project. No game files included; import your own legally obtained ROMs.

## Recording

New shots are added to `capture.lua`, one block per game (`heartgold`, `soulsilver`, `black`, `white`, plus Platinum's `first_person`). Run them like this:

```powershell
powershell -ExecutionPolicy Bypass -File tools/trailer/capture_all.ps1 -Versions heartgold,soulsilver,black,white,platinum
```

The online, Walker, minigame and Emerald 3DS shots come from their own drivers. Each driver header says how to run it.

## Rendering

```powershell
cd tools/trailer/remotion
python ../audio/make_audio.py public/audio    # music + sound effects (git-ignored)
npx remotion render src/index.ts OnlineTrailer out/online_trailer.mp4 --crf 16
```
