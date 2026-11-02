-- BLACK AND WHITE'S SCRIPTS, IN THE POOL THE GEN 4 SCRIPT ENGINE RUNS.
--
-- Gen5ScriptOps knows how wide every command is; this names the commands whose
-- meaning the cartridge's own scripts make plain, in Platinum's words, so
-- Gen4ScriptVM lowers them unchanged -- the same move HGSS's aliases make.
--
-- WHAT IDENTIFIES EACH. A Striaton conversation decodes as 2E, A6 0547, 74,
-- 3D 00 04 0009 0000 0000, 32, 3E, 30, 2F, 02 -- the Gen 4 order of lock all,
-- play sound, face player, message, wait for a press, close, (pause), release
-- all, end -- and entry 9 of the zone's story bank is that NPC's line. The
-- control flow is fixed by the widths and the jump targets themselves (Call
-- and Jump a u32 that lands on an instruction, Return and End nothing). The
-- rest:
--
--   0x23 / 0x24  a flag id (u16)            set / clear flag
--   0x28         var (0x8000+), value       set var to value
--   0x3C         like 0x3D with the message id at operand 3 and two more
--   0x64 / 0x65  object + u32 to a movement list / no operands
--                apply / wait movement. All 4,129 lists end at 0xFE in Gen 4's
--                { u16 action, u16 count } form, from the byte after the
--                8-byte instruction, and the object ids are Gen 4's (0xFF the
--                player at 1,060 sites, else the NPC's local id), so
--                Gen4Movement decodes them unchanged
--
-- BW's conditionals are STACK-based (push a constant / a var / a flag,
-- compare, then 0x1F jumps on the result); `rewriteStack` turns each one into
-- Platinum's compare + gotoif chains (see THE STACK FORM below).

local Ops = require("src.import.Gen5ScriptOps")
local Movement = require("src.import.Gen4Movement")

local L = {}

