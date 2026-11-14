// The map editor showcase, cut from tools/trailer/editor_tour.lua's footage
// (public/editor is a junction to G:\Gen2Recomped\editor_footage). Every
// click in it is a real click on the real editor; the on-screen labels are
// drawn by the tour itself.
//
//   npx remotion render src/index.ts MapEditor out/map_editor.mp4
import React from "react";
import {
  AbsoluteFill,
  Audio,
  interpolate,
  OffthreadVideo,
  Sequence,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { Card, GOLD, Logo, PIXEL, SANS, useEdgeFade } from "./Trailer";

const MUSIC = false;
const FPS = 30;
const s = (sec: number) => Math.round(sec * FPS);

// clip lengths as recorded (seconds)
const CLIPS = {
  ed_crystal_browse: 7.8,
  ed_crystal_3d: 6.2,
  ed_crystal_tiles: 30.0,
  ed_crystal_walkable: 6.5,
  ed_crystal_npcs: 8.5,
  ed_crystal_world: 4.7,
  ed_crystal_import: 8.5,
  ed_crystal_cave3d: 3.5,
  ed_crystal_link: 18.0,
  ed_crystal_pack: 6.9,
  ed_plat_browse: 6.3,
  ed_plat_place: 8.2,
  ed_plat_change: 15.8,
} as const;
type ClipName = keyof typeof CLIPS;

const Clip: React.FC<{ name: ClipName; dur: number; label?: string }> = ({ name, dur, label }) => {
  const f = useCurrentFrame();
  const opacity = useEdgeFade(dur, 8);
  const scale = interpolate(f, [0, dur], [1, 1.02]);
  return (
    <AbsoluteFill style={{ opacity, backgroundColor: "black" }}>
      <OffthreadVideo
        src={staticFile(`editor/${name}.mp4`)}
        muted
        style={{ width: "100%", height: "100%", transform: `scale(${scale})` }}
      />
      {label ? <Chip text={label} /> : null}
    </AbsoluteFill>
  );
};

// a small section chip, top-left, over the editor's title bar
const Chip: React.FC<{ text: string }> = ({ text }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = spring({ frame: f, fps, config: { damping: 200 } });
  return (
    <div
      style={{
        position: "absolute",
        right: 40,
        bottom: 40,
        opacity: p,
        transform: `translateY(${(1 - p) * 20}px)`,
        background: "rgba(11,15,26,0.9)",
        border: `3px solid ${GOLD}`,
        borderRadius: 12,
        padding: "12px 22px",
        fontFamily: PIXEL,
        fontSize: 22,
        color: "white",
      }}
    >
      {text}
    </div>
  );
};

const SectionCard: React.FC<{ dur: number; gen: string; game: string; sub: string }> = ({ dur, gen, game, sub }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = spring({ frame: f, fps, config: { damping: 14 } });
  return (
    <Card dur={dur}>
      <div style={{ fontFamily: PIXEL, fontSize: 34, color: GOLD, letterSpacing: 4 }}>{gen}</div>
      <div
        style={{
          fontFamily: PIXEL,
          fontSize: 84,
          color: "white",
          marginTop: 24,
          textShadow: "6px 6px 0 #000",
          transform: `scale(${0.8 + 0.2 * p})`,
        }}
      >
        {game}
      </div>
      <div style={{ fontFamily: SANS, fontSize: 32, color: "#d6e0f5", marginTop: 26, fontWeight: 600 }}>{sub}</div>
    </Card>
  );
};

type Beat = { len: number; el: React.ReactNode };
const clip = (name: ClipName, label?: string): Beat => {
  const len = s(CLIPS[name]);
  return { len, el: <Clip name={name} dur={len} label={label} /> };
};

const beats: Beat[] = [
  {
    len: s(4),
    el: (
      <Card dur={s(4)} bg="black">
        <Logo width={1100} />
        <div style={{ fontFamily: PIXEL, fontSize: 52, color: "white", marginTop: 34, letterSpacing: 6 }}>MAP EDITOR</div>
        <div style={{ fontFamily: SANS, fontSize: 28, color: "#9aa7c7", marginTop: 20 }}>
          Every map. Every tile. Every model. Built in.
        </div>
      </Card>
    ),
  },
  { len: s(2.5), el: <SectionCard dur={s(2.5)} gen="GEN II" game="CRYSTAL" sub="Tiles, collision, NPCs and warps, in 2D or 3D" /> },
  clip("ed_crystal_browse", "PICK ANY MAP"),
  clip("ed_crystal_3d", "EDIT IN 3D"),
  clip("ed_crystal_tiles", "TILES"),
  clip("ed_crystal_walkable", "WALKABLE"),
  clip("ed_crystal_npcs", "NPCs & WARPS"),
  clip("ed_crystal_world", "WORLD MAP"),
  { len: s(2.5), el: <SectionCard dur={s(2.5)} gen="GEN I  →  GEN II" game="RED  →  CRYSTAL" sub="Import any map from another game you own" /> },
  clip("ed_crystal_import", "IMPORT FROM RED"),
  clip("ed_crystal_cave3d", "CERULEAN CAVE"),
  clip("ed_crystal_link", "CAVE MOUTH + WARP"),
  clip("ed_crystal_pack", "EXPORT A MAP PACK"),
  { len: s(2.5), el: <SectionCard dur={s(2.5)} gen="GEN IV" game="PLATINUM" sub="Place, swap, move and scale the real 3D models" /> },
  clip("ed_plat_browse", "JUBILIFE CITY"),
  clip("ed_plat_place", "PLACE MODELS"),
  clip("ed_plat_change", "MOVE · CHANGE · SCALE"),
  {
    len: s(7),
    el: (
      <Card dur={s(7)} bg="black">
        <Logo width={900} />
        <div style={{ fontFamily: SANS, fontSize: 34, color: "white", marginTop: 40, fontWeight: 700 }}>
          Export your edits as a map pack and share them as a mod.
        </div>
        <div style={{ fontFamily: SANS, fontSize: 28, color: "#b9c6ff", marginTop: 30 }}>discord.gg/VswK7HpYab</div>
        <div style={{ fontFamily: SANS, fontSize: 26, color: "white", marginTop: 34 }}>Rip packs with us on Tilt Rips:</div>
        <div style={{ fontFamily: PIXEL, fontSize: 28, color: GOLD, marginTop: 14 }}>tiltrips.com/r/GEN2RECOMP</div>
      </Card>
    ),
  },
];

export const MAP_EDITOR_FRAMES = beats.reduce((n, b) => n + b.len, 0);

export const MapEditorVideo: React.FC = () => {
  let t = 0;
  return (
    <AbsoluteFill style={{ backgroundColor: "black" }}>
      {beats.map((b, i) => {
        const from = t;
        t += b.len;
        return (
          <Sequence key={i} from={from} durationInFrames={b.len}>
            {b.el}
          </Sequence>
        );
      })}
      {MUSIC ? <Audio src={staticFile("music_editor.mp3")} /> : null}
    </AbsoluteFill>
  );
};
