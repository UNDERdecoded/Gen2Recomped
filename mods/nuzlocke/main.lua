-- Nuzlocke rules. Uses the current engine's internal seams while the
-- equivalent public API hooks are being added.
return function(mod)
  mod.hooks:wrap("intro.oak_speech.build", function(next, steps, speech)
    steps = next(steps, speech)
    mod.ui.insertStepAfter(steps, "oak_welcome", {
      id = "nuzlocke_intro", kind = "say", pic = "oak",
      text = "A Nuzlocke is a\npromise.\fEvery loss is\npermanent.",
    })
    mod.ui.insertStepAfter(steps, "nuzlocke_intro", {
      id = "nuzlocke_slow_start", kind = "yesno", pic = "oak",
      saveKey = "slow_start", defaultNo = true,
      text = "Use SLOW START?\nRules start with\nPOKé BALLS.",
    })
    mod.ui.insertStepAfter(steps, "nuzlocke_slow_start", {
      id = "nuzlocke_dupes", kind = "choice", pic = "oak",
      saveKey = "dupes_mode", text = "When you meet a\nknown family?",
      choices = { "SKIP", "LOSE" }, values = { "skip", "strict" },
    })
    mod.ui.insertStepAfter(steps, "nuzlocke_dupes", {
      id = "nuzlocke_safari", kind = "yesno", pic = "oak",
      saveKey = "safari_sectors", text = "Separate SAFARI\nsectors?",
    })
    mod.ui.insertStepAfter(steps, "nuzlocke_safari", {
      id = "nuzlocke_close", kind = "say", pic = "oak",
      text = "Give every friend\na name. Keep them\nsafe. Good luck!",
    })
    return steps
  end)

  mod.events:on("intro.oak_speech.answered", function(ev)
    if ev.saveKey then mod.save:set(ev.saveKey, ev.value) end
  end)

  local function active(game, battle)
    if not (game and game.save) or (battle and (battle.demo or battle.ghost)) then return false end
    if not mod.save:get("slow_start", false) then return true end
    if mod.save:get("balls_unlocked", false) then return true end
    for id, count in pairs(game.save.inventory or {}) do
      if count > 0 and game.data.items[id] and game.data.items[id].ball then
        mod.save:set("balls_unlocked", true)
        return true
      end
    end
    return false
  end

  local function areaKey(game, battle)
    if battle and battle.safari and not mod.save:get("safari_sectors", false) then
      return "SAFARI_ZONE"
    end
    return (game.overworld and game.overworld.map and game.overworld.map.id)
      or (game.save.player and game.save.player.map) or "UNKNOWN"
  end

  local function family(data, species)
    local found, pending = {}, { species }
    while #pending > 0 do
      local id = table.remove(pending)
      if not found[id] then
        found[id] = true
        for _, evo in ipairs((data.pokemon[id] or {}).evolutions or {}) do pending[#pending + 1] = evo.species end
        for parent, def in pairs(data.pokemon or {}) do
          for _, evo in ipairs(def.evolutions or {}) do
            if evo.species == id then pending[#pending + 1] = parent end
          end
        end
      end
    end
    return found
  end

  local function ownsFamily(game, species)
    local members = family(game.data, species)
    local function owns(mon) return mon and members[mon.species] end
    for _, mon in ipairs(game.save.party or {}) do if owns(mon) then return true end end
    for _, box in ipairs(game.save.boxes or {}) do
      for _, mon in ipairs(box) do if owns(mon) then return true end end
    end
    return false
  end

  local function caughtAreas()
    local areas = mod.save:get("caught_areas")
    if type(areas) ~= "table" then areas = {}; mod.save:set("caught_areas", areas) end
    return areas
  end

  local function denied(game, battle, species)
    if not active(game, battle) then return nil end
    if caughtAreas()[areaKey(game, battle)] then return "area" end
    if ownsFamily(game, species) then return "dupes" end
  end

  mod.events:on("pokemon.caught", function(ev)
    -- A successful capture proves that Slow Start has ended even when it was
    -- the last ball in the bag.
    if mod.save:get("slow_start", false) then mod.save:set("balls_unlocked", true) end
    if active(ev.game, ev.battle) then
      caughtAreas()[areaKey(ev.game, ev.battle)] = ev.species
      mod.save:set("caught_areas", caughtAreas())
    end
  end)

  mod.events:on("game.ready", function()
    local BattleState = require("src.battle.BattleState")
    local Commands = require("src.script.Commands")
    local Party = require("src.pokemon.Party")
    local Boxes = require("src.pokemon.Boxes")
    local Pokemon = require("src.pokemon.Pokemon")
    local Runtime = require("src.mods.Runtime")
    local Screens = require("src.ui.Screens")
    local Strings = require("src.core.Strings")
    local SaveData = require("src.core.SaveData")
    local GameVersion = require("src.core.GameVersion")
    local Bag = require("src.inventory.Bag")

    BattleState.askNicknameUI = function(self, mon)
      self.lockedBall, self.blankForAskName = nil, false
      return self:buildScreen("NamingScreen", {
        title = Strings("NICKNAME?"), maxLen = 10,
        onDone = function(name) mon.nickname = name or "A" end,
      })
    end

    -- Gifts and starters use the same mandatory naming screen.
    Commands.give_pokemon = function(ctx, species, level)
      local gift = { ctx = ctx, species = species, level = level }
      if ctx.game.mods then ctx.game.mods.events:emit("pokemon.before_give", gift) end
      local mon = Pokemon.new(ctx.game.data, gift.species, gift.level)
      ctx.game.stringBuffer, ctx.pendingPokemonName = ctx.game.data.pokemon[gift.species].name or gift.species, gift.species
      BattleState.stampOT(ctx.save, mon)
      local inParty = Party.add(ctx.save.party, mon)
      local boxNum = inParty and nil or Boxes.deposit(ctx.save, mon)
      if not inParty and not boxNum then ctx.lastCheck = false; return end
      if ctx.save.pokedex then ctx.save.pokedex.seen[gift.species], ctx.save.pokedex.owned[gift.species] = true, true end
      ctx.lastCheck, ctx.addedToParty, ctx.boxNum = true, inParty, boxNum
      if ctx.runner then
        Screens.push(ctx.game, "NamingScreen", {
          title = Strings("NICKNAME?"), maxLen = 10,
          onDone = function(name) mon.nickname = name or "A"; ctx.runner:resume() end,
        })
        ctx.runner:yield()
      else mon.nickname = "A" end
      if boxNum then
        ctx.game.boxMonNicks, ctx.game.stringBuffer = mon.nickname, tostring(boxNum)
        if ctx.runner then Commands.show_text(ctx, "_SentToBoxText") end
      end
    end

    local vanillaThrowBall = BattleState.throwBall
    BattleState.throwBall = function(self, ball)
      local reason = denied(self.game, self, self.enemy and self.enemy.mon.species)
      if reason then
        if reason == "dupes" and mod.save:get("dupes_mode", "skip") == "strict" then
          caughtAreas()[areaKey(self.game, self)] = "DUPES_LOST"
          mod.save:set("caught_areas", caughtAreas())
        end
        Bag.add(self.game.save, ball, 1, self.game.data)
        self:say(reason == "area" and "This area already\nhas a captured POKéMON!"
          or "You already have\nthis POKéMON family!")
        return
      end
      return vanillaThrowBall(self, ball)
    end

    local vanillaOnFaint = BattleState.onFaint
    BattleState.onFaint = function(self, battler)
      if not (battler.isPlayer and active(self.game, self)) then return vanillaOnFaint(self, battler) end
      if battler.faintQueued then return end
      battler.faintQueued = true
      if self.participants then self.participants[battler.mon] = nil end
      Runtime.emit("battle.fainted", { battle = self, battler = battler })
      for i, mon in ipairs(self.game.save.party) do
        if mon == battler.mon then table.remove(self.game.save.party, i); break end
      end
      self:actNext(function()
        battler.fainted = true
        require("src.core.Sound").playCry(self.data, battler.mon.species)
        require("src.core.Sound").play(self.data, "Faint_Fall")
        self.fx = self.fx or {}; self.fx.faint = { battler = battler, frames = 30 }
      end)
      self.nextInsert = (self.nextInsert or 0) + 1
      table.insert(self.queue, self.nextInsert, { wait = 30 })
      self:sayNext(Strings("%s\ndied!", battler.name))
      self:act(function() self:playerMonFainted() end)
    end

    local vanillaPlayerFainted = BattleState.playerMonFainted
    BattleState.playerMonFainted = function(self)
      if active(self.game, self) and not Party.firstHealthy(self.game.save.party) then
        self.nuzlockeGameOver, self.result, self.afterQueue = true, "nuzlocke_game_over", "finish"
        self:sayNext(Strings("All of your\nPOKéMON are dead..."))
        return
      end
      return vanillaPlayerFainted(self)
    end

    local vanillaFinish = BattleState.finish
    BattleState.finish = function(self)
      if not self.nuzlockeGameOver then return vanillaFinish(self) end
      self.nuzlockeGameOver = nil
      self.game.stack:pop()
      Runtime.emit("battle.ended", { battle = self, result = "nuzlocke_game_over" })
      -- Game over has no victory lap: delete the slot, then use Credits only
      -- as its existing THE END renderer / A-or-B wait screen.
      local version = GameVersion.get()
      local slot = SaveData.activeSlot(version)
      if slot then SaveData.deleteSlot(version, slot)
      elseif love and love.filesystem then
        local main = SaveData.saveFilename(version)
        love.filesystem.remove(main); love.filesystem.remove(main .. ".bak"); love.filesystem.remove(main .. ".tmp")
      end
      local ending = Screens.push(self.game, "Credits", function()
        require("src.core.Music").stop()
        while self.game.stack:top() do self.game.stack:pop() end
        Screens.push(self.game, "IntroMovie", function()
          if self.game.makeTitleState then self.game.stack:push(self.game:makeTitleState()) end
        end)
      end)
      ending.phase, ending.timer = "end_wait", 0
    end
  end)
end