-- { name, spec, order }: spec splits the operands (b = u8, w = u16, d = u32);
-- order picks which become the Platinum command's arguments
L.ALIASES = {
  [0x02] = { "end", "" }, [0x05] = { "return", "" },
  [0x04] = { "call", "d" }, [0x1E] = { "goto", "d" },
  [0x2E] = { "lockall", "" }, [0x2F] = { "releaseall", "" }, [0x30] = { "noop", "" },
  [0x74] = { "faceplayer", "" },
  [0x32] = { "waitabpress", "" }, [0x3E] = { "closemessage", "" }, [0x3F] = { "closemessage", "" },
  [0x3D] = { "message", "bbwww", { 3 } }, [0x3C] = { "message", "bbwwww", { 3 } },
  -- 0x0CC <dest>: the running script's text bank into a var (ov10
  -- 0x0215AADC: *var = ctx+0x18, the bank 0x0215A760 loaded) -- what an
  -- NPC hands the shared item-gift script (2800) so it speaks their lines
  [0x0CC] = { "bwstorecurrentbank", "w" },
  [0xA6] = { "playse", "w" },
  [0x23] = { "setflag", "w" }, [0x24] = { "clearflag", "w" },
  -- 0x25 <flag, dest>: the flag's state into a var (the handler reads the
  -- flag through the same event-flag routine 0x23 / 0x24 write it with);
  -- 0x06 <value> reads a value and does nothing with it
  [0x25] = { "bwflagtovar", "ww" }, [0x06] = { "noop", "w" },
  [0x28] = { "setvarfromvalue", "ww" },
  [0x64] = { "applymovement", "wd" }, [0x65] = { "waitmovement", "" },
  -- read off their handlers (overlay 10): 0x09 pushes a var's value, 0x0A
  -- pops into a var, 0x2A is `var = var-or-value`, 0x1C runs the common
  -- script <id> and waits on it (one u16, see Gen5ScriptOps)
  -- 0x29 copies var to var, 0x26 / 0x27 add / subtract a var-or-value, 0x03
  -- stores its u16 in the context's counter and pauses until it reaches 0
  [0x2A] = { "setvar", "ww" }, [0x29] = { "setvarfromvar", "ww" },
  [0x26] = { "addvar", "ww" }, [0x27] = { "subvar", "ww" }, [0x03] = { "waittime", "w" },
  -- from the scripts around them, with the handlers agreeing on the operands:
  --   0x6C <object>  removes it (run in batches just before their hide flags)
  --   0x6D <object, x, height, z, dir>  places it -- Platinum's setposition,
  --        the same five var-or-values in the same order
  --   0x4C <slot>    the player's name into a string slot, before a message
  --   0x34 <message, style> / 0x36  a message box and its close
  --        (`34 0027, 32, 36, releaseall`); the id may be a var (0x804D)
  --   0x47 <var>     the yes/no box after a question, 0 for YES as in
  --        Platinum: Z054's masseuse runs `if (var == 0) { massage }` and
  --        jumps past it to "Oh, I see. Please see me if you change your mind."
  [0x6C] = { "removeobject", "w" }, [0x6D] = { "setposition", "wwwww" },
  [0x4C] = { "bufferplayername", "b" },
  [0x34] = { "message", "ww", { 1 } }, [0x36] = { "closemessage", "" },
  [0x47] = { "showyesnomenu", "w" },
  --   0xA9 <sound> / 0xAA  a jingle and the wait for it (the masseuse plays
  --        one between "Let me get started" and "All done")
  --   0xB4         waits for the 0xB3 fade (see rewriteCompound)
  --   0xCB <var, bound>  var = random below bound: the handler calls the
  --        DS's 64-bit LCG (0x020056EC), which scales its high word by bound
  [0xA9] = { "playfanfare", "w" }, [0xAA] = { "waitfanfare", "" },
  [0xB4] = { "waitfadescreen", "" }, [0xCB] = { "getrandom", "ww" },
  --   0x43 <message, style> / 0x44  a sign-style box: the handler prints and
  --        pauses until it is dismissed (`2E A6 43 44 30 2F 02` is a whole
  --        talk), so it is Platinum's message + waitabpress; 0x44 closes it
  --   0xA8         waits for the sound just played (`A6 069D, A8, A6 069B, A8`)
  [0x43] = { "message", "ww", { 1 } }, [0x44] = { "closemessage", "" },
  [0xA8] = { "waitse", "" },
  --   0x85 <trainer, second trainer, u16>  a trainer battle (the trainer may
  --        be a var: `85 0x8022 0 0`). Then `8D var; if (var == 1) { 8E }
  --        else { 8C }`: 0x8D writes 1 when the battle was WON, 0x8E is the
  --        return to the field and 0x8C the black-out. The bedroom battle
  --        settles it: Bianca's may be lost, so it runs 0x8E unconditionally
  --        and then `8D var; if (var == 1)` says "you're gonna be an awesome
  --        Trainer" (bank 430 #37) and otherwise "I won before even
  --        realizing" (#38). (An earlier reading had all three backwards,
  --        which the gym's own shape cannot tell apart.)
  --   0xD5 <var, badge>  var = bit `badge` of the save's badge mask (the gym
  --        asks for badge 0 before its leader's challenge)
  [0x85] = { "starttrainerbattle", "ww" },
  [0x8E] = { "returntofield", "" }, [0x8C] = { "blackoutfrombattle", "" },
  --   0xD6 <badge>  sets that bit of the badge mask (and stamps the time);
  --   0xE1 <var>    counts the mask's bits into var
  [0xD5] = { "checkbadgeacquired", "ww", { 2, 1 } },
  [0xD6] = { "givebadge", "w" }, [0xE1] = { "countbadgesacquired", "w" },
  --   0x38 / 0x4A <message, style byte>  two more message boxes (0x38's
  --        handler is a tail-jump stub, see Gen5ScriptOps); 0x39 closes them
  --        (`38 0025 02, 32, 39`) and 0x4B waits on the box like 0x32
  --   0x6E <var>    the player's facing, tested for 0..3 straight after
  [0x38] = { "message", "wb", { 1 } }, [0x4A] = { "message", "wb", { 1 } },
  [0x39] = { "closemessage", "" }, [0x4B] = { "waitabpress", "" },
  [0x6E] = { "getplayerdir", "w" },
  -- THE CUTSCENE CAMERA runs on Platinum's: `addfreecamera` stands an
  -- invisible body the camera follows, so a scene looks where BW's does
  -- under whichever CAM TILT the player picked (cartridge, an angle, first
  -- or third person). The sequence is
  --   0x13F, 0x141 (start, lock)  0x143 (move, see rewriteCompound)
  --   0x145 (wait)  0x144 / 0x147 <frames> (back to the player)
  --   0x142, 0x140 (unlock, end)
  [0x13F] = { "noop", "" }, [0x141] = { "noop", "" }, [0x142] = { "noop", "" },
  [0x145] = { "noop", "" },
  [0x144] = { "restorecamera", "w", {} }, [0x147] = { "restorecamera", "w", {} },
  [0x140] = { "restorecamera", "" },
  [0x1C] = { "callcommonscript", "w" },
  -- the direct compare and the jump on it: 0x19 var, value then 0x1F with a
  -- real condition (1 = equal in all 109 such jumps) -- Platinum's pair
  [0x19] = { "comparevartovalue", "ww" },
  [0x1F] = { "gotoif", "bd" },
  -- THE GIFT BOX (the bedroom, member 782):
  --   0x153 <var>  the starter app; the script reads 0 / 1 / 2 back and
  --        turns it into 495 / 498 / 501 itself
  --   0x10C <dest, species, item, level>  the gift (`10C 8010 8021 0 5`
  --        after the fanfare and "{VAR1} chose {VAR2}!") -- Platinum's
  --        givepokemon <species, level, item, dest>
  --   0x057 <slot, species>  a tail-jump stub into the name buffer: `057
  --        01 01EF` before "chose {VAR2}!", `057 01 01F5` before Cheren's
  --        "I wanted {VAR2} from the start"
  --   0x1AE / 0x14B before the app and 0x14A / 0x1AF after it bracket it
  --        with the field's fade; 0x21C <u8, value> follows the answer
  [0x153] = { "bwchoosestarter", "w" },
  [0x10C] = { "givepokemon", "wwww", { 2, 4, 3, 1 } },
  [0x057] = { "bufferspeciesnamefromvar", "bw" },
  [0x1AE] = { "noop", "" }, [0x1AF] = { "noop", "" },
  [0x14A] = { "noop", "" }, [0x14B] = { "noop", "" },
  [0x21C] = { "bwpasserbyanswer", "ww" },
  -- AFTER THE BEDROOM BATTLES:
  --   0x101 <dest, slot>  1 when the slot's HP is full or it is an Egg
  --        (GetMonData 0xA0 against 0xA1, then 0x4C) -- before Cheren's
  --        "you won without your Pokemon's losing any energy"
  --   0x104  heals the party (party from the save, straight into the heal):
  --        right after "Cheren healed {VAR1}'s Pokemon!"
  --   0x053 / 0x054 <slot, party index>  byte then value like 0x057: a
  --        party Pokemon's species name / its nickname into a buffer (two
  --        neighbouring buffer routines; 0x054 is what Juniper's "Are you OK
  --        with the nickname {VAR1}?" prints)
  --   0x127 <handle, u16, u16, u16> / 0x129 <handle, u16> / 0x12A <handle> /
  --        0x128 <handle>  bracket the battle's return with an effect on a
  --        handle var (0x8022); the scene reads nothing back from them
  [0x101] = { "bwmonhpfull", "ww" },
  [0x104] = { "healparty", "" },
  [0x053] = { "bufferpartymonspecies", "bw" }, [0x054] = { "bufferpartymonnickname", "bw" },
  -- (READ FROM CODE since: they are the building animations, ov21
  -- 0x021B2D34.. -- src/world/Gen5BuildingAnim.lua)
  [0x127] = { "bwbuildinginstance", "wwww" }, [0x129] = { "bwbuildingplay", "ww" },
  [0x12A] = { "bwbuildingwait", "w" }, [0x128] = { "bwbuildingfree", "w" },
  -- THE BAG, in Platinum's order and shapes (consecutive handlers in overlay
  -- 10, each <item, quantity, dest> into one bag routine): 0xB5 adds (the
  -- give-item script, member 862, runs it before the fanfare), 0xB6 takes,
  -- 0xB7 asks whether it fits (the same script's `if (dest == 0)` bag-full
  -- branch), 0xB8 asks whether there are that many; 0xB9 <item, dest> the
  -- count
  --   0x04E <slot, item, quantity, u8>  the item's name into a buffer (the
  --        plural when quantity > 1), before "obtained"
  [0xB5] = { "additem", "www" }, [0xB6] = { "removeitem", "www" },
  [0xB7] = { "canfititem", "www" }, [0xB8] = { "checkitem", "www" },
  [0xB9] = { "getitemquantity", "ww" },
  [0x04E] = { "bufferitemname", "bwwb", { 1, 2 } },
  --   0xBB <item, dest>  the item's parameter 5, its pocket (0..4, see
  --        Gen5Data's bwPocket); the give-item script picks its jingle
  --        and its "put the ... in the ... Case" line on it
  --   0x052 <slot, pocket>  the pocket's name (system bank 55)
  [0xBB] = { "getitempocket", "ww" },
  [0x052] = { "bufferpocketname", "bw" },
  -- JUNIPER'S NICKNAME LOOP (the lab, member 792):
  --   0x105 <dest, slot, u16>  the naming screen for that party Pokemon --
  --        Platinum's openpokemonnamingscreen <slot, dest>
  --   0x110 <dest, slot, u16>  1 when it now carries a nickname; on 1 the
  --        script buffers it (0x054) and asks "Are you OK with the nickname
  --        {VAR1}?", and a NO goes round again
  --   0x1AD  the fade back in after the screen (0x1AE's pair)
  --   0x19F <u16>  run with no badges, between `setflag 0x962` (the
  --        Pokedex) and "obtained the Pokedex!"; nothing reads it back
  [0x105] = { "openpokemonnamingscreen", "www", { 2, 1 } },
  [0x110] = { "bwmonhasnickname", "www" },
  [0x1AD] = { "noop", "" }, [0x19F] = { "noop", "w" },
  -- ROUTE 1 (member 634): 0x17D is Juniper's catching demonstration, between
  -- "I'll show you how to catch a Pokemon" and "Did you see that, just
  -- now?" -- its routine builds a level 7 Minccino (Pound, Growl) against a
  -- wild level 2 Patrat (Tackle, Leer) and the handler pauses the script on
  -- it. 0x179 starts a field task after it that reads nothing back.
  [0x17D] = { "bwcatchingtutorial", "" }, [0x179] = { "noop", "" },
  -- ACCUMULA (member 794): 0x0BE <zone, x, y, facing>, four literals, is a
  -- warp -- Juniper's `0BE 398 7 19 0` takes the player into the Pokemon
  -- Center for her tour. Platinum's warp is <header, ?, x, z, facing>, so
  -- the zone fills the unused slot too. (0x127 .. 0x12A above are the door
  -- opening: `127 handle, 1, 796, 657` is the Center's door, matrix tile
  -- (28, 17) of the town.)
  [0x0BE] = { "warp", "wwww", { 1, 1, 2, 3, 4 } },
  -- 0x0C2: the same four literals with another transition (Fennel's "follow
  -- me" outside Striaton's gym: `0C2 9 7 10 0`, into her lab)
  [0x0C2] = { "warp", "wwww", { 1, 1, 2, 3, 4 } },
  -- THE NURSE (shared band 2100, member 855, every Pokemon Center):
  --   0x0CE <var>  the Trainer Card level (see 0x0CD below: the time of
  --        day that picks "Good morning!" or "Hello" is 0x0CD)
  --   0x0D0 <month, day> today, 0x0D4 <month, day> the DS profile's
  --        birthday: equal, and she asks "Hey! Is today your birthday?"
  --        (bank 346 #3). Unread, both were 0 = 0 and she asked every time
  --   0x100 <var>  Pokerus in the party (then `if (var == 1 && !flag 0x65)`
  --        prints #12, "may be infected with the Pokerus")
  --   0x075 <u16> / 0x23A <u16, u16> / 0x103 <var, u16> / 0x12F <var>  her
  --        bow, a record counter and the healing machine's balls -- nothing
  --        reads them back (0x103's var only feeds 0x12F)
  [0x0CE] = { "bwcardlevel", "w" },
  [0x0D0] = { "bwgetdate", "ww" }, [0x0D4] = { "bwgetbirthday", "ww" },
  [0x100] = { "checkpartypokerus", "w" },
  [0x075] = { "noop", "w" }, [0x23A] = { "noop", "ww" },
  -- 0x12F <var>: the healing machine itself -- the nurse's subroutine (member
  -- 855 @817) counts the party into the var with 0x103, runs 0x12F on it,
  -- then heals (0x104). It is Platinum's playpokecenterhealinganimation:
  -- the balls going in one by one and the Pokemon Center jingle.
  [0x103] = { "partycountnotegg", "ww", { 1 } },
  [0x12F] = { "playpokecenterhealinganimation", "w" },
  -- THE FLOATING WINDOWS: 0x03A <message, x, y, window> prints a line in a
  -- small window of its own at a tile position -- the crowd's murmurs
  -- around Ghetsis (`03A 000A 20 10 1`, `03A 000B 22 15 2`, then a wait for
  -- A) -- and 0x03B <window> takes that window down. Shown here in the
  -- ordinary box; WHERE it floats is not carried.
  [0x03A] = { "message", "wwww", { 1 } }, [0x03B] = { "noop", "w" },
  -- ROUTE 2 (member 640): Mom's Xtransceiver call. 0x0E3 sets a system flag
  -- from a constant, with no operands, between "I have another present for
  -- you" and "received a pair of Running Shoes!" -- Platinum's
  -- giverunningshoes
  [0x0E3] = { "giverunningshoes", "" },
  -- 0x068 <x var, z var>: the player's MATRIX position -- Striaton's guard
  -- runs `068 8020 8021; if (8020 == 750)`, 750 being the town's origin 736
  -- plus the trigger's first column -- Platinum's getplayermappos
  -- 0x0E0 <var>: the version id, the handler's own constant (21 in Black);
  -- scripts branch `if (var == 21)`
  [0x068] = { "getplayermappos", "ww" },
  [0x0E0] = { "bwgetversion", "w" },
  -- THE IN-GAME TRADES (src/import/Gen5Trades.lua, handlers in ov21):
  --   0x1BF <dest, trade, slot>  0 ok / 1 an Egg / 2 not the species asked
  --         for / 3 not the gender asked for (0x021B647C)
  --   0x1BE <trade, slot>        build theirs, play the demo, swap in place
  --   0x120 <slot, index>        the Pokemon given away, kept in the save for
  --         the NPC's later battle (Nacrene 0, Driftveil 1)
  [0x1BF] = { "bwnpctradecheck", "www" }, [0x1BE] = { "bwnpctrade", "ww" },
  [0x120] = { "bwkeeptradedmon", "ww" },
  -- 0x056 <slot, type>: a type's name into a buffer, byte first like 0x057 --
  -- the Striaton leaders' "the partner you first chose was {VAR1} type"
  [0x056] = { "buffertypename", "bw" },
  -- 0x04D / 0x050 <slot, item>: the item's name and the move a machine
  -- carries -- the gym's TM gift runs `4D 0 410; 50 1 410` before "{VAR1}
  -- contains Work Up". 0x04D is a stub into the shared byte-then-value
  -- buffer routine (Gen5ScriptOps' resolve)
  [0x04D] = { "bufferitemname", "bw" }, [0x050] = { "buffertmhmmovename", "bw" },
  -- 0x04F <slot, item>: a machine's name ("HM01") before "obtained {VAR2}
  -- {VAR3}" -- Fennel's Cut; the same stub shape as 0x04D
  [0x04F] = { "bufferitemname", "bw" },
  -- 0x116 <dest, move>: the first party slot knowing that move, 6 for none --
  -- the Cut tree's shared script (band 10000 #4) runs `116 8010 15; if
  -- (8010 == 6) { "This tree looks like it can be cut down!" }` --
  -- Platinum's findpartyslotwithmove
  [0x116] = { "findpartyslotwithmove", "ww" },
  -- 0x069 <x, y, dir, object, sprite, script>: a TEMPORARY object made on the
  -- spot (Castelia's gym door: Cheren as 0xFB, removed by 0x6C, then 0xFB
  -- again as Burgh, sprite 0x57); 0x048 <style, male, female, object, ...>:
  -- the message by the player's gender (Burgh's "your name is..." 3 / 4)
  [0x069] = { "bwspawnobject", "wwwwww" },
  [0x048] = { "gendermsgbox", "bbwwwww", { 3, 4 } },
  -- Castelia Gym (overlay 38): 0x18C <n> is switch n's press (and its saved
  -- word), 0x18D <n> a press that may open a wall, 0x18F <eight vars> lays
  -- the walls out on entry (overlay 37). Lowered as nothing: the switch
  -- scripts set their own vars, and src/world/Gen5CasteliaGym.lua opens the
  -- walls from them and keeps the saved words.
  [0x18C] = { "noop", "w" }, [0x18F] = { "noop", "wwwwwwww" },
  -- (0x18D / 0x18E <gate var>: the same overlay's other two animations)
  [0x18D] = { "noop", "w" }, [0x18E] = { "noop", "w" },
  -- 0x11E <badge>: the party recorded against the badge just won (its
  -- handler copies six slots) -- the trainer card's history, nothing the
  -- story reads; 0x01D closes a common script's work just before its end
  [0x11E] = { "bwbadgeteam", "w" }, [0x01D] = { "noop", "" },
  -- 0x098 <sequence> / 0x09E: a cutscene's own music and the return to the
  -- map's (Z038's Plasma theft: `98 0443` as Iris runs in, `9E` once she
  -- has gone). READ FROM CODE (ov21 0x021AEDE0 / 0x021AEFD8): 0x098 reads a
  -- u16 and parks the script on arm9 0x02029984's task (sound queue 2, the
  -- old BGM out in 6 frames, then 7 <sequence>); 0x09E asks 0x02029DF4 for
  -- the current zone's BGM and fades to it (0x020298A0, 0x5A / 0x3C). The
  -- ids are the SDAT's own sequence numbers (0x443 SEQ_BGM_E_PLASMA), the
  -- same numbers the zone headers' music uses, so they play as they are
  -- (src/script/Gen5MusicCommands.lua)
  [0x098] = { "bweventmusic", "w" }, [0x09E] = { "bwmapmusic", "" },
  -- 0x06B <object>: addobject, 0x6C's partner -- Z031 clears flag 797 and
  -- then 6B's objects 6 and 7, Iris and Bianca, who carry that flag (139
  -- sites)
  [0x06B] = { "addobject", "w" },
  -- 0x049 <style, black, white, object, ...>: the line by VERSION, as 0x048
  -- is by gender -- the Sages' hideout (Z056) has Iris name "the white
  -- Dragon-type Pokemon" (#4) in Black and "the black" (#5) in White;
  -- 0x248 <sequence, frames>: a cutscene's music with a fade (see 0x098)
  [0x049] = { "bwversionmsgbox", "bbwwwww", { 3, 4 } },
  [0x248] = { "noop", "ww" },
  -- 0x0AB <species, form> / 0x0AC: a cry and the wait for it (Munna, 517,
  -- when Iris hands it back in the Sages' hideout)
  [0x0AB] = { "playcry", "ww" }, [0x0AC] = { "waitcry", "" },
  -- MENUS AND CASTELIA'S ELEVATORS (band 10405, bank 261: "Which floor
  -- would you like to go to?"):
  --   0xB2 <x, y, cursor, B cancels, result var>  opens a menu (7 bytes, see
  --        Gen5ScriptOps), 0xAF <text, -, value> adds a line, 0xB0 shows it
  --   0x1CB <u32>  the building's floor table, an offset from the script
  --        pointer into the script file itself: 10-byte records <label,
  --        zone, x, y, z> to a 0xFFFF label (read at link time, `floors`)
  --   0x1CC  every floor but this one into the menu; 0x1CD <var> picks
  --        the chosen floor; 0xA7 rides there; 0x1AE / 0x1AD / 0x1B1 are
  --        the doors' and the car's animations and their wait
  [0x0B2] = { "bwmenuopen", "bbwbw" }, [0x0AF] = { "addmenuentry", "www", { 1, 3 } },
  [0x0B0] = { "showmenu", "" },
  -- THE POKE MART COUNTER (shared script 871, src/script/Gen5MartCommands):
  -- 0x149 <var shop, var result> the BUY list (shop 255 = the regular
  -- counter by badges, else a second clerk's specialty), 0x14E <u16, var,
  -- var> the Bag in sell mode
  [0x149] = { "bwpokemart", "ww" }, [0x14E] = { "bwmartsell", "www" },
  -- THE PC (behaviour 0xD6 -> shared script 10090, member 868): 0x0B1 shows
  -- the menu 0x0B2 / 0x0AF built (no operands -- the list form of 0x0B0),
  -- and 0x14F <var, mode> opens the boxes in the mode the second menu
  -- picked (0 deposit, 1 withdraw, 2 move, 3 items, 4 the Battle Box)
  [0x0B1] = { "showmenu", "" }, [0x14F] = { "bwopenstorage", "ww" },
  [0x1CB] = { "bwelevator", "d" }, [0x1CC] = { "bwelevatorfloors", "" },
  [0x1CD] = { "bwelevatorpick", "w" }, [0x0A7] = { "bwelevatorwarp", "" },
  [0x1AE] = { "noop", "" }, [0x1AD] = { "noop", "" }, [0x1B1] = { "noop", "" },
  -- 0x155 <call>: the Xtransceiver call itself (overlay 174, the call's
  -- people and lines in /a/1/3/1 -- src/script/Gen5XtransceiverCommands.lua),
  -- between 0x14B and 0x14A; calls 1..6
  [0x155] = { "bwxtcall", "w" },
  -- 0x13D / 0x13E: the bracket round a long arrival scene (Nimbasa's
  -- Bianca and her father: 13D first, 13E just before the release) --
  -- nothing in between reads what they set
  [0x13D] = { "noop", "" }, [0x13E] = { "noop", "" },
  -- 0x240 <item>: the item-gift script (common 0xAF5) runs it for a KEY
  -- item only, before buffering the name -- Nimbasa's Bicycle (450). The
  -- bag already holds the item; this is the cartridge's own bookkeeping
  [0x240] = { "noop", "w" },
  -- NIMBASA'S PARK VISITOR (Z064's map entry): 0x0D2 <var> the season
  -- (0 spring .. 3 winter), 0x02B <var, value> var *= value, and 0x232
  -- <index, dest> dest = a sixteen-sprite table (season x 2 + badges) --
  -- the sprite var 0x4020 that object 162 draws as
  [0x0D2] = { "bwseason", "w" }, [0x02B] = { "bwmulvar", "ww" },
  [0x232] = { "bwparkvisitor", "ww" },
  -- the park's chase (Z064's trigger): 0x078 <var> is asked first and a 1
  -- answered with 0x075 1 -- read as "is the player on the bicycle", which
  -- this port's scenes start off it, so 0 (setvar); 0x253 <a, b> a screen
  -- effect, 0x154 <caller, ?> the Xtransceiver picture's other form, 0x254
  -- <n> and 0x1D3 <three> / 0x1D4 a picture window round one line --
  -- presentation only
  [0x078] = { "setvar", "w" }, [0x253] = { "noop", "ww" }, [0x154] = { "noop", "ww" },
  [0x254] = { "noop", "w" },
  -- ...except 0x1D3 / 0x1D4 / 0x1D5, N's full-screen portrait round his lines
  -- (READ FROM CODE, ov10 0x02164910 / 0x02164994 / 0x02164978 -> overlay 82;
  -- src/world/Gen5NPortrait.lua): <mode, u16, close>, its close, "talk"
  [0x1D3] = { "bwnportraitopen", "www" }, [0x1D4] = { "bwnportraitclose", "" },
  [0x1D5] = { "bwnportraittalk", "" },
  -- NIMBASA GYM: 0x17F <a, b> records two trainer flags in the gym's save
  -- block (its overlay only stores them); 0x180 <n> turns coaster track n's
  -- switch over (Gen5Field's gen5Coaster, ridden from OverworldController)
  [0x17F] = { "noop", "ww" }, [0x180] = { "bwcoasterswitch", "w" },
  -- 0x022 <var>: byte +5 of a save sub-block (0x02012B38's) into var -- 4
  -- sites; Nimbasa Gym's entry asks it and runs 0x260 only on a 1. Not
  -- identified, so it reads as a fresh save's 0
  [0x022] = { "setvar", "w" },
  -- 0x09F <sequence>: another cutscene music start (Route 5's Elesa scene
  -- opens with `9F 043F`; Pinwheel's Plasma grunts' `9F 0467`,
  -- SEQ_BGM_EYE_PLASMA). READ FROM CODE (ov21 0x021AF0BC): a var-or-value,
  -- then arm9 0x02029AF4's task -- queue 3 (the old BGM paused, 6 frames)
  -- and 7 <sequence>, where 0x098 stops it (queue 2)
  [0x09F] = { "bweventmusic", "w" },
  -- 0x0A1 <frames> / 0x0A2 <u16, frames>: READ FROM CODE (ov21 0x021AF0F8 /
  -- 0x021AF130) the field BGM paused over <frames> (arm9 0x020295A4, queue
  -- 3) and resumed over the second operand's (0x02029620, queue 4) -- the
  -- Musical's dress-up (`A1 0006` ... `A2 0000 003C`) and N's Castle
  -- 0x25F: READ FROM CODE (ov21 0x021AF1B0) clears bit 2 of the sound
  -- state that 0x098 / 0x09E set and clear -- the bit that stops the
  -- field's ambient sound loops (arm9 0x02028BA0 stops the handles at
  -- +0xAC when it is first set); this port plays no such loops
  [0x0A1] = { "bwpausemusic", "w" }, [0x0A2] = { "bwresumemusic", "ww" },
  [0x25F] = { "noop", "" },
  -- 0x1EA <sign, x, level, z>: READ FROM CODE (ov10 0x0215B214 ->
  -- 0x02162A74) a sign record of the loaded zone moved to a new cell --
  -- Nacrene Gym's bookshelves following the bookcase
  -- (src/script/Gen5FieldEventCommands.lua)
  [0x1EA] = { "bwsetsignpos", "wwww" },
  -- 0x0C4 <zone, x, height, z, dir>: the warp with an elevation word --
  -- Driftveil Gym's lobby lift drops the player into Clay's mine (zone 97,
  -- `C4 0061 0011 0032 0019 0000`: tile (17, 25), 50 units up). The height
  -- is the arrival's; the map's own ground takes it here
  [0x0C4] = { "warp", "wwwww", { 1, 1, 2, 4, 5 } },
  -- the lift round it: 0x1B6 starts it, 0x192 <n> runs it
  [0x1B6] = { "noop", "" }, [0x192] = { "noop", "w" },
  -- 0x021 <entry>: THE SCRIPT TO RUN WHEN THE NEXT WARP LANDS -- entry n of
  -- the destination zone's own file.  All 43 uses stand right before a warp
  -- (or the lift ride that warps), and the entry is each time the scene the
  -- story continues with: Dragonspiral's summit queues 4 and warps to zone
  -- 205, whose entry 4 is Alder and Cedric's talk at the tower's foot (it
  -- sets 0x409D); Relic Castle's floor queues 5 for zone 158, whose entry 5
  -- sets 0x4092 = 6, the Nacrene museum's cue.  Read as a lift's exit note
  -- before, and both scenes never played.
  [0x021] = { "bwqueueentry", "w" },
  -- RELIC CASTLE'S QUICKSAND (the pits' coord scripts, members 320..328 and
  -- 370): 0x0C1 <zone, x, z> is the fall -- a warp with no facing, only the
  -- castle's pits use it; and 0x0D8 <n, var> stores whether condition n of
  -- a ten-row table holds (handler 0x215AEB9 -> 0x2159F54; the table at
  -- 0x2170FB0 in overlay 10, rows { ?, n, var 0x4031 + n, value }) -- on
  -- B3F's pit it picks between the two landing tiles, in the player's room
  -- between the Wii's two lines
  [0x0C1] = { "warp", "www", { 1, 1, 2, 3 } },
  -- THE EVENT POKEMON CHECKS: 0x220 <species, 0, slotVar, resultVar> asks
  -- whether a distributed (fateful-encounter) Pokemon of that species is in
  -- the party -- Castelia's Zorua scene asks for Celebi (member 94), Lostlorn
  -- Forest's Zoroark for Entei, Raikou and Suicune (member 770)
  [0x220] = { "bwpartyhaseventmon", "wwww" },
  -- OPELUCID GYM (overlay 46, Gen5DragonGym): 0x196 lists the dragons'
  -- lines as the save says, 0x19A <statue, side> flips a switch, 0x199
  -- <statue> settles the head and its lines; 0x197 <statue, side> and 0x198
  -- <n> are the switch's and the player's animations
  -- THE ELITE FOUR'S LIFTS (zones 140-143, gimmick 0x2C): 0x1A2 <n>, run by
  -- the entry floor's platform trigger at (15, 25), starts overlay task n - 1
  -- that raises the platform into the member's floor above -- the rows
  -- between are solid and the upper floor stands 0x33 up. The overlay is
  -- not decoded; the ride is a lift up the player's column (Gen4Commands)
  [0x1A2] = { "bwe4lift", "w" },
  [0x196] = { "bwdragoninit", "" }, [0x19A] = { "bwdragonflip", "ww" },
  [0x199] = { "bwdragonsettle", "w" }, [0x197] = { "noop", "ww" }, [0x198] = { "noop", "w" },
  -- THE GYMS' ANIMATIONS (src/script/Gen5GymFxCommands.lua, drawn by
  -- src/world/Gen5GymFx.lua): 0x185 <n> Nacrene's bookcase, 0x187 / 0x189
  -- <switch> Striaton's floor switch down / up, 0x188 <row> its curtain --
  -- each parks the script until its animation ends
  [0x185] = { "bwgymop", "w" }, [0x187] = { "bwgymop", "w" }, [0x188] = { "bwgymop", "w" },
  [0x189] = { "bwgymop", "w" },
  [0x0D8] = { "bwcondition", "ww" },
  -- 0x121 <var, 5>: how many of the party can battle (not an egg, not
  -- fainted) -- the legendary's "able to battle" test in N's Castle (Z278,
  -- M0556 S1A78: none able and the dragon only stares), beside 0x103's count
  [0x121] = { "bwpartyable", "ww", { 1 } },
  -- 0x245 <mode, var>: N's Castle's dragon joining the party (Z278, M0556
  -- S187F): mode 0 answers whether the party has room, mode 1 adds the
  -- version's dragon -- Reshiram on Black, Zekrom on White, level 50 -- and
  -- a full party first sends one to the PC (S19BA)
  [0x245] = { "bwlegend", "ww" },
  -- THE SCRIPTED WILD BATTLES (17 of them -- N's Castle's dragon, the
  -- legendaries): 0x178 <species, level, flags var> starts it, 0x17B <var>
  -- answers 1 when the battle ended without a loss (caught, knocked out or
  -- fled -- N's Castle reads the catch only then), 0x17C <var> whether it got
  -- away uncaught (N's Castle sets 0x133 when it was caught and removes the
  -- dragon), and 0x17A <n> closes the battle's field effect. 0x013 <var,
  -- value> adds to a var -- the battle's flag word, 0x100 | 1 | 0x10.
  [0x178] = { "startwildbattle", "www", { 1, 2 } },
  [0x17B] = { "bwbattleok", "w" },
  [0x17C] = { "checkdidnotcapture", "w" },
  [0x17A] = { "noop", "w" },
  [0x013] = { "addvar", "ww" },
  -- 0x156 <kind>: THE GAME CLEAR. Kind 0 closes N's Castle (Z278, the last
  -- row before 0x40B6 = 6): the ending plays and the game goes on in the
  -- player's room; kind 1 is the Champion's room after Alder (Z145)
  [0x156] = { "bwgameclear", "w" },
  -- Clay's lifts: 0x190 <lift> moves lift n to its other height (the panel
  -- script flips the lift's flag 0x0A + n after), carrying the player when
  -- standing on it (Gen5DriftveilGym); 0x191 <n> / 0x1B5 the arrival lift
  [0x190] = { "bwliftmove", "w" }, [0x191] = { "noop", "w" }, [0x1B5] = { "noop", "" },
  -- 0x1EB <index, x, y, z>: four var-or-values into a save-block slot
  -- (0x02162708) -- Chargestone's mouth stores (107, 1, 337) there while
  -- 0x409A < 2, a stored position nothing on the way reads
  [0x1EB] = { "noop", "wwww" },
  -- CEDRIC JUNIPER'S POKEDEX CHECK (Mistralton): 0x0DF <mode, species, var>
  -- var = has the species been seen (Klink, 599), 0x0DD <mode, var> the
  -- seen count, 0x05C <slot, var, digits, ?> the count into a string slot
  -- (his "{CMD 0202 0} Pokemon"), 0x1D2 the upgrade -- form detection
  [0x0DF] = { "bwdexseen", "www", { 2, 3 } }, [0x0DD] = { "getlocaldexseencount", "ww", { 2 } },
  [0x05C] = { "buffernumber", "bwbb", { 1, 2 } }, [0x1D2] = { "turnonpokedexformdetection", "" },
  -- 0x07B <object, x, height, z>: 0x6D's placement without a facing --
  -- Twist Mountain's entrance moves Cheren (1) to (142, 206) mid-scene
  [0x07B] = { "bwplaceobject", "wwww" },
  -- THE PARTY, read by Cedric Juniper ("How is {VAR2}?") and Mistralton's
  -- scene: 0x10D <var, mode> the first Pokemon that is not an egg (mode 2
  -- at every site read), 0x0FC <var, slot> its friendship (70 and up is
  -- "really taken a shine to you"), 0x0FE <var, slot> its species
  -- ICIRRUS GYM: 0x195 <n> a ride along a gated rail track (Gen5Field's
  -- gen5RailTracks / gen5RailGates); 0x193 / 0x194 <group> the switches'
  -- animation, 0x077 the ride's preamble
  [0x195] = { "bwrailride", "w" }, [0x193] = { "noop", "w" }, [0x194] = { "noop", "w" },
  [0x077] = { "noop", "" },
  -- 0x0DA <a, b, c>: three var-or-values into a save record after a
  -- leader's win (Brycen's `DA 4 1 1`, 17 sites) -- bookkeeping nothing on
  -- the story's path reads back
  [0x0DA] = { "noop", "www" },
  -- 0x148 <eight> right after a sound (Dragonspiral's 1F: the tower
  -- shaking) and 0x1EC <five> in map-load callbacks (a model's set-up) --
  -- presentation only
  [0x148] = { "noop", "wwwwwwww" }, [0x1EC] = { "noop", "wwwww" },
  [0x10D] = { "getfirstnonegginparty", "ww", { 1 } },
  [0x0FC] = { "getpartymonfriendship", "ww", { 1, 2 } },
  [0x0FE] = { "getpartymonspecies", "ww", { 2, 1 } },
  -- THE SHARED TRAINER SCRIPT (band 3000, member 863, every trainer):
  --   0x084 <var>  the trainer's id (Platinum's gettrainerid)
  --   0x097 <trainer, dest>  beaten?   0x092 <trainer, dest>  healer / prize
  --   0x08A <trainer, dest>  the battle type, 1 for a double (2 triple, 3
  --        rotation; Platinum's double check answers only the first)
  --   0x103 <dest, u16>  the party's count, checked against the type's need
  --        (the nurse's machine reads it too)
  --   0x08B <trainer>  the encounter music
  --   0x088 <pre, post, notEnough>  which lines (Platinum's
  --        gettrainermessagetypes) and 0x087 <trainer, type, object> says one
  --        (printtrainerdialogue), from system bank 189
  --   0x066 <dest, object> / 0x073 <object, value>  the object's movement
  --        type, read to turn the trainer, and set back
  -- 0x086 <partner, foe, foe, u16>: a tag battle -- Wellspring Cave's
  -- `086 56 62 63 0` is Cheren (56) beside you against two grunts --
  -- Platinum's multibattle
  [0x086] = { "multibattle", "wwww", { 1, 2, 3 } },
  [0x084] = { "gettrainerid", "w" },
  --   0x095 / 0x096 <trainer>  set / clear its beaten flag (the event flag at
  --        a fixed base plus the id; 0x097 reads the same one) -- run after
  --        every trainer win
  [0x095] = { "settrainerflag", "w" }, [0x096] = { "cleartrainerflag", "w" },
  [0x097] = { "bwtrainerbeaten", "ww" }, [0x092] = { "bwtrainerafter", "ww" },
  [0x08A] = { "checkistrainerdoublebattle", "ww", { 2 } },
  -- 0x08B <trainer>: Platinum's playtrainerencounterbgm (READ FROM CODE,
  -- Black ov10 command table at file 0x1B4CC -> ov21 0x21AEC40): one
  -- var-or-value (0x2159B10), the trainer record's byte 1, its class
  -- (ARM9 0x202A230 field 1), looked up in ARM9 0x2029E20's { u16 class,
  -- u16 seq } rows at 0x020A75A8 (Gen4BattleMusic.eyes; a class it does not
  -- name gets 0x45A, SEQ_BGM_EYE_01), and handed to the field as a BGM-change
  -- event the script waits on (0x2029AF4 -> ov10 0x215897C). Twelve sites:
  -- member 863's talk path (`08B 8020`), eye paths (`8027` single, `8029`
  -- double, `802C` then `802D` -- the SECOND trainer's theme, after the first
  -- has spoken -- for two separate trainers), and scripted fights in members
  -- 126 (67, 69), 242 (274 x2), 642 (18 x2) and 658 (46).
  [0x08B] = { "playtrainerencounterbgm", "w" },
  [0x088] = { "gettrainermessagetypes", "www" },
  [0x087] = { "printtrainerdialogue", "www", { 1, 2 } },
  [0x066] = { "bwobjectmovement", "ww" }, [0x073] = { "noop", "ww" },
  -- THE BATTLE SUBWAY (src/script/Gen5BattleSubway.lua): 0x15A <function,
  -- a, b, dest> is the facility's switch (ov21 0x021CA5C4: a raw u16, two
  -- var-or-values, a var); 0x157 / 0x158 <kind, mode> / 0x159 clear, make
  -- and free the challenge's work (ov21 0x021C9924 / 0x021C9934 /
  -- 0x021C9B24); 0x1BA <regulation, dest> the party-or-Battle-Box check;
  -- 0x067 <object, x var, z var> an object's tile; 0x0D3 <var> the zone
  -- (ov10 0x0215AD38); 0x137 <var> the save under "Saving...", its answer; 0x13B <var> whether
  -- wireless play is on (0 here: the Wi-Fi branches say so); 0x13C / 0x1F0
  -- <kind, var> close the field windows / count a game record
  [0x15A] = { "bwsubway", "wwww" },
  [0x157] = { "bwsubwayinit", "" }, [0x158] = { "bwsubwaycreate", "ww" }, [0x159] = { "bwsubwayfree", "" },
  [0x1BA] = { "bwteamsource", "ww" }, [0x067] = { "bwobjectpos", "www" },
  [0x0D3] = { "getcurrentmapid", "w" }, [0x137] = { "bwsavegame", "w" },
  [0x13B] = { "bwwirelessoff", "w" }, [0x13C] = { "noop", "" }, [0x1F0] = { "noop", "ww" },
  -- BIG STADIUM / SMALL COURT (src/script/Gen5Stadium.lua, ov10
  -- 0x0215F2F0..0x0215F52C): 0x1F4 / 0x1F5 load / free the athletes' table,
  -- 0x1F6 <slot, object, tier> / 0x1F3 <slot, object, object, tier> dress
  -- objects as a row's trainer, 0x1F7 <object x3, row x3> three visitors,
  -- 0x1F8 clears the rows' trainer flags, 0x25C <var x6> draws six visitors;
  -- the clock: 0x0CF <var> the weekday, 0x0D1 <hour, minute>
  [0x1F4] = { "bwstadiumload", "" }, [0x1F5] = { "bwstadiumfree", "" }, [0x1F8] = { "bwstadiumreset", "" },
  [0x1F6] = { "bwstadiumsingle", "www" }, [0x1F3] = { "bwstadiumdouble", "wwww" },
  [0x1F7] = { "bwstadiumvisitors", "wwwwww" }, [0x25C] = { "bwstadiumdraw", "wwwwww" },
  [0x0CF] = { "bwweekday", "w" }, [0x0D1] = { "bwtime", "ww" },
  -- 0x0BF <zone, x, z, dir>: the lobby's walk onto the field (ov21
  -- 0x021AFE64 -> 0x02185050, 0x0BE's shape) -- Z079 `0BF 82 9 61 0`
  [0x0BF] = { "warp", "wwww", { 1, 1, 2, 3, 4 } },
  -- THE POKEMON MUSICAL (src/script/Gen5Musical.lua, ov10 scrcmd_musical.c
  -- 0x0215D34C..0x0215DB38): 0x167 <slot var, u8 mode> the show (2 the
  -- photo), 0x168 <slot var> Dress Up alone, 0x169 <u8 fn, arg, dest> the
  -- queries, 0x16A <fan, u8 kind, dest>, 0x16B <fn, a, b, dest> the event's
  -- work, 0x16C <prop> a prop given, 0x16D <fan> its gift handed over, 0x16E
  -- <result, slot> choose the Pokemon, 0x05D <u8 kind, u8 buffer, value> a
  -- Musical word
  [0x167] = { "bwmusicalshow", "wb" }, [0x168] = { "bwmusicaldressup", "w" },
  [0x169] = { "bwmusicalquery", "bww" }, [0x16A] = { "bwmusicalfan", "wbw" },
  [0x16B] = { "bwmusicalevent", "wwww" }, [0x16C] = { "bwmusicaladdprop", "w" },
  [0x16D] = { "bwmusicalfandone", "w" }, [0x16E] = { "bwmusicalpick", "ww" },
  [0x05D] = { "bwmusicalword", "bbw" },
  -- MONEY (BeaterScript's BW.yml names them ShowMoneyBox / CloseMoneyBox /
  -- UpdateMoneyBox / TakeMoney / CheckMoney; the call sites fix the shapes).
  -- Driftveil's item seller (member 210): `28 8027 01F4` the price, then
  -- `FB 8028 8027` -- 0 in 8028 and he says you can't afford it and the box
  -- closes (41) -- else `FA 8027` takes it and `42` redraws the box. The
  -- Magikarp salesman (member 526): `FA 01F4`, `42`, then the Magikarp.
  --   0x040 <left, top>    Platinum's showmoney
  --   0x041 / 0x042        hidemoney / updatemoneydisplay
  --   0x0FA <amount>       removemoney2 (var-or-value)
  --   0x0FB <dest, amount> checkmoney2: 1 when the money covers it
  [0x040] = { "showmoney", "ww" }, [0x041] = { "hidemoney", "" },
  [0x042] = { "updatemoneydisplay", "" },
  [0x0FA] = { "removemoney2", "w" }, [0x0FB] = { "checkmoney2", "ww" },
  --   0x0F9 <amount>       AddMoney, a var-or-value (src/script/Gen5FieldCommands)
  [0x0F9] = { "bwaddmoney", "w" },
  -- 0x094 <trainer, second, u16, u16>: BeaterScript's EventTrainerBattle --
  -- 0x085's battle with two more operands (member 46: `094 0205 0 0 0` in
  -- Black, `094 0204 ...` in White, then the 0x8D won-check)
  [0x094] = { "starttrainerbattle", "wwww", { 1, 2 } },
  -- 0x031 WaitKeypressAB, 0x000 Nop; 0x151 <u16, u16> ShowDiploma, a screen
  -- this port does not draw (Platinum's diplomas are noops too)
  [0x031] = { "waitabpress", "" }, [0x000] = { "noop", "" },
  [0x151] = { "noop", "ww" },
  -- 0x243 <message, style>: 0x43's box again (member 490's 39 lines, each
  -- `A6 0547; 243 n 0; 44`-shaped: a sound, the line, the close) -- printed
  -- and held until dismissed, so it takes 0x43's waitabpress (rewriteCompound)
  [0x243] = { "message", "ww", { 1 } },
  -- 0x051 <slot, move>: the move's name into a buffer, between 0x050 (a
  -- machine's move) and 0x052 (a pocket). Opelucid's Draco Meteor tutor
  -- (member 860): `051 0 01B2` then "It looks like this Pokemon already
  -- knows {VAR1}." -- 0x1B2 is 434, Draco Meteor; `051 1 8021` fills the
  -- {VAR2} of "Want me to teach {VAR2} to {VAR1}?"
  [0x051] = { "buffermovename", "bw" },
  -- 0x0CD <dest>: THE TIME OF DAY, and 0x0CE <dest> the Trainer Card level --
  -- READ FROM CODE, the other way round from the first reading: 0x0CD (ov10
  -- 0x0215AB18 -> 0x021690B4) is arm9 0x0209DF24[season * 24 + hour], 0
  -- morning .. 4 late night (the nurse's "Good morning!" on 0, "Hello" on 1,
  -- the evening line on 2..4; the Royal Unova's clerk sails only on 2), and
  -- 0x0CE (0x0215AAF4 -> 0x0216F830) counts five card conditions (the
  -- nurse's "Great to see you" regular on 4 or more)
  [0x0CD] = { "bwtimeperiod", "w" },
  -- THE EYE-CONTACT PATH of the shared trainer script (member 863): 0x07F
  -- <which, dest> the spotting trainer's id (0 the first, 1 the second;
  -- ov21 0x021AE9F0 reads the record's +0x10) -- Platinum's
  -- getapproachingtrainerid -- and 0x082 <which, dest> its object
  [0x07F] = { "getapproachingtrainerid", "ww" },
  [0x082] = { "bwapproachobject", "ww" },
  -- ...and the rest of that path (member 863 S0D51, the script 0xE20 that
  -- ov21 0x21AE930 starts; used nowhere else in the cartridge):
  --   0x083 <dest>   the approach type, slot 0's eye record +0x14 (ov21
  --        0x21AE9CC): 0 single, 1 a same-id double, 2 two separate
  --        trainers (VS2) -- Platinum's getapproachingtrainertype
  --   0x080 <which>  start that slot's approach task (ov21 0x21AE948 ->
  --        0x21AE454) -- Platinum's startapproachingtrainertask
  --   0x081          wait for both slots' tasks (ov21 0x21AE994); the port's
  --        0x080 already blocks until its walk is done (Gen4TwoTrainers)
  [0x083] = { "getapproachingtrainertype", "w" },
  [0x080] = { "startapproachingtrainertask", "w" },
  [0x081] = { "noop", "" },
  -- THE MOVE DELETER (member 859; src/script/Gen5FieldCommands.lua):
  -- `109 8025 8022 8020 0`, `10A 8023 8020 8022`, `10B 8020 8022`
  [0x109] = { "bwforgetmenu", "wwww" },
  [0x10A] = { "getpartymonmove", "www" },
  -- 0x10B <partySlot, moveSlot, move>: that slot set to the move, full PP --
  -- or, for move 0, forgotten with the rest moving up (the deleter's
  -- `10B 8020 8022 0`; the tutors' `10B 8020 8024 8021` after "Ta-da!" and
  -- `10B 8020 8010 8021` into a free slot)
  [0x10B] = { "bwsetmove", "www" },
  -- 0x108 <dest, partySlot>: how many moves (`108 8027 8020`, then fewer
  -- than two is "That Pokemon knows only one move")
  [0x108] = { "getpartymonmovecount", "ww" },
  -- 0x070 <idDest, foundDest, x, height, z>: the object standing on a tile
  -- (src/script/Gen5FieldCommands.lua)
  [0x070] = { "bwobjectat", "wwwww" },
  -- 0x0FF <dest, partySlot>: the Pokemon's form (ov10 0x0215B824 reads data
  -- field 0x6F) -- the Deoxys meteor (member 876: `0FF 8024 8020`, then +1
  -- round the four forms) and the Rotom boxes (member 880). Platinum's
  -- getpartymonform takes <slot, dest>
  [0x0FF] = { "getpartymonform", "ww", { 2, 1 } },
  -- 0x117 <partySlot, form>: set it (src/script/Gen5FieldCommands.lua)
  [0x117] = { "bwsetform", "ww" },
  -- 0x114 <species, dest>: how many of the party are that species, eggs not
  -- counted (ov10 0x0215B904) -- the meteor's `114 0182 8022` (Deoxys) and
  -- the Rotom boxes' `114 01DF 8028`; Platinum's countrepeatedspeciesinparty
  -- <dest, species>
  [0x114] = { "countrepeatedspeciesinparty", "ww", { 2, 1 } },
  -- 0x118 <species, found, slot>: where in the party it is (Gen5FieldCommands)
  [0x118] = { "bwfindspecies", "www" },
  -- THE POKEDEX RATING (member 884; src/script/Gen5FieldCommands.lua):
  -- 0x1CF <mode, msgDest, countDest>, 0x1CE <dest, mode>, 0x1D1 <dest>
  [0x1CF] = { "bwdexrating", "www" }, [0x1CE] = { "bwdexcomplete", "ww" },
  [0x1D1] = { "bwhasnationaldex", "w" },
  -- THE JUDGE (member 879): 0x237 <slot, mode, dest> -- the IVs by mode
  [0x237] = { "bwjudge", "www" },
  -- 0x113 <dest, slot>: the player's own Pokemon (OT id and name match)
  [0x113] = { "bwmonisown", "ww" },
  -- 0x115 <dest, move, slot>: does it know the move (ov10 0x0215BAB0) --
  -- the Rotom boxes ask after the form move; Platinum's checkpartymonhasmove
  [0x115] = { "checkpartymonhasmove", "www" },
  -- 0x06A <object, dest>: the object's event flag (the item-ball Foongus)
  [0x06A] = { "bwobjectflag", "ww" },
  -- 0x20E <kind, dest>: does the Bag hold anything the special buyer takes
  -- (src/script/Gen5MartCommands.lua; 0x14E mode 1 is that buyer's counter)
  [0x20E] = { "bwbuyerhasitems", "ww" },
  -- ...and one item to that buyer (src/script/Gen5MartCommands.lua): 0x20F
  -- <item, kind, dest> its price, 0x249 <item, kind, slot, digits> the price
  -- buffered, 0x24A <item, kind> the price paid
  [0x20F] = { "bwbuyerprice", "www" }, [0x249] = { "bwbuyerpricebuffer", "wwww" },
  [0x24A] = { "bwbuyerpay", "ww" },
  -- 0x035 <message, style>: 0x034's line (the same operands, the same
  -- message routine) in the gray event window -- the Battle Subway's and
  -- the Battle Test's announcements (`035 000F 2; waittime 15; close`)
  [0x035] = { "message", "ww", { 1 } },
  -- 0x1A0 <party slot>: the field move's cut-in (band 10000, member 867:
  -- Cut, Strength ... "{VAR1} used Cut!"), a task the script waits on (ov21
  -- 0x021C8170) -- Platinum's playhmcutin
  [0x1A0] = { "playhmcutin", "w" },
  -- THE DAY CARE (member 856; src/script/Gen5FieldCommands.lua)
  [0x0EB] = { "bwdaycarehasegg", "w" }, [0x0EE] = { "bwdaycarecount", "w" },
  [0x0EF] = { "bwdaycarecompat", "w" }, [0x0EC] = { "bwdaycaregiveegg", "" },
  [0x0ED] = { "bwdaycareresetegg", "" }, [0x0F7] = { "bwdaycarepick", "w" },
  [0x0F0] = { "bwdaycareleave", "w" }, [0x0F1] = { "bwdaycaretake", "w" },
  [0x0F2] = { "bwdaycarespecies", "ww" }, [0x0F3] = { "bwdaycareform", "ww" },
  [0x0F8] = { "bwdaycaregender", "ww" }, [0x0F4] = { "bwdaycarelevel", "ww" },
  [0x0F5] = { "bwdaycaregained", "ww" }, [0x0F6] = { "bwdaycareprice", "ww" },
  [0x251] = { "bwdaycaresign", "www" }, [0x05B] = { "bwdaycarename", "bw" },
  [0x24D] = { "bwcry", "ww" },
  -- THE MOVE TUTORS (member 860; src/script/Gen5FieldCommands.lua)
  [0x1E4] = { "bwtutorparty", "ww" }, [0x1E5] = { "bwtutormon", "www" },
  [0x1E6] = { "bwtutormove", "www" }, [0x1E7] = { "bwtutorpick", "www" },
  -- THE ROYAL UNOVA (member 104; src/world/Gen5RoyalUnova.lua). READ FROM
  -- CODE: 0x1A5 / 0x1A6 make and free the cruise's work (ov21 0x021C881C /
  -- 0x021C8848); 0x1A7 <kind, dest> a count off it (0x021C8738); 0x1A8
  -- <units, toEnd> time passing (0x021C86E8); 0x1A9 <room, kind, b, dest>
  -- a cabin's sprite / kind / trainer / line / beaten (ov10 0x02166734 --
  -- kind 6 is the trainer `85 8027 0` fights); 0x1AA <room, kind, u16,
  -- value> marks a cabin beaten (0x021C88EC); 0x1AB <dest> the deck's
  -- scenery app (ov10 0x021667E0); 0x1AC stops the clock (0x021C8960)
  [0x1A5] = { "bwshipinit", "" }, [0x1A6] = { "bwshipfree", "" },
  [0x1A7] = { "bwshipcount", "ww" }, [0x1A8] = { "bwshipadvance", "ww" },
  [0x1A9] = { "bwshiproom", "wwww" }, [0x1AA] = { "bwshipset", "wwww" },
  [0x1AB] = { "bwshipdeck", "w" }, [0x1AC] = { "bwshipstop", "" },
  -- 0x17E <frames>: a gate's electronic board -- SE 0x547, the camera to the
  -- board and back, B or a direction between (READ FROM CODE, ov48
  -- 0x021F4650; src/world/Gen5GateBoard.lua)
  [0x17E] = { "bwgateboard", "w" },
  -- 0x146 <preset, frames>: the cutscene camera to /a/1/6/3[preset] over
  -- frames (READ FROM CODE, ov21 0x021B542C; src/script/Gen5CameraCommands.lua)
  [0x146] = { "bwcamerapreset", "ww" },
  -- 0x12B <model, x, z> a building shown at its open pose (the badge gates'
  -- on-load scripts), 0x12E <model, x, z> its slot 0 looping, 0x12C <handle>
  -- an instance held where it is (READ FROM CODE, ov21 0x021B2C08 /
  -- 0x021B2C5C / 0x021B2E3C; src/world/Gen5BuildingAnim.lua)
  [0x12B] = { "bwbuildingholdopen", "www" }, [0x12E] = { "bwbuildingloop", "www" },
  [0x12C] = { "bwbuildingstop", "w" },
  -- 0x12D <model, x, z, flag> a placed building hidden (0) or shown (1)
  -- (READ FROM CODE, ov21 0x021B2CA0 -> 0x0218C54C)
  [0x12D] = { "bwbuildingshow", "wwww" },
  -- THE LAYERED FIELD THEMES (Village Bridge, Accumula): 0x0A3 <part> fades a
  -- band of the sequence in, 0x0A4 <part> out, 0x0A5 <dest, part> asks (READ
  -- FROM CODE, ov21 0x021AF458 / 0x021AF484 / 0x021AF4B0 -> arm9 0x0202C0D0..;
  -- src/world/Gen5MusicParts.lua)
  [0x0A3] = { "bwmusicparton", "w" }, [0x0A4] = { "bwmusicpartoff", "w" },
  [0x0A5] = { "bwmusicpartquery", "ww" },
  -- save reads of link data this port never has (src/script/Gen5LinkStubCommands.lua):
  -- 0x1BD <index, dest> the roamer's state (ov10 0x0216BF38), 0x1EE / 0x1EF
  -- <mode, dest> the Dream World Pokemon / Dream Remnants (ov21 0x021B6BDC,
  -- ov10 0x0215E1C0)
  [0x1BD] = { "bwroamerstate", "ww" }, [0x1EE] = { "bwdreamworld", "ww" },
  -- 0x1BC <slot> releases a roamer (ov21 0x021B5154; src/world/Gen5Roamers.lua)
  [0x1BC] = { "bwroamerrelease", "w" },
  [0x1EF] = { "bwdreamworld", "ww" },
  -- PASSERBY ANALYTICS (Castelia, member 84; src/world/Gen5Passerby.lua):
  -- READ FROM CODE, ov10 0x0216B504..0x0216B86C / ov21 0x021AFB90..
  [0x063] = { "bwanswername", "bw" },
  [0x210] = { "bwpasserbystart", "wwww" }, [0x211] = { "bwpasserbyend", "" },
  [0x212] = { "bwpasserbyrequest", "w" }, [0x213] = { "bwpasserbyquestions", "www" },
  [0x214] = { "bwpasserbytopanswer", "ww" }, [0x215] = { "bwpasserbystatus", "ww" },
  [0x216] = { "bwpasserbyremaining", "w" }, [0x217] = { "bwpasserbyelapsed", "w" },
  [0x218] = { "bwpasserbyword", "w" }, [0x219] = { "bwpasserbyword", "w" },
  [0x21A] = { "bwpasserbytally1c", "b" }, [0x21B] = { "bwpasserbytally18", "b" },
  [0x21D] = { "noop", "" },
  [0x21E] = { "bwpasserbyrank", "w" }, [0x21F] = { "bwpasserbyrankup", "" },
  -- BLACK CITY'S RESIDENTS (member 0 / 10; src/world/Gen5BlackCity.lua):
  -- READ FROM CODE, ov20 0x02186BE4 / 0x02186C44 / 0x02186D48 / 0x02186E94 /
  -- 0x02187000
  [0x1C2] = { "bwcitystop", "" }, [0x1C3] = { "bwcitybattled", "" },
  [0x1C4] = { "bwcityquery", "ww" }, [0x1C7] = { "bwcitygoalup", "" },
  [0x1C9] = { "bwcityline", "ww" },
  [0x1C5] = { "bwcityname", "w" }, [0x1C6] = { "bwcityforestcatch", "www" },
  [0x1C8] = { "bwcitygate", "" },
  -- ABYSSAL RUINS (src/script/Gen5DiveCommands.lua): 0x0DC <zone, warp, x,
  -- y, z> the special location (ov10 0x0215ADCC), 0x0C8 <mode> the dive /
  -- surfacing to it (ov21 0x021C46A4); presentation only, READ FROM CODE:
  -- 0x252 the zone camera again (0x021B2FB0), 0x033 <flag> a field byte and
  -- script bit 9 (0x021B15C8), 0x076 <dir, frames, units, sign> a camera
  -- slide (0x021B1D64)
  [0x0DC] = { "bwspeciallocation", "wwwww" }, [0x0C8] = { "bwdive", "w" },
  [0x252] = { "noop", "" }, [0x033] = { "noop", "w" }, [0x076] = { "noop", "wwww" },
  -- 0x1A4 <room> the Elite Four rooms' ambient sound (ov21 0x021B568C ->
  -- overlay 56; src/world/Gen5ZoneSounds.lua)
  [0x1A4] = { "bwzonesound", "w" },
  -- 0x135 the Abyssal Ruins' overlay models (ov21 0x021CFA58 -> overlay 57;
  -- src/world/Gen5ZoneModels.lua)
  [0x135] = { "bwzonemodels", "" },
  -- 0x134 the street crowds (ov21 0x021B69B0 -> overlay 55;
  -- src/world/Gen5Walkers.lua)
  [0x134] = { "bwcrowd", "" },
  -- the party checks behind the Effort Ribbon and the Hidden Power reader
  -- (src/script/Gen5PartyChecks.lua): 0x112 <dest, slot> ov10 0x0215B5BC,
  -- 0x236 <dest, slot> ov21 0x021B62C8
  [0x112] = { "bweffortsum", "ww" }, [0x236] = { "bwhiddenpower", "ww" },
  -- side quests (src/script/Gen5SideCommands.lua): the Hip Waders' catch of
  -- the day 0x231 / met date 0x11A, the move man 0x238, the feature bits
  -- 0x0E6..0x0E8, the Relocator's word entry 0x1ED / passwords 0x20C, Unity
  -- Tower 0x1DA / 0x1DD..0x1E1 / 0x1E3
  [0x231] = { "bwcatchofday", "w" }, [0x11A] = { "bwmetdate", "wwww" },
  [0x238] = { "bwmachinemove", "w" },
  [0x0E6] = { "bwfeaturelow", "ww" }, [0x0E7] = { "bwfeatureset", "w" }, [0x0E8] = { "bwfeaturefull", "ww" },
  [0x1ED] = { "bwwordentry", "wwww" }, [0x20C] = { "bwpassword", "wwww" },
  [0x1DD] = { "bwunityfloor", "ww" }, [0x1DE] = { "bwunity2", "ww" }, [0x1DF] = { "bwunity3", "www" },
  [0x1DA] = { "bwunity2", "ww" }, [0x1E0] = { "bwunitymenu", "wwww" },
  [0x1E1] = { "bwunity1", "w" }, [0x1E3] = { "bwunity1", "w" },
  [0x229] = { "bweventitem", "ww" },
  -- party / bag / save checks for offline side events
  -- (src/script/Gen5FieldChecks.lua); 0x11E (above) keeps each badge's team
  [0x0BD] = { "bwitemkind", "ww" }, [0x10E] = { "bwgivemonball", "wwwwwwwww" },
  [0x10F] = { "bwgiveegg", "www" }, [0x11B] = { "bwmontypes", "www" },
  [0x11F] = { "bwbadgeteamnames", "ww" }, [0x20D] = { "bwbirthdaywords", "wwww" },
  [0x05A] = { "bwbufferword", "bw" }, [0x0E9] = { "bwsaveblock1c", "w" },
  -- 0x1E2 <value> (ov21 0x021D0014) writes the value into the Global Link
  -- guest block (0x02009618) and nothing else: no block here, a no-op
  [0x1E2] = { "noop", "w" },
  -- Zorua's illusion puff (ov59; src/world/Gen5IllusionFx.lua)
  [0x221] = { "bwillusionend", "wwwwww" }, [0x222] = { "bwillusionplace", "wwww" },
  [0x223] = { "bwillusionwait", "w" }, [0x224] = { "bwillusionstart", "w" },
  -- N's Castle's objects (ov64; src/world/Gen5IllusionFx.lua)
  [0x23F] = { "bwcastleplayer", "" }, [0x255] = { "bwcastlecarry", "wwwwww" },
  [0x256] = { "bwcastlepuff", "www" }, [0x257] = { "bwcastlewait", "" }, [0x258] = { "bwcastlewait", "" },
  -- 0x136 <weather, instant> a script's field weather (src/world/Gen5Weather.lua)
  [0x136] = { "bwsetweather", "ww" },
  -- an object flown along a baked path round the player (ov21; Tornadus /
  -- Thundurus at Z337 and Z376; src/world/Gen5FlightPath.lua)
  [0x15B] = { "bwflightattach", "w" }, [0x15C] = { "bwflightdetach", "" },
  [0x15D] = { "bwflightplay", "w" }, [0x15E] = { "bwflightwait", "" },
  -- an object raised / lowered in place and Meloetta's dance (ov10;
  -- src/world/Gen5ObjectMotion.lua)
  [0x225] = { "bwobjectheight", "www" }, [0x226] = { "bwobjectdance", "w" },
  -- the Zorua story's picture and the movie event Pokemon used up
  -- (src/script/Gen5EventMonCommands.lua)
  [0x0DE] = { "bwdexmarkseen", "ww" }, [0x227] = { "bwshowmonpicture", "wwww" }, [0x228] = { "bweventmonused", "ww" },
  -- 0x24B <frames> (ov21 0x021AF044): the zone's own BGM back (0x02029DF4,
  -- as 0x09E) through sound queue 5 faded over `frames` (0x020298A0 ->
  -- 0x020289F8), the event-BGM bit cleared (0x02028BDC); not a save
  [0x24B] = { "bwmapmusic", "w" },
  -- a trade record's nickname, the wireless wait, a save word, the C-Gear
  -- off (src/script/Gen5MiscFieldOps.lua)
  [0x242] = { "bwbuffertradedname", "ww" }, [0x139] = { "bwwirelessend", "w" },
  [0x23C] = { "bwsaveblock34", "" }, [0x25E] = { "bwcgearoff", "" },
  [0x1A3] = { "bwroomcamera", "w" },
}

-- THE STACK FORM. Most of BW's conditional jumps are an expression on the
-- script stack and then 0x1F 0xFF target, "jump if the top is FALSE" -- the
-- handler (0x02159670 in Black) pops it and falls through on 1, which is a
-- compiled `if (expression) { ... }` jumping past its body. (Read the other
-- way round, Z054's masseuse was "exhausted" on a fresh save: she checks
-- `flag 0xAAE == 0` and sets 0xAAE herself after a massage.)
--
--   0x08 push constant   0x09 push var   0x10 push flag (1 set, 0 clear)
--   0x11 op  pops b, then a, pushes `a op b`
--
-- The operators, read off 0x11's handler (overlay 10, 0x021594E0 in Black):
-- 0 <  1 ==  2 >  3 <=  4 >=  5 != (unsigned), 6 OR, 7 AND (each side == 1).
-- The usual shape is one comparison (2,192 jumps); the rest join several
-- with 6 / 7, e.g. `var 0x408A == 3 AND flag 0x80 == 0`.
--
-- Platinum has one compare and a jump on its result, so an expression is
-- rewritten as a chain of them ("jumping code") that jumps when the
-- expression fails: a failing AND jumps on either side, a failing OR skips
-- past the jump when its left side holds. A var is compared to
-- the constant (or to another var) and the jump takes the operator (or its
-- negation) as its condition; a flag is checked and the condition is the
-- Gen 4 code whose answer for clear and for set is exactly `flag op
-- constant` (or its negation) -- all four combinations have one. The skip lands on the instruction after the 0x1F,
-- which the pool decodes as an entry of its own.
local OPS = {
  [0] = function(a, b) return a < b end, function(a, b) return a == b end,
  function(a, b) return a > b end, function(a, b) return a <= b end,
  function(a, b) return a >= b end, function(a, b) return a ~= b end,
}
-- Gen 4 condition by its answer for result 0 (clear) and result 1 (set)
local FLAG_CONDITION = { ["TF"] = 0, ["FT"] = 1, ["TT"] = 3, ["FF"] = 2 }
-- the comparison that holds when this one fails, and the one for swapped sides
local NEGATE = { [0] = 4, 5, 3, 2, 0, 1 }
local SWAP = { [0] = 2, 1, 0, 4, 3, 5 }

local function u16le(s, o) return (s:byte(o) or 0) + (s:byte(o + 1) or 0) * 256 end

-- parse(decoded, i) -> the expression, the index of its 0x1F, or nil
local function parse(decoded, i)
  local stack = {}
  for k = i, #decoded do
    local ins = decoded[k]
    if ins.op == 0x08 then stack[#stack + 1] = { kind = "const", value = u16le(ins.operands, 1), at = ins.at }
    elseif ins.op == 0x09 then stack[#stack + 1] = { kind = "var", value = u16le(ins.operands, 1), at = ins.at }
    elseif ins.op == 0x10 then stack[#stack + 1] = { kind = "flag", value = u16le(ins.operands, 1), at = ins.at }
    elseif ins.op == 0x11 then
      local op = u16le(ins.operands, 1)
      local b, a = table.remove(stack), table.remove(stack)
      if not (a and b) or op > 7 then return nil end
      stack[#stack + 1] = { kind = "op", op = op, a = a, b = b, at = a.at }
    elseif ins.op == 0x1F and ins.operands:byte(1) == 0xFF then
      if #stack == 1 and stack[1].kind == "op" then return stack[1], k end
      return nil
    else
      return nil
    end
  end
end

-- emit(node, target, sense, tail, out, skip) -> true when lowered: jumps to
-- `target` when the node's truth is `sense`, else falls through. A skip past
-- the whole jump is only reachable from the tail of the chain.
local function emit(node, target, sense, tail, out, skip)
  if node.kind ~= "op" then return false end
  local op, a, b = node.op, node.a, node.b
  if op == 6 or op == 7 then
    if (op == 6) == sense then        -- OR jumping on true / AND on false
      return emit(a, target, sense, false, out, skip) and emit(b, target, sense, tail, out, skip)
    end
    if not tail then return false end -- AND on true / OR on false
    return emit(a, skip, not sense, false, out, skip) and emit(b, target, sense, tail, out, skip)
  end
  -- a comparison: put the var or flag on the left
  if a.kind == "const" and b.kind ~= "const" then a, b, op = b, a, SWAP[op] end
  -- `(expression) == 1` / `!= 0` is the expression; `== 0` / `!= 1` its negation
  if a.kind == "op" and b.kind == "const" and (op == 1 or op == 5) and (b.value == 0 or b.value == 1) then
    local same = (op == 1) == (b.value == 1)
    return emit(a, target, same == sense, tail, out, skip)
  end
  local cond = sense and op or NEGATE[op]
  if a.kind == "var" and b.kind == "const" then
    out[#out + 1] = { at = a.at, op = 0x19, name = "comparevartovalue", args = { a.value, b.value } }
  elseif a.kind == "var" and b.kind == "var" then
    out[#out + 1] = { at = a.at, op = 0x19, name = "comparevartovar", args = { a.value, b.value } }
  elseif a.kind == "flag" and b.kind == "const" then
    local f = OPS[op]
    local key = (f(0, b.value) == sense and "T" or "F") .. (f(1, b.value) == sense and "T" or "F")
    out[#out + 1] = { at = a.at, op = 0x10, name = "checkflag", args = { a.value } }
    cond = FLAG_CONDITION[key]
  else
    return false
  end
  out[#out + 1] = { at = a.at, op = 0x1F, name = "gotoif", args = { cond }, target = target }
  return true
end

function L.rewriteStack(decoded)
  local out, i = {}, 1
  while i <= #decoded do
    local a = decoded[i]
    local node, k
    if a.op == 0x08 or a.op == 0x09 or a.op == 0x10 then node, k = parse(decoded, i) end
    local chain = {}
    local j = k and decoded[k]
    if node and emit(node, j.target, false, true, chain, j.at + 2 + j.width) then
      for _, ins in ipairs(chain) do out[#out + 1] = ins end
      i = k + 1
    elseif node then
      -- AN EXPRESSION THE JUMPING CODE CANNOT SPELL (an OR of ANDs jumping on
      -- false, a nested sum of conditions): kept as the cartridge's own stack
      -- program, postfix, as (kind, value) pairs -- 1 const, 2 var, 3 flag,
      -- 4 operator -- and evaluated when it runs (g4_bw_eval)
      local program = {}
      local function post(n)
        if n.kind == "op" then post(n.a); post(n.b); program[#program + 1] = 4; program[#program + 1] = n.op
        else program[#program + 1] = (n.kind == "const" and 1) or (n.kind == "var" and 2) or 3
             program[#program + 1] = n.value end
      end
      post(node)
      out[#out + 1] = { at = a.at, op = 0x1F, name = "bwevalgoto", args = program, target = j.target }
      i = k + 1
    else
      out[#out + 1] = L.name(a)
      i = i + 1
    end
  end
  return out
end

-- SAVE AND RESTORE. Outside a condition 0x09 / 0x0A are a push and a pop,
-- and nearly every one brackets a common-script call: push 0x8000, push
-- 0x8001, set them as the callee's arguments, call, pop 0x8001, pop 0x8000.
-- Platinum has no script stack, so a push becomes a copy into a slot var
-- (one per depth, from 0x8100 -- the cartridge's own temporary vars stop
-- at 0x8054) and a pop copies it back. Depth is tracked through each block in
-- order; a pop with nothing pushed in the block stays unnamed.
L.SLOT_BASE = 0x8100
-- a var-or-value operand: 0x4000 and up names a var (Gen 4's rule too)
function L.setvarName(value) return (value or 0) >= 0x4000 and "setvarfromvar" or "setvarfromvalue" end
function L.rewritePushPop(list)
  local depth = 0
  for _, ins in ipairs(list) do
    if ins.name == "bw_009" and ins.operands then
      local value = (ins.operands:byte(1) or 0) + (ins.operands:byte(2) or 0) * 256
      ins.name, ins.args = L.setvarName(value), { L.SLOT_BASE + depth, value }
      depth = depth + 1
    elseif ins.name == "bw_00A" and ins.operands and depth > 0 then
      depth = depth - 1
      ins.name, ins.args = "setvarfromvar", { (ins.operands:byte(1) or 0) + (ins.operands:byte(2) or 0) * 256, L.SLOT_BASE + depth }
    end
  end
  return list
end

-- COMMANDS THAT ARE SEVERAL OF PLATINUM'S. Each expands into Platinum rows,
-- and where it needs a choice the skip lands on the instruction after it,
-- which the pool decodes as an entry like any other jump target.
--
--   0x107 <ok var, slot var, u16 mode>  the party menu: ok = 1 and the slot
--         when a Pokemon was picked, ok = 0 on cancel. Z054's masseuse:
--         `107 0x8022 0x8021 0`, then "Oh, I see" unless 0x8022 == 1.
--   0x102 <dest var, slot var>  whether that slot holds an Egg (she answers a
--         non-zero one with "Massage the Egg? It may be a bit too early").
--         Platinum's species read gives an Egg as 0, so dest = species == 0.
--   0xB3 <layers, from, to, speed>  a brightness fade, 0 -> 16 darkening
--         and 16 -> 0 brightening; Platinum's fadescreen takes an even type
--         to darken and an odd one to brighten, with steps x frames per step
--   0xFD <slot, amount, mode>  friendship: mode 1 adds (the masseuse's
--         30 / 10 / 5 before "much more / more / a little more friendly");
--         Platinum's increasepartymonfriendship is <amount, slot>
L.KEEP_OPERANDS = { [0x09] = true, [0x0A] = true, [0x107] = true, [0x102] = true,
                    [0xB3] = true, [0xFD] = true, [0x8D] = true, [0x143] = true }
L.SCRATCH = 0x8141
local function word(ins, k) return (ins.operands:byte(k) or 0) + (ins.operands:byte(k + 1) or 0) * 256 end
function L.rewriteCompound(list)
  local out = {}
  local function add(ins, name, args, target)
    out[#out + 1] = { at = ins.at, op = ins.op, name = name, args = args, target = target }
  end
  for _, ins in ipairs(list) do
    local nextAt = ins.width and ins.at + 2 + ins.width
    if ins.name == "bw_107" and ins.operands then
      local ok, slot = word(ins, 1), word(ins, 3)
      add(ins, "openpartymenufortrade", {})
      add(ins, "getselectedpartyslot", { slot })
      add(ins, "setvarfromvalue", { ok, 1 })
      add(ins, "comparevartovalue", { slot, 0xFF })
      add(ins, "gotoif", { 5 }, nextAt)
      add(ins, "setvarfromvalue", { ok, 0 })
    elseif ins.name == "bw_102" and ins.operands then
      local dest, slot = word(ins, 1), word(ins, 3)
      add(ins, "getpartymonspecies", { slot, L.SCRATCH })
      add(ins, "setvarfromvalue", { dest, 1 })
      add(ins, "comparevartovalue", { L.SCRATCH, 0 })
      add(ins, "gotoif", { 1 }, nextAt)
      add(ins, "setvarfromvalue", { dest, 0 })
    elseif (ins.op == 0x43 or ins.op == 0x243) and (ins.name == "message" or ins.name == "messagevar") then
      out[#out + 1] = ins
      add(ins, "waitabpress", {})
    elseif ins.name == "bw_08D" and ins.operands then
      -- Platinum's checkwonbattle: 1 for a win, as BW's (and it marks the
      -- trainer beaten)
      add(ins, "checkwonbattle", { word(ins, 1) })
    elseif ins.name == "bw_143" and ins.operands and #ins.operands >= 22 then
      -- <u16 pitch, u16 yaw, fx32 distance, fx32 x, y, z, u16 frames>: the
      -- point to look at in world units, 16 to a tile, so tile = fx32 / 65536
      -- -- ABSOLUTE matrix tiles, which addfreecamera takes as Platinum's
      -- does. The gym's (12.5, 3.4) is where Z007's three leaders stand;
      -- Nacrene's (644.5, 583.5) is local (36.5, 7.5) from its origin
      -- (608, 576). The cartridge's pitch, distance and frames are not
      -- carried: the player's own camera mode decides those here.
      local function fx(k) local v = word(ins, k) + word(ins, k + 2) * 65536
        if v >= 0x80000000 then v = v - 0x100000000 end return v end
      add(ins, "addfreecamera", { math.floor(fx(9) / 65536), math.floor(fx(17) / 65536) })
    elseif ins.name == "bw_0B3" and ins.operands then
      local from, to, speed = word(ins, 3), word(ins, 5), word(ins, 7)
      add(ins, "fadescreen", { 6, math.max(1, speed), to > from and 0 or 1, 0 })
    elseif ins.name == "bw_0FD" and ins.operands and word(ins, 5) == 1 then
      add(ins, "increasepartymonfriendship", { word(ins, 3), word(ins, 1) })
    else
      out[#out + 1] = ins
    end
  end
  return out
end

-- THE SCRIPT ID TABLE. A script id above a map's own picks a shared file by
-- range: { u16 first, u16 last, u16 script member, u16 3, u16 text bank },
-- 46 records in descending order (overlay 10, 0x021701A8 in Black), e.g.
-- 2000-2099 -> member 854 with bank 158, 10110-10119 -> 871. Found by
-- shape: the run of such records holding { 2000, 2099 }. The bands Gen 4
-- also has keep Gen 4's names (common scripts, the two battle bands on one
-- file, visible and hidden items); the rest are named by their first id.
local GEN4_NAMES = { [2000] = "common_scripts", [3000] = "single_battles", [5000] = "double_battles",
                     [7000] = "visible_items", [8000] = "hidden_items" }
function L.findBands(rom)
  local blobs = { rom:arm9() }
  for o = 0, 400 do
    local ok, b = pcall(function() return rom:overlay(o) end)
    if ok and b then blobs[#blobs + 1] = b elseif o > 200 then break end
  end
  local function valid(b, k)
    if k < 0 or k + 10 > #b then return nil end
    local f, l, m, t, txt = u16le(b, k + 1), u16le(b, k + 3), u16le(b, k + 5), u16le(b, k + 7), u16le(b, k + 9)
    if t == 3 and f <= l and f >= 1 then return { f, l, m, txt } end
  end
  local key = string.char(0xD0, 0x07, 0x33, 0x08) -- 2000, 2099
  for _, b in ipairs(blobs) do
    local at = 1
    while true do
      local i = b:find(key, at, true)
      if not i then break end
      local k = i - 1
      if valid(b, k) then
        local rows = {}
        while valid(b, k) do
          local r = valid(b, k)
          rows[#rows + 1] = { r[1], GEN4_NAMES[r[1]] or ("bw_" .. r[1]), r[3], r[4], last = r[2] }
          k = k - 10
        end
        if #rows >= 10 then
          table.sort(rows, function(x, y) return x[1] > y[1] end)
          return rows
        end
      end
      at = i + 1
    end
  end
  return nil
end

local function split(operands, spec)
  local args, o = {}, 1
  for i = 1, #spec do
    local c = spec:sub(i, i)
    local b = function(k) return operands:byte(o + k) or 0 end
    if c == "b" then args[#args + 1] = b(0); o = o + 1
    elseif c == "w" then args[#args + 1] = b(0) + b(1) * 256; o = o + 2
    elseif c == "d" then args[#args + 1] = b(0) + b(1) * 256 + b(2) * 65536 + b(3) * 16777216; o = o + 4 end
  end
  return args
end

-- name(ins) -> the instruction with Platinum's name and arguments
function L.name(ins)
  local alias = L.ALIASES[ins.op]
  if not alias or #alias[2] == 0 and ins.width ~= 0 then
    return { at = ins.at, op = ins.op, name = ("bw_%03X"):format(ins.op), args = {}, target = ins.target,
             operands = L.KEEP_OPERANDS[ins.op] and ins.operands or nil,
             width = L.KEEP_OPERANDS[ins.op] and ins.width or nil }
  end
  local args = split(ins.operands, alias[2])
  if alias[3] then
    local picked = {}
    for i, k in ipairs(alias[3]) do picked[i] = args[k] end
    args = picked
  end
  if alias[1] == "noop" then args = {} end
  local name = alias[1]
  if name == "setvar" then name = L.setvarName(args[2]) end
  if name == "message" and (args[1] or 0) >= 0x4000 then name = "messagevar" end
  -- 0x3D / 0x3C OPEN WITH A BANK SELECTOR, a u16 the two leading "bytes" make
  -- up: 0x0400 is the script's own bank; anything else names one -- a var
  -- when >= 0x4000 (the shared item-gift script prints from 0x8006, which its
  -- caller filled with its own bank through 0x0CC), else the bank itself
  if (ins.op == 0x3D or ins.op == 0x3C) and name:sub(1, 7) == "message" then
    local bank = (ins.operands:byte(1) or 0) + (ins.operands:byte(2) or 0) * 256
    if os.getenv and os.getenv("BWBANKSTAT") then
      L.bankStat = L.bankStat or {}
      if not L.bankStat[bank] then print(("[bwbank] selector 0x%04X first at op 0x%X"):format(bank, ins.op)) end
      L.bankStat[bank] = (L.bankStat[bank] or 0) + 1
    end
    if bank ~= 0x0400 then
      return { at = ins.at, op = ins.op, name = "messagefrombank", args = { bank, args[1] }, target = ins.target }
    end
  end
  return { at = ins.at, op = ins.op, name = name, args = args, target = ins.target }
end

-- THE NEW-GAME SCRIPT: newGame(archive, widths, bandRows) -> { flags, vars }
-- A new game hides every actor whose story has not begun by running one
-- shared script of nothing but `setflag`s (Platinum's 112, Hoenn's 159).
-- Black's is a subroutine band 9600's (member 866) entry calls: 131 setflags, one
-- `0x4116 = 1`, and a return. Found by that shape -- the one shared script
-- whose every row is a setflag, a set var or its end, at least 100 of them --
-- not by its id. Without it Nuvema's and Accumula's gated people stand on the
-- map from the first frame.
function L.newGame(arc, widths, bandRows)
  local Script = require("src.import.Gen4Script")
  local best
  local seen = {}
  for _, row in ipairs(bandRows or {}) do
    local m = row[3]
    local d = not seen[m] and m < arc.count and arc:get(m)
    seen[m] = true
    if d then
      -- the entries and every block they call or jump to (the flag list is
      -- a subroutine the band's entry calls)
      local queue, visited = {}, {}
      for _, at in ipairs(Script.entries(d)) do queue[#queue + 1] = at end
      local qi = 1
      while qi <= #queue do
        local at = queue[qi]; qi = qi + 1
        if visited[at] then goto continue end
        visited[at] = true
        local decoded = Ops.decode(d, at, widths)
        for _, ins in ipairs(decoded) do
          if ins.target and ins.target >= 1 and ins.target <= #d then queue[#queue + 1] = ins.target end
        end
        local flags, vars, clean = {}, {}, true
        for _, ins in ipairs(decoded) do
          local named = L.name(ins)
          if named.name == "setflag" then flags[#flags + 1] = ("FLAG_G4_%04X"):format(named.args[1])
          elseif named.name == "setvarfromvalue" or named.name == "setvar" then
            vars[#vars + 1] = { id = named.args[1], value = named.args[2] }
          elseif named.name ~= "return" and named.name ~= "end" then clean = false break end
        end
        if clean and #flags >= 100 and (not best or #flags > #best.flags) then
          best = { flags = flags, vars = vars, member = m, at = at,
                   source = ("ROM:/a/0/5/7 member %d at %d"):format(m, at) }
        end
        ::continue::
      end
    end
  end
  return best
end

-- pool(archive, widths, zones, maps) -> map_scripts, report
-- A ZONE'S INIT-SCRIPT FILE (the zone header's `initScripts`, a member of
-- the same archive): 6-byte entries -- u16 type, u32 value -- ended by a u16
-- 0. Type 1 is a frame table, its value an offset from the end of its own
-- entry to rows of u16 var, u16 value, u16 script, ended by a u16 0; the
-- other types name a script outright. The numbering is HGSS's (2 on
-- transition, 3 on resume, 4 on load). Read off Nuvema's: the player's room
-- (783) is one frame table, var 0x4081 == 0 -> script 5, the opening.
L.INIT_NAMES = { [1] = "frame_table", [2] = "on_transition", [3] = "on_resume", [4] = "on_load" }
function L.initScripts(d)
  local callbacks, tables = {}, {}
  if type(d) ~= "string" then return callbacks, tables end
  local function u16(o) return d:byte(o + 1) + d:byte(o + 2) * 256 end
  local function u32(o) return u16(o) + u16(o + 2) * 65536 end
  local o = 0
  while o + 2 <= #d do
    local kind = u16(o)
    if kind == 0 or o + 6 > #d then break end
    local value = u32(o + 2)
    if kind == 1 then
      local rows, r = {}, o + 6 + value
      while r + 6 <= #d and u16(r) ~= 0 do
        rows[#rows + 1] = { var = u16(r), value = u16(r + 2), script = u16(r + 4) }
        r = r + 6
      end
      tables[#tables + 1] = { type = 1, name = L.INIT_NAMES[1], rows = rows }
    else
      callbacks[#callbacks + 1] = { type = kind, name = L.INIT_NAMES[kind] or ("init_" .. kind), script = value }
    end
    o = o + 6
  end
  return callbacks, tables
end

function L.pool(arc, widths, zones, maps, bandRows)
  local Script = require("src.import.Gen4Script")
  local VM = require("src.script.Gen4ScriptVM")
  local scripts, entriesOf, named, total, moves = {}, {}, 0, 0, 0
  -- A SHARED FILE'S `end` IS A RETURN. 0x1C runs the common script in a
  -- context of its own and waits for it, so the `end` closing the give-item
  -- script (member 862: `B5 item; ... 01D; end`) ends only that context and
  -- Mom's scene carries on after her Xtransceiver. Lowered as Platinum's
  -- call, that `end` ended the caller too.
  local shared = {}
  for _, row in ipairs(bandRows or {}) do shared[row[3]] = true end
  local function decodeMember(m)
    if entriesOf[m] then return entriesOf[m] end
    local d = m < arc.count and arc:get(m)
    if not d then entriesOf[m] = {} return entriesOf[m] end
    local entries = Script.entries(d)
    local queue, seen = {}, {}
    for _, at in ipairs(entries) do queue[#queue + 1] = at end
    local i = 1
    while i <= #queue do
      local at = queue[i]; i = i + 1
      if not seen[at] then
        seen[at] = true
        local decoded, stopped = Ops.decode(d, at, widths)
        for _, ins in ipairs(decoded) do
          if ins.target and ins.target >= 1 and ins.target <= #d then queue[#queue + 1] = ins.target end
        end
        local list = L.rewriteCompound(L.rewritePushPop(L.rewriteStack(decoded)))
        for _, ins in ipairs(list) do
          if ins.target and ins.target >= 1 and ins.target <= #d and not seen[ins.target] then queue[#queue + 1] = ins.target end
        end
        for _, ins in ipairs(list) do
          total = total + 1
          if not ins.name:match("^bw_") then named = named + 1 end
          if ins.name == "gotoif" and ins.args[1] == 0xFF then ins.name = "bw_01F" end
          if shared[m] and ins.name == "end" then ins.name = "return" end
          if ins.op == 0x1CB and ins.args and ins.args[1] and ins.at then
            -- the elevator's floor table, in this file after the code (the
            -- named row keeps the u32 as its argument, not the operands)
            local rel = ins.args[1]
            if rel >= 2147483648 then rel = rel - 4294967296 end
            local t = (ins.at - 1) + 6 + rel
            local function h(p) return (d:byte(p + 1) or 0) + (d:byte(p + 2) or 0) * 256 end
            ins.floors = {}
            for k = 0, 7 do
              local p = t + k * 10
              if p + 10 > #d or h(p) == 0xFFFF then break end
              ins.floors[#ins.floors + 1] = { label = h(p), zone = h(p + 2), x = h(p + 4), y = h(p + 6), z = h(p + 8) }
            end
          end
          if ins.name == "applymovement" then
            local address = Movement.addressOf(ins, 8)
            ins.movement = address and Movement.decode(d, address) or nil
            if ins.movement then moves = moves + 1 end
          end
        end
        scripts[VM.label(m, at)] = { instructions = list, stopped = stopped }
      end
    end
    local labels = {}
    for k, at in ipairs(entries) do labels[k] = VM.label(m, at) end
    entriesOf[m] = labels
    return labels
  end
  local out, linked = {}, 0
  for mapId, def in pairs(maps) do
    local z = zones[def.header]
    if z then
      local labels = decodeMember(z.scripts)
      local rec = { header = def.header, objects = {}, signs = {}, entries = labels }
      -- A SCRIPT ID PAST THE ZONE'S OWN names a shared file: the Pokemon
      -- Center's nurse is 2100 and its PC 2101 in every town. Filed the way
      -- the Gen 4 pool files them (`shared.objects[index] = { band, entry }`)
      -- so Gen4ScriptVM resolves the block and reads the band's text bank.
      local function shared(kind, index, id)
        for _, row in ipairs(bandRows or {}) do
          if id >= row[1] and id <= (row.last or row[1]) then
            rec.shared = rec.shared or {}
            rec.shared[kind] = rec.shared[kind] or {}
            rec.shared[kind][index] = { band = row[2], entry = id - row[1] }
            linked = linked + 1
            return
          end
        end
      end
      for _, o in ipairs(def.objects or {}) do
        local label = labels[o.script]
        if label then rec.objects[o.index] = label; linked = linked + 1
        elseif o.script and o.script >= 1000 then shared("objects", o.index, o.script) end
      end
      for _, s in ipairs(def.signs or {}) do
        local label = labels[s.script]
        if label then rec.signs[s.index] = label; linked = linked + 1
        elseif s.script and s.script >= 1000 then shared("signs", s.index, s.script) end
      end
      -- the coordinate triggers (Accumula's welcome, Route 1's exit), filed
      -- under the event's index as Gen4ScriptVM joins them
      for _, c in ipairs(def.coordEvents or {}) do
        local label = c.script and labels[c.script]
        if label then
          rec.coords = rec.coords or {}
          rec.coords[c.index] = label; linked = linked + 1
        end
      end
      -- the zone's init scripts, in HGSS's record shape
      local initBytes = z.initScripts and z.initScripts < arc.count and arc:get(z.initScripts)
      local callbacks, tables = L.initScripts(initBytes)
      for _, c in ipairs(callbacks) do
        local label = labels[c.script]
        if label then
          rec.callbacks = rec.callbacks or {}
          rec.callbacks[#rec.callbacks + 1] = { type = c.type, name = c.name, script = label }
        end
      end
      for _, t in ipairs(tables) do
        local rows = {}
        for _, row in ipairs(t.rows) do
          local label = labels[row.script]
          if label then rows[#rows + 1] = { a = row.var, b = row.value, script = label } end
        end
        if #rows > 0 then
          rec.tables = rec.tables or {}
          rec.tables[#rec.tables + 1] = { type = 1, name = t.name, rows = rows }
        end
      end
      out[mapId] = rec
    end
  end
  -- the shared files, in the shape Gen4ScriptVM's `bandLabel` reads
  local bands = {}
  for _, row in ipairs(bandRows or {}) do
    if not bands[row[2]] then
      bands[row[2]] = { member = row[3], textBank = row[4], entries = decodeMember(row[3]) }
    end
  end
  for _, ins in pairs(scripts) do
    for _, i in ipairs(ins.instructions) do i.operands, i.width = nil, nil end
  end
  return { source = "RomExtractorGen4", scripts = scripts, maps = out, bands = bands },
         { instructions = total, named = named, linked = linked, movements = moves }
end

return L
