// The Gen2Recomped trailer, cut from the harness footage in public/footage
// (a junction to G:\Gen2Recomped\trailer_footage, one MP4 per shot, recorded
// by tools/trailer/capture_all.ps1). The beat sheet is tools/trailer/TRAILER.md.
//
//   npm run studio   -- preview and scrub
//   npm run render   -- out/trailer.mp4
//
// Optional music: drop public/music.mp3 and set MUSIC = true.
import React from "react";
import {
  AbsoluteFill,
  Audio,
  Easing,
  Img,
  interpolate,
  OffthreadVideo,
  Sequence,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { loadFont as loadPixel } from "@remotion/google-fonts/PressStart2P";
import { loadFont as loadSans } from "@remotion/google-fonts/Inter";

export const { fontFamily: PIXEL } = loadPixel();
export const { fontFamily: SANS } = loadSans("normal", { weights: ["500", "600", "700"], subsets: ["latin"] });

const MUSIC = false;
const FPS = 30;
const s = (sec: number) => Math.round(sec * FPS);

export const GOLD = "#f8d030";
export const INK = "#0b0f1a";

// ----------------------------------------------------------- building blocks

// a fade in and out on the edges of a clip
export const useEdgeFade = (dur: number, edge = 8) => {
  const f = useCurrentFrame();
  return interpolate(f, [0, edge, dur - edge, dur], [0, 1, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
};

// one shot of game footage, with a slow push-in so even a still beat moves
const Shot: React.FC<{ src: string; dur: number; from?: number; push?: number; fade?: number }> = ({
  src,
  dur,
  from = 0,
  push = 0.04,
  fade = 8,
}) => {
  const f = useCurrentFrame();
  const opacity = useEdgeFade(dur, fade);
  const scale = interpolate(f, [0, dur], [1, 1 + push]);
  return (
    <AbsoluteFill style={{ opacity, backgroundColor: "black" }}>
      <OffthreadVideo
        src={staticFile(`footage/${src}.mp4`)}
        startFrom={from}
        muted
        style={{ width: "100%", height: "100%", objectFit: "cover", transform: `scale(${scale})` }}
      />
    </AbsoluteFill>
  );
};

// a kinetic caption: slides up, holds, fades
const Caption: React.FC<{ text: string; sub?: string; dur: number; pos?: "low" | "mid" | "top" }> = ({
  text,
  sub,
  dur,
  pos = "low",
}) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const enter = spring({ frame: f, fps, config: { damping: 200 } });
  const out = interpolate(f, [dur - 10, dur], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return (
    <AbsoluteFill
      style={{
        justifyContent: pos === "low" ? "flex-end" : pos === "top" ? "flex-start" : "center",
        alignItems: "flex-start",
        padding: pos === "low" ? "0 0 110px 120px" : pos === "top" ? "150px 0 0 120px" : "0 0 0 120px",
        opacity: out,
      }}
    >
      <div
        style={{
          transform: `translateY(${(1 - enter) * 40}px)`,
          opacity: enter,
          background: "linear-gradient(90deg, rgba(11,15,26,0.85), rgba(11,15,26,0))",
          padding: "22px 140px 22px 28px",
          borderLeft: `8px solid ${GOLD}`,
        }}
      >
        <div style={{ fontFamily: PIXEL, fontSize: 46, color: "white", letterSpacing: 2, textShadow: "4px 4px 0 #000" }}>
          {text}
        </div>
        {sub ? (
          <div style={{ fontFamily: SANS, fontSize: 30, color: "#d6e0f5", marginTop: 14, fontWeight: 500 }}>{sub}</div>
        ) : null}
      </div>
    </AbsoluteFill>
  );
};

// letterbox bars for the cinematic stretch
const Letterbox: React.FC = () => (
  <>
    <div style={{ position: "absolute", top: 0, left: 0, right: 0, height: 70, background: "black" }} />
    <div style={{ position: "absolute", bottom: 0, left: 0, right: 0, height: 70, background: "black" }} />
  </>
);

// a full-screen title card
export const Card: React.FC<{ dur: number; children: React.ReactNode; bg?: string }> = ({ dur, children, bg = INK }) => {
  const opacity = useEdgeFade(dur, 10);
  return (
    <AbsoluteFill style={{ backgroundColor: bg, justifyContent: "center", alignItems: "center", opacity }}>
      {children}
    </AbsoluteFill>
  );
};

// the RetroRecomped logo (public/logo.png, from assets/logo/gen2logo.png),
// popping in on a spring
export const Logo: React.FC<{ width?: number }> = ({ width = 1300 }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const pop = spring({ frame: f, fps, config: { damping: 12, stiffness: 120 } });
  return (
    <Img
      src={staticFile("logo.png")}
      style={{ width, height: "auto", transform: `scale(${0.6 + 0.4 * pop})` }}
    />
  );
};

// the "flat -> voxel" moment: a white flash right where the reveal clip switches
const Flash: React.FC<{ at: number }> = ({ at }) => {
  const f = useCurrentFrame();
  const o = interpolate(f, [at - 2, at, at + 14], [0, 0.85, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.quad),
  });
  return <AbsoluteFill style={{ backgroundColor: "white", opacity: o }} />;
};

// quick-cut montage: each entry is [clip, length in frames, start in the clip]
const Montage: React.FC<{ cuts: [string, number, number?][] }> = ({ cuts }) => {
  let t = 0;
  return (
    <>
      {cuts.map(([src, len, from], i) => {
        const start = t;
        t += len;
        return (
          <Sequence key={i} from={start} durationInFrames={len}>
            <Shot src={src} dur={len} from={from ?? 30} fade={5} push={0.03} />
          </Sequence>
        );
      })}
    </>
  );
};

const GenTag: React.FC<{ gen: string; game: string; region: string; dur: number }> = ({ gen, game, region, dur }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const enter = spring({ frame: f, fps, config: { damping: 200 } });
  const out = interpolate(f, [dur - 8, dur], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return (
    <AbsoluteFill style={{ alignItems: "flex-end", justifyContent: "flex-start", padding: "110px 110px 0 0", opacity: out }}>
      <div style={{ textAlign: "right", transform: `translateX(${(1 - enter) * 60}px)`, opacity: enter }}>
        <div style={{ fontFamily: PIXEL, fontSize: 30, color: GOLD, textShadow: "3px 3px 0 #000" }}>{gen}</div>
        <div style={{ fontFamily: PIXEL, fontSize: 54, color: "white", marginTop: 12, textShadow: "5px 5px 0 #000" }}>{game}</div>
        <div style={{ fontFamily: SANS, fontSize: 28, color: "#e8eefc", marginTop: 10, fontWeight: 600 }}>{region}</div>
      </div>
    </AbsoluteFill>
  );
};

// ------------------------------------------------------------------ the cut

type Beat = { len: number; el: React.ReactNode };

const beats: Beat[] = [
  // 0:00 cold open
  {
    len: s(4),
    el: (
      <Card dur={s(4)} bg="black">
        <Logo />
        <div style={{ fontFamily: SANS, fontSize: 30, color: "#9aa7c7", marginTop: 40, letterSpacing: 8 }}>
          THE GAMES YOU REMEMBER. REBUILT.
        </div>
      </Card>
    ),
  },
  // 0:04 the reveal: flat, then the town lifts into voxels
  {
    len: s(8),
    el: (
      <>
        <Shot src="crystal_voxel_reveal" dur={s(8)} from={0} push={0.06} />
        <Flash at={s(4)} />
        <Sequence durationInFrames={s(3.8)}>
          <Caption text="YOU REMEMBER IT LIKE THIS." dur={s(3.8)} />
        </Sequence>
        <Sequence from={s(4.3)} durationInFrames={s(3.7)}>
          <Caption text="NOW WALK BACK IN." dur={s(3.7)} />
        </Sequence>
      </>
    ),
  },
  // 0:12 day and night
  {
    len: s(6),
    el: (
      <>
        <Sequence durationInFrames={s(3.2)}>
          <Shot src="crystal_newbark_day" dur={s(3.2)} from={20} />
        </Sequence>
        <Sequence from={s(2.8)} durationInFrames={s(3.2)}>
          <Shot src="crystal_newbark_night" dur={s(3.2)} from={60} />
        </Sequence>
        <Caption text="A REAL DAY AND NIGHT" sub="Lit by the sun, the moon and your system clock" dur={s(6)} />
      </>
    ),
  },
  // 0:18 Johto montage
  {
    len: s(6),
    el: (
      <>
        <Montage
          cuts={[
            ["crystal_ecruteak_dusk", s(2), 20],
            ["crystal_goldenrod", s(2), 30],
            ["crystal_cherrygrove_tiltshift", s(2), 40],
          ]}
        />
        <GenTag gen="GEN II" game="CRYSTAL" region="Johto" dur={s(6)} />
      </>
    ),
  },
  // 0:24 first person
  {
    len: s(6),
    el: (
      <>
        <Shot src="crystal_first_person" dur={s(6)} from={0} push={0} />
        <Letterbox />
        <Caption text="FIRST PERSON" sub="Walk New Bark Town at eye level" dur={s(6)} />
      </>
    ),
  },
  // 0:30 third person
  {
    len: s(6),
    el: (
      <>
        <Shot src="crystal_third_person" dur={s(6)} from={0} push={0} />
        <Letterbox />
        <Caption text="THIRD PERSON" sub="Or follow over the shoulder" dur={s(6)} />
      </>
    ),
  },
  // 0:36 battles on the map
  {
    len: s(8),
    el: (
      <>
        <Shot src="crystal_battle_shiny" dur={s(8)} from={s(3.5)} push={0.05} />
        <Caption text="BATTLES IN THE WORLD" sub="Fought where you stand" dur={s(8)} pos="mid" />
      </>
    ),
  },
  // 0:44 diorama overview
  {
    len: s(4),
    el: <Shot src="crystal_overview" dur={s(4)} from={30} push={0.08} />,
  },
  // 0:48 Kanto
  {
    len: s(7),
    el: (
      <>
        <Montage
          cuts={[
            ["firered_voxel_reveal", s(2.5), s(4)],
            ["firered_pallet", s(2), 30],
            ["firered_battle", s(2.5), s(2)],
          ]}
        />
        <GenTag gen="GEN III" game="FIRERED" region="Kanto" dur={s(7)} />
      </>
    ),
  },
  // 0:55 Hoenn
  {
    len: s(7),
    el: (
      <>
        <Montage
          cuts={[
            ["emerald_slateport", s(2.3), 30],
            ["emerald_lilycove", s(2.2), 30],
            ["emerald_first_person", s(2.5), 20],
          ]}
        />
        <GenTag gen="GEN III" game="EMERALD" region="Hoenn" dur={s(7)} />
      </>
    ),
  },
  // 1:02 Sinnoh
  {
    len: s(8),
    el: (
      <>
        <Montage
          cuts={[
            ["platinum_jubilife", s(1.6), 40],
            ["platinum_third_person", s(1.6), 0],
            ["platinum_snowpoint", s(1.6), 30],
            ["platinum_hearthome", s(1.6), 40],
            ["platinum_battle", s(1.6), s(5)],
          ]}
        />
        <GenTag gen="GEN IV" game="PLATINUM" region="Sinnoh" dur={s(8)} />
      </>
    ),
  },
  // 1:10 coming soon
  { len: s(6), el: <ComingSoon dur={s(6)} /> },
  // 1:16 modding
  { len: s(5), el: <Modding dur={s(5)} /> },
  // 1:21 end card
  { len: s(9), el: <EndCard dur={s(9)} /> },
];

function ComingSoon({ dur }: { dur: number }) {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const games = [
    ["HEARTGOLD", "#e8b830"],
    ["SOULSILVER", "#c8d0e0"],
    ["BLACK", "#f0f0f0"],
    ["WHITE", "#f0f0f0"],
  ];
  return (
    <Card dur={dur}>
      <div style={{ fontFamily: PIXEL, fontSize: 40, color: "#9aa7c7", letterSpacing: 6, marginBottom: 60 }}>COMING SOON</div>
      <div style={{ display: "flex", gap: 70 }}>
        {games.map(([g, c], i) => {
          const p = spring({ frame: f - 8 - i * 7, fps, config: { damping: 14 } });
          return (
            <div
              key={g}
              style={{
                fontFamily: PIXEL,
                fontSize: 48,
                color: c,
                opacity: p,
                transform: `translateY(${(1 - p) * 50}px)`,
                textShadow: "5px 5px 0 #000",
              }}
            >
              {g}
            </div>
          );
        })}
      </div>
      <div style={{ fontFamily: SANS, fontSize: 30, color: "#d6e0f5", marginTop: 60 }}>Johto returns. Unova arrives.</div>
    </Card>
  );
}

function Modding({ dur }: { dur: number }) {
  const f = useCurrentFrame();
  const items = ["Voxel dioramas", "3D battles", "First & third person", "Map packs", "Sprite sets", "Your own mods"];
  return (
    <Card dur={dur}>
      <div style={{ fontFamily: PIXEL, fontSize: 56, color: GOLD, textShadow: "6px 6px 0 #7a3b00", marginBottom: 56 }}>
        BUILT TO BE MODDED
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 420px)", gap: "26px 30px" }}>
        {items.map((t, i) => {
          const o = interpolate(f, [8 + i * 5, 18 + i * 5], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
          return (
            <div
              key={t}
              style={{
                opacity: o,
                fontFamily: SANS,
                fontSize: 32,
                fontWeight: 700,
                color: "white",
                border: "3px solid #2c3a5c",
                background: "#141c30",
                padding: "18px 22px",
              }}
            >
              <span style={{ color: GOLD, fontFamily: PIXEL, fontSize: 22, marginRight: 14 }}>+</span>
              {t}
            </div>
          );
        })}
      </div>
    </Card>
  );
}

function EndCard({ dur }: { dur: number }) {
  const f = useCurrentFrame();
  const late = interpolate(f, [20, 40], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return (
    <Card dur={dur} bg="black">
      <Logo width={900} />
      <div style={{ opacity: late, textAlign: "center" }}>
        <div style={{ fontFamily: SANS, fontSize: 30, color: "#e8eefc", marginTop: 46, fontWeight: 600 }}>
          Red · Blue · Yellow · Gold · Silver · Crystal · FireRed · Emerald · Platinum
        </div>
        <div style={{ fontFamily: SANS, fontSize: 26, color: "#9aa7c7", marginTop: 18 }}>
          Windows · macOS · Linux · Steam Deck · Android · Switch · iOS
        </div>
        <div style={{ fontFamily: SANS, fontSize: 28, color: "white", marginTop: 54 }}>
          Rip packs with us on Tilt Rips:
        </div>
        <div style={{ fontFamily: PIXEL, fontSize: 30, color: GOLD, marginTop: 18 }}>tiltrips.com/r/GEN2RECOMP</div>
        <div style={{ fontFamily: SANS, fontSize: 28, color: "#b9c6ff", marginTop: 40 }}>discord.gg/VswK7HpYab</div>
      </div>
    </Card>
  );
}

export const TRAILER_FRAMES = beats.reduce((n, b) => n + b.len, 0);

export const Trailer: React.FC = () => {
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
      {MUSIC ? <Audio src={staticFile("music.mp3")} /> : null}
    </AbsoluteFill>
  );
};
