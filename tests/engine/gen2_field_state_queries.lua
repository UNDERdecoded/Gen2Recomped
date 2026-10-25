package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Compat = require("src.core.ModCompat")
Compat.install()
local Fields = require("src.world.gen2.FieldMoves")
local State = require("src.world.Gen2PlayerState")
T.eq(Fields, require("src.world.Gen2FieldMoves"), "both module names share the native query table")
T.eq(Fields.isBiking, State.isBiking, "bike predicate is the actual native state predicate")
T.eq(Fields.isSurfing, State.isSurfing, "surf predicate is the actual native state predicate")
for _, key in ipairs({"PLAYER_NORMAL", "PLAYER_BIKE", "PLAYER_SURF", "PLAYER_SURF_PIKA"}) do
  T.eq(Fields[key], State[key], "native movement constant: " .. key)
end
for _, state in ipairs({"normal", "bike", "surf", "surf_pika", "unknown", 0, false}) do
  T.eq(Fields.isBiking(state), state == "bike", "only native bike state is biking")
  T.eq(Fields.isSurfing(state), state == "surf" or state == "surf_pika", "both actual surf variants are surfing")
end
T.eq(Fields.isBiking(nil), false, "teardown does not invent a bike state")
T.eq(Fields.isSurfing(nil), false, "teardown does not invent a surf state")
-- Querying the derived state must follow a script's flag changes without a
-- cached mode byte, and must not perform any native action itself.
local player, save = {surfing = false}, {onBike = false}
T.eq(Fields.isBiking(State.read(player, save)), false, "standing player walks")
save.onBike = true
T.eq(Fields.isBiking(State.read(player, save)), true, "native script mounts immediately observable")
player.surfing, player.surfingPikachu = true, true
T.eq(Fields.isSurfing(State.read(player, save)), true, "actual Pikachu surf overrides stale bike flag")
T.eq(save.onBike, true, "observing state does not edit save flags")
T.eq(Fields.fromMenu, nil, "no invented legacy action protocol")
T.eq(Fields.flyPoints, nil, "no invented visited-destination or fly-picker protocol")
T.eq(Fields.encounterTable, nil, "no guessed permission table for imported collision classes")
T.finish("native Gen2 field-state queries")
