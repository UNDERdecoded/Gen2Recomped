import React from "react";
import { Composition } from "remotion";
import { Trailer, TRAILER_FRAMES } from "./Trailer";
import { MapEditorVideo, MAP_EDITOR_FRAMES } from "./MapEditorVideo";
import { OnlineTrailer, ONLINE_TRAILER_FRAMES } from "./OnlineTrailer";

export const RemotionRoot: React.FC = () => (
  <>
    <Composition
      id="Trailer"
      component={Trailer}
      durationInFrames={TRAILER_FRAMES}
      fps={30}
      width={1920}
      height={1080}
    />
    <Composition
      id="OnlineTrailer"
      component={OnlineTrailer}
      durationInFrames={ONLINE_TRAILER_FRAMES}
      fps={30}
      width={1920}
      height={1080}
    />
    <Composition
      id="MapEditor"
      component={MapEditorVideo}
      durationInFrames={MAP_EDITOR_FRAMES}
      fps={30}
      width={1920}
      height={1080}
    />
  </>
);
