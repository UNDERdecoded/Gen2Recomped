# Polished Crystal audio decoding

Polished Crystal 3.2.3 uses packed duty opcodes, parameter-free per-channel panning, shifted command numbers, and little-endian tempo/pitch-offset words. Reading these as standard Crystal commands desynchronized the stream. The synth now selects a separate normalization path through `audio.gen2Dialect`, including noise-kit changes and channel conditions. Def-local chip programs retain their existing interpretation.

The importer now reads Polished's seven drumkits using entry-relative byte pointers, preserves the rest entry, and loads all thirteen wave instruments. The music-worker packet includes this dialect and its drumkits. Data loading stamps the dialect for Polished only; the cache revision requires rebuilding Polished's old audio metadata without invalidating other games.

Validation: `tools/polished_audio_check.lua` passes 895 checks, covering 194 native songs, 212 effect headers, 68 cry headers, extracted metadata, worker propagation, equivalent standard/Polished PCM, and the native Gold/Silver/Crystal music rosters. Mono/stereo and Switch audio checks also pass. Native New Bark Town PCM renders without invalid samples. This is program/PCM verification, not a claim of complete hardware audio parity.

References: [Polished audio macros](https://github.com/Rangi42/polishedcrystal/blob/master/macros/scripts/audio.asm), [audio engine](https://github.com/Rangi42/polishedcrystal/blob/master/audio/engine.asm), [drumkits](https://github.com/Rangi42/polishedcrystal/blob/master/audio/drumkits.asm). Command table and pointer layouts were also checked directly against the supported local ROM and its matching symbol manifest.
