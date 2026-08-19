-- The START menu (engine/menus/start_menu.asm): entries appear as they
-- become usable -- POKéDEX once Oak gives it, POKéMON once you have any,
-- SAVE with a confirmation, plus ITEM / OPTION / LINK / QUIT.  The built
-- item list runs through the ui.start_menu.items hook before the menu
-- opens, so mods insert or remove rows without patching this file.

local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Menu = require("src.ui.Menu")
local Renderer = require("src.render.Renderer")
local Runtime = require("src.mods.Runtime")
local Screens = require("src.ui.Screens")
local Strings = require("src.core.Strings")

local StartMenu = {}

local function sameItems(_, items) return items end

function StartMenu.new(game)
  local flags = game.save.flags or {}
  local items = {}

  -- vanilla start submenus return here on B (RedisplayStartMenu): the
  -- generic Menu pops the start menu when a row is selected, so each
  -- submenu gets an onCancel that re-opens it
  local function reopen() Screens.push(game, "StartMenu") end

  -- StartMenu.DrawBugContestStatus (engine/menus/start_menu.asm:396) tests
  -- STATUSFLAGS2_BUG_CONTEST_TIMER_F and, while the contest is running, draws
  -- a status box ABOVE the menu -- it is not a menu row, and it is not
  -- selectable.  Drawn at the bottom of this file, like the Safari Zone's.
  local BugContest = require("src.world.BugContest")
  local inContest = BugContest.active(game.save)

  -- POKéDEX: only after the professor hands it over -- and WHICH FLAG that is
  -- differs per cartridge, so it goes through Flags.hasPokedex (Prism sets
  -- ENGINE_POKEDEX where Gold and Crystal set EVENT_GOT_POKEDEX).
  if require("src.script.Flags").hasPokedex(game.save) then
    table.insert(items, { label = Strings("POKéDEX"), onSelect = function()
      Screens.push(game, "PokedexMenu", { onCancel = reopen })
    end })
  end

  -- POKéGEAR sits directly under the DEX in Gen2's start menu
  -- (StartMenu_Pokegear, gated on EVENT_GOT_POKEGEAR)
  if flags.EVENT_GOT_POKEGEAR then
    table.insert(items, { label = Strings("POKéGEAR"), onSelect = function()
      Screens.push(game, "PokegearMenu", { onCancel = reopen })
    end })
  end

  -- R/B's draw_start_menu.asm prints POKéMON even with an empty party and
  -- no-ops on select.  GSC does not: StartMenu builds its item list from
  -- flags and leaves POKéMON out entirely until the player owns one, which
  -- is why it looked wrong sitting there before Elm hands the starter over.
  if #game.save.party > 0
     or not require("src.core.GameVersion").isGen2() then
    table.insert(items, { label = Strings("POKéMON"), onSelect = function()
      if #game.save.party == 0 then return end
      Screens.push(game, "PartyMenu", { onCancel = reopen })
    end })
  end

  -- .SetUpMenuItems' `.no_pack`: the PACK row is left OUT entirely while the
  -- contest timer is running (start_menu.asm:51-57).  You are carrying Park
  -- Balls, not your bag, and the balls are thrown from the battle menu.
  if not inContest then
    table.insert(items, { label = Strings("ITEM"), onSelect = function()
      Screens.push(game, "BagMenu", { onCancel = reopen })
    end })
  end

  -- the player's name opens the trainer card (StartMenu_TrainerInfo)
  table.insert(items, { label = game.save.player.name or "RED",
    onSelect = function()
      Screens.push(game, "TrainerCard", { onCancel = reopen })
    end })

  -- SAVE shows the player/badges/dex/time panel then asks to confirm
  -- (PrintSaveScreenText).  During the contest the SAME SLOT becomes QUIT
  -- instead -- `ld a, STARTMENUITEM_QUIT / jr nz, .write` in .SetUpMenuItems
  -- (start_menu.asm:77-85) -- so you cannot save mid-run, and QUIT is added
  -- below rather than here.
  if not inContest then
  table.insert(items, { label = Strings("SAVE"), onSelect = function()
    local TextBox = require("src.render.TextBox")
    local badges = require("src.inventory.Badges").count(game.data, game.save)
    local owned = 0
    for _ in pairs(game.save.pokedex and game.save.pokedex.owned or {}) do
      owned = owned + 1
    end
    local t = math.floor(game.save.playTime or 0)
    local panel = Strings("PLAYER %s\nBADGES    %d\nPOKéDEX %3d\nTIME %6d:%02d",
                          game.save.player.name or "RED", badges, owned,
                          math.floor(t / 3600), math.floor(t / 60) % 60)
    game.stack:push(TextBox.new(game,
      panel .. Strings("\fWould you like to\nSAVE the game?"), nil, {
      choice = function(yes)
        if not yes then return end
        -- "Now saving..." beat before the write (save.asm
        -- NowSavingString), then GameSavedText + SFX_SAVE
        game.stack:push(TextBox.new(game, Strings("Now saving..."), function()
          game:writeSave()
          require("src.core.Sound").play(game.data, "Save")
          game.stack:push(TextBox.new(game,
            Strings("%s saved\nthe game!", game.save.player.name or "RED")))
        end))
      end,
    }))
  end })

  end

  table.insert(items, { label = Strings("OPTION"), onSelect = function()
    Screens.push(game, "OptionsMenu", { onCancel = reopen })
  end })

  -- LINK needs a party
  if #game.save.party > 0 then
    table.insert(items, { label = Strings("LINK"), onSelect = function()
      local LinkState = require("src.link.LinkState")
      game.stack:push(LinkState.new(game))
    end })
  end

  -- the manager's pause-menu entry (18-mod-manager-ux): gated on at least
  -- one discovered mod so a vanilla install's menu is unchanged
  local status = game.modStatus
  if status and #(status.available or {}) > 0 then
    table.insert(items, { label = Strings("MODS"), onSelect = function()
      Screens.push(game, "ManagerState")
    end })
  end

  -- the original's EXIT just closed the menu (CloseStartMenu); with a
  -- window close button covering that, QUIT instead power-cycles back
  -- to the title after a confirm (defaultNo guards accidental quits)
  -- StartMenu_Quit: during the contest QUIT does NOT leave the game, it offers
  -- to end the Contest (_StartMenuContestEndText).  That is the "how do I get
  -- out of here" exit a cartridge gives you.
  if inContest then
    table.insert(items, { label = Strings("QUIT"), onSelect = function()
      local TextBox = require("src.render.TextBox")
      game.stack:push(TextBox.new(game,
        Strings("Would you like to\nend the Contest?"), nil, {
        defaultNo = true,
        choice = function(yes)
          if not yes then return reopen() end
          -- StartMenu_Quit (engine/menus/start_menu.asm:411) does exactly one
          -- thing on YES: FarQueueScript BugCatchingContestReturnToGateScript.
          -- It does NOT judge, score or tear the run down first -- all of that
          -- is inside the script it queues, and it has to happen AT THE GATE,
          -- in the cartridge's order.  Ending the run here as well meant
          -- judging later scored a run that had already been zeroed, so the
          -- prize was always the consolation BERRY.
          game.overworld:bugContestReturnToGate()
        end,
      }))
    end })
  else
    table.insert(items, { label = Strings("QUIT"), onSelect = function()
      local TextBox = require("src.render.TextBox")
      game.stack:push(TextBox.new(game, Strings("RETURN TO MAIN\nMENU?"), nil, {
        defaultNo = true,
        choice = function(yes)
          if yes then game:returnToTitle() end
        end,
      }))
    end })
  end

  local hooked = Runtime.call("ui.start_menu.items", sameItems, game, items)
  if type(hooked) == "table" then
    items = hooked
  else
    Logger.error("ui.start_menu.items returned %s; keeping the vanilla items",
                 type(hooked))
  end

  -- the start menu's mask is PAD_DOWN | PAD_UP | PAD_START | PAD_B | PAD_A
  -- (engine/menus/draw_start_menu.asm), so START closes it back to the
  -- overworld -- unlike most menus, whose masks omit PAD_START.
  --
  -- item count isn't fixed: POKéDEX/LINK/MODS come and go with save state,
  -- and mods can append their own rows through the hook above, so the
  -- double-spaced box (the original's style) can grow past the 18-tile
  -- canvas. Cap it at however many rows actually fit and scroll the rest,
  -- with Menu's moreArrow showing while there's more below.
  local rowStep = 2
  local maxVisible = math.floor((Renderer.HEIGHT / 8 - 2) / rowStep)
  local menu = Menu.new(game, items,
    -- the START menu hugs the top-right corner of the SCREEN, not of a
    -- centred letterbox: at 9,0 x 11 it is already flush with the top and
    -- right of the 20x18 grid, so the anchor keeps it flush when the view
    -- is zoomed out and the letterbox no longer fills the window
    { tx = 9, ty = 0, tw = 11, maxVisible = maxVisible, startCloses = true,
      anchor = "topright" })
  -- the cursor position survives closing the menu
  -- (wBattleAndStartSavedMenuItem, home/start_menu.asm)
  menu.index = math.min(game.save.startMenuIndex or 1, #items)
  menu:clampScroll()
  local baseUpdate = menu.update
  menu.update = function(self, dt)
    baseUpdate(self, dt)
    game.save.startMenuIndex = self.index
  end

  -- inside the Safari Zone the start menu also shows remaining steps and
  -- SAFARI BALLs (PrintSafariZoneSteps, engine/overworld/player_state.asm:
  -- 219-224): a 9x5 border at the top-left with "steps/500" and "BALL xx".
  -- It opens with `cp SAFARI_ZONE_EAST / ret c`, so only the nine interior
  -- maps ($D9..$E1) get it -- SAFARI_ZONE_GATE is $9C and falls under that
  -- early out, and used to show "502/500" while the player was still
  -- standing at the counter (#540).  Same map set as the step counter's
  -- (FieldDefaults safari.stepMaps via OverworldState:inSafariStepZone).
  -- StartMenu_PrintBugContestStatus (engine/menus/menu_2.asm:152) draws the
  -- contest panel above the menu: a Textbox at hlcoord 0,0 with b = 5 rows and
  -- c = 17 columns, then
  --
  --     hlcoord 1, 1  "CAUGHT"     hlcoord 8, 1  <mon name> or "None"
  --     hlcoord 1, 3  "LEVEL"      right after it, the level, left-aligned
  --     hlcoord 1, 5  "BALLS:"     hlcoord 8, 5  wParkBallsRemaining
  --
  -- Note there is NO TIMER in it.  The clock runs, and it ends the contest,
  -- but the cartridge never shows you how long is left -- so neither does
  -- this.  The LEVEL row appears only once something has been caught
  -- (`ld a, [wContestMon] / and a / jr z, .skip_level`).
  if inContest then
    local baseDraw = menu.draw
    menu.draw = function(self)
      baseDraw(self)
      Font.drawBox(0, 0, 17, 5)
      love.graphics.setColor(0, 0, 0, 1)
      Font.draw(Strings("CAUGHT"), 8, 8)
      local caught = BugContest.caught(game.save)
      if caught then
        local def = game.data.pokemon[caught.species]
        Font.draw((def and def.name) or tostring(caught.species), 64, 8)
        Font.draw(Strings("LEVEL"), 8, 24)
        Font.draw(tostring(math.floor(caught.level or 0)), 56, 24)
      else
        Font.draw(Strings("None"), 64, 8)
      end
      Font.draw(Strings("BALLS:"), 8, 40)
      Font.draw(("%d"):format(BugContest.ballsLeft(game.save)), 64, 40)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  local ow = game.overworld
  if game.save.safari and ow and ow.map and ow.inSafariStepZone
     and ow:inSafariStepZone() then
    local baseDraw = menu.draw
    menu.draw = function(self)
      baseDraw(self)
      local safari = game.save.safari
      Font.drawBox(0, 0, 9, 5)
      love.graphics.setColor(0, 0, 0, 1)
      Font.draw(("%3d"):format(math.floor(safari.steps or 0)), 8, 8)
      Font.draw("/500", 32, 8)
      Font.draw(Strings("BALL"), 8, 24)
      Font.draw(("%2d"):format(math.floor(safari.balls or 0)), 48, 24)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end
  return menu
end

return StartMenu
