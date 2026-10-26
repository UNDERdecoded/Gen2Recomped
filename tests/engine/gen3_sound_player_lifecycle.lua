package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Sound, V = require("src.core.Sound"), require("src.core.GameVersion")
for _, version in ipairs({ "firered", "emerald" }) do
  local rows = dofile("tests/enemy_actions/native_sound_lifecycle.lua").run(".", "gen2", version)
  T.eq(#rows, 20, "every native player/control/role/override case executes")
  for _, row in ipairs(rows) do
    local last = row.states[#row.states]
    local expected = ({
      ["independent-players"] = 2,
      ["replace-one-player"] = 2,
      ["same-id-independent-players"] = 2,
      ["replace-after-clone"] = 2,
      ["file-override"] = 2,
      ["string-override"] = 2,
      ["stop-all"] = 0,
      ["stop-cloned-id"] = 0,
    })[row.case] or 1
    T.eq(#last, expected, row.case .. " keeps exactly its native output ownership")
    if row.case == "same-id-independent-players" then
      T.same(last[1], last[2], "one PCM variant can sound on two independently owned players")
    elseif row.case == "special-player" or row.case == "retain-special-player" then
      T.eq(
        row.queries[#row.queries].any,
        version == "firered",
        "Emerald regular SE polling excludes player three"
      )
      T.eq(row.queries[#row.queries]["164"], true, "explicit native polling includes player three")
    elseif
      row.case == "file-override"
      or row.case == "string-override"
      or row.case == "disabled-override"
    then
      T.eq(row.queries[#row.queries]["164"], false, "override outputs do not impersonate a native player")
      T.eq(row.queries[#row.queries]["141"], true, "override does not cut the existing native player")
    end
  end
  local f = dofile("tests/enemy_actions/assist.lua").fixture(".", "gen2", version)
  local Handshake, Copy = require("src.link.Handshake"), require("src.mods.Merge").deepCopy
  local current = Handshake.hello(f.game, "battle")
  T.eq(current.nativeBattleRevision, 18, "native player lifecycle advertises revision eighteen")
  T.eq(current.nativePartyRevision, 1, "player lifecycle does not change the party codec")
  local older = Copy(current)
  older.nativeBattleRevision = 17
  T.eq(Handshake.checkCompat(current, older), "subset", "old ownership cannot admit lockstep")
  T.eq(Handshake.checkCompat(older, current), "subset", "old ownership mismatch is symmetric")
  for _, host in ipairs({ false, true }) do
    local state = setmetatable(
      { game = f.game, myHello = current, peerHello = older },
      { __index = require("src.link.LinkState") }
    )
    state:decideCompat("battle", host)
    T.eq(state.stage, "notice", "ownership mismatch stops actual link controller before battle setup")
  end
  local h = dofile("tests/native_sound/fixture.lua").install(".", false, f)
  h.clear()
  h.player(141, 1)
  local first = assert(Sound.playId(f.data, 141, { pan = -64 }))
  h.player(141, 2)
  local second = assert(Sound.playId(f.data, 141, { pan = -64 }))
  T.neq(first, second, "simultaneous players cannot rewind the same Source")
  T.eq(#h.active(), 2, "both actual native sources remain sounding")
  Sound.setVolumeLevel(2)
  T.eq(#h.volumes(), 2, "both independently owned voices receive the volume update")
  for _, volume in ipairs(h.volumes()) do
    T.check(math.abs(volume - 0.8 * 2 / 7) < 1e-12, "volume update reaches each owned voice")
  end
  Sound.invalidate("OWNED_NATIVE_141")
  T.eq(#h.active(), 0, "name invalidation stops original and extra player voices")
  T.eq(Sound.isSePlaying(f.data, 141), false, "invalidation releases player ownership")
  local rebuilt = assert(Sound.playId(f.data, 141, { pan = -64 }))
  T.neq(rebuilt, first, "invalidated PCM sources are rebuilt")
  T.check(Sound.isPlaying("OWNED_NATIVE_141"), "generic named polling observes native control variants")
  Sound.stop("OWNED_NATIVE_141")
  T.eq(#h.active(), 0, "generic named stop reaches native control variants")
  local beforeSuspend = assert(Sound.playId(f.data, 141, { pan = -64 }))
  Sound.suspend()
  T.eq(#h.active(), 0, "suspension releases sustained native effects")
  T.eq(Sound.isSePlaying(f.data), false, "suspended native queries are silent")
  T.eq(Sound.playId(f.data, 141, { pan = -64 }), nil, "suspended session cannot build or restart effects")
  Sound.resume()
  T.neq(
    assert(Sound.playId(f.data, 141, { pan = -64 })),
    beforeSuspend,
    "resume replaces device-bound native sources"
  )
  h.clear()
  h.player(141, 1)
  h.player(164, 1)
  Sound.playId(f.data, 141, { pan = -64 })
  local originalNewSource = love.audio.newSource
  love.audio.newSource = function()
    error("owned device-loss test")
  end
  local failed = Sound.playId(f.data, 164, { pan = 63 })
  love.audio.newSource = originalNewSource
  T.eq(failed, nil, "native device failure is contained")
  T.eq(#h.active(), 0, "native replacement releases its prior player before a new source build")
  Sound.invalidate()
  V.set("red")
  f.data.audio.sfx.LEGACY_ONE, f.data.audio.sfx.LEGACY_TWO =
    { file = "owned-effect-141.wav" }, { file = "owned-effect-164.wav" }
  Sound.play(f.data, "LEGACY_ONE")
  Sound.play(f.data, "LEGACY_TWO")
  T.eq(#h.active(), 2, "legacy independent effects retain their existing overlap")
  h.clear()
  h.close()
  f.close()
  Sound.setVolumeLevel(7)
end
T.finish("native M4A source ownership, queries, overrides and session cleanup")
