-- Copyright (c) 2026 Cedric. Existing source rights retained; see NOTICE.md.
-- Native player integration of the Gen1Recomp GSC runtime under GPLv3 plus
-- Additional Terms; compat/gen1-gsc/LICENSE.MD and provenance.json.
-- One real command VM owns BG, ten object structs and forty OAM entries.
local Runtime=require('src.battle.gen2.AnimRunner')
local Data=require('src.battle.Gen2AnimData')
local Gen2AnimPlayer={}
Gen2AnimPlayer.__index=function(self,key)
  local method=Gen2AnimPlayer[key]
  if method~=nil then return method end
  local runner=rawget(self,'runtime')
  if runner then
    if key=='done'then return runner.stopped end
    if key=='frames'or key=='bg'or key=='objects'or key=='keepSprites'then return runner[key]end
  end
end
function Gen2AnimPlayer.new(data)
  local anims=data and data.battle_anims or {}
  require('src.battle.Gen2AnimationIds').install(anims)
  local tables,constants=Data.tables(anims,data and data.constants)
  local runner=Runtime.new({data=tables,constants=constants})
  runner.stopped=true
  runner.retire=function()end
  local self=setmetatable({data=data,anims=anims,warned={},effects={},runtime=runner},Gen2AnimPlayer)
  self.view=require('src.battle.Gen2AnimView').new(tables,data)
  return self
end
function Gen2AnimPlayer:release()
  if self.view then self.view:release();self.view=nil end
end
function Gen2AnimPlayer:warnOnce(key,fmt,...)
  if self.warned[key]then return end
  self.warned[key]=true
  print(string.format(fmt,...))
end
local GEN1_BALL_ANIMS = {
  TOSS_ANIM = "throwPokeBall",
  GREATTOSS_ANIM = "throwPokeBall",
  ULTRATOSS_ANIM = "throwPokeBall",
  BLOCKBALL_ANIM = "throwPokeBall",
  POOF_ANIM = "sendOutMon",
  -- The shiny sparkle is not an animation of its own: BattleAnim_SendOutMon
  -- opens `anim_if_param_equal $1, .Shiny`, and core.asm plays the SAME
  -- animation a SECOND time with wBattleAnimParam = 1 whenever
  -- CheckShininess returns carry (:3566 the enemy's send-out, :4057 the
  -- player's, :9091 a wild encounter, which plays only this pass).  That
  -- branch is eight SFX_SHINE stars over an inverted flash and a
  -- gray/yellow OBJ-palette cycle.  Both Gold and Crystal carry it; Prism's
  -- script is shorter but has the same param-1 arm.
  SHINY_ANIM = "sendOutMon",
  SHAKE_ANIM = false,
  HIDEPIC_ANIM = false,
  SHOWPIC_ANIM = false,
}

-- Resolve a move id (or one of the misc animation names) to a script.
function Gen2AnimPlayer:scriptFor(moveId)
  local anims = self.anims
  if Data.isNative(anims)then
    local key=anims.moves and anims.moves[moveId]or anims.ids and anims.ids[moveId]
    if not key then
      local alias=GEN1_BALL_ANIMS[moveId]
      if alias==false then return nil end
      key=anims.misc and anims.misc[alias or moveId]
    end
    if not key and type(moveId)=='number'then key=anims.indices and anims.indices[moveId]end
    return key and anims.scripts and anims.scripts[key]and key or nil
  end
  local id = anims.moveAnims and anims.moveAnims[moveId]
    or anims.ids and anims.ids[moveId]
  if not id then
    local alias = GEN1_BALL_ANIMS[moveId]
    if alias == false then return nil end
    id = anims.misc and anims.misc[alias or moveId]
  end
  if not id and type(moveId) == "number" then id = moveId end
  return id and anims.scripts and anims.scripts[id] or nil
end

-- BattleAnim_ThrowPokeBall opens with
--   anim_if_param_equal NO_ITEM,     .TheTrainerBlockedTheBall
--   anim_if_param_equal MASTER_BALL, .MasterBall
--   anim_if_param_equal ULTRA_BALL,  .UltraBall
--   anim_if_param_equal GREAT_BALL,  .GreatBall
-- so wBattleAnimParam is the ball's ITEM INDEX, and 0 is the trainer-battle
-- block.  Leaving it at 0 sent every toss down .TheTrainerBlockedTheBall,
-- which spawns BATTLE_ANIM_OBJ_HIT_YFIX off BATTLE_ANIM_GFX_HIT -- the stray
-- "attack" flash over the throw -- and skipped the whole capture tail (the
-- mon being drawn in, the wobbles, the click).
local DEFAULT_BALL_ITEM = 5   -- POKE_BALL, the generic-arc branch

local function itemIndex(self, id)
  local items = id and self.data and self.data.items
  if not items then return nil end
  local def = items[id]
  if not def then
    -- Gen2's item ids are ITEM_nnn while the battle code keys balls by
    -- Gen1's name-derived ids, so match on either
    for _, entry in pairs(items) do
      if entry.key == id then def = entry; break end
    end
  end
  local index = def and tonumber(def.index)
  return (index and index > 0) and index or nil
end

local function ballParam(self, opts)
  if self.moveId == "BLOCKBALL_ANIM" then return 0 end
  local index = opts and tonumber(opts.ballIndex)
  if index and index > 0 then return index end
  return itemIndex(self, opts and opts.ball)
    or itemIndex(self, "POKE_BALL")
    or DEFAULT_BALL_ITEM
end

function Gen2AnimPlayer:start(moveId,attackerIsPlayer,opts)
  if self.presentation then self.presentation.retire()end
  self.presentation=nil
  self.effects={}
  self.keptSprites=nil
  self.opts=opts or {}
  self.moveId=moveId
  if moveId=='POOF_ANIM'or moveId=='SHINY_ANIM'then attackerIsPlayer=not attackerIsPlayer end
  self.enemySide=not attackerIsPlayer
  self.script=self:scriptFor(moveId)
  self.presentationId=moveId
  local alias=GEN1_BALL_ANIMS[moveId]
  local canonical=alias=='throwPokeBall'and 'ANIM_THROW_POKE_BALL'
    or alias=='sendOutMon'and 'ANIM_SEND_OUT_MON'
  if self.script and canonical and self:scriptFor(canonical)==self.script then self.presentationId=canonical end
  local param=self.opts.param or 0
  if alias=='throwPokeBall'then param=ballParam(self,self.opts)
  elseif moveId=='SHINY_ANIM'then param=1 end
  local tables,constants=Data.tables(self.anims,self.data and self.data.constants)
  local program,entry
  if Data.isNative(self.anims)then program,entry=tables,self.script
  else program,entry=Data.program(tables,self.script)end
  local data,events,options=self.data,self.effects,self.opts
  local wobbles=0
  local runner=Runtime.new({data=program,constants=constants,
    battleTurn=self.enemySide and 1 or 0,animId=self.presentationId,
    param=param,ballPalette=options.ballPalette,sgb=options.sgb,
    flying=options.flying,
    hooks={
      battlerGfx=function(runner,front,back)
        self.view:loadBattlerRows(self.screen,front,back)
      end,
      pokeballWobble=function()
        wobbles=wobbles+1
        return wobbles<=(options.shakes or 0)and 0 or options.caught and 1 or 2
      end,
      sound=function(_,panning,duration,id)
        local Sound=require('src.core.Sound')
        local audio=data and data.audio
        local name=audio and (audio.sfxIndex and audio.sfxIndex[tostring(id)]
          or audio.sfxOrder and audio.sfxOrder[id+1])
        if name and audio.sfx and audio.sfx[name]then return Sound.playStereo(data,name)end
        local def=data and data.moves and data.moves[moveId]
        if def and def.anim then return Sound.playMove(data,def.anim)end
      end,
      cry=function(side,pitch,length)
        events[#events+1]={cry=true,side=side,pitch=pitch,length=length}
      end,
    }})
  runner:start(entry)
  if not self.script then runner.stopped=true end
  -- A restarted native player creates a new VM. Old public runners already
  -- own their old BG/objects/OAM and have no pointer back to this player.
  runner.retire=function()end
  self.runtime=runner
  self.view.data=program
  self.vars=setmetatable({}, {
    __index=function(_,key)return runner[key]end,
    __newindex=function(_,key,value)runner[key]=value end,
  })
  if not self.script and GEN1_BALL_ANIMS[moveId]==nil then
    self:warnOnce('anim:'..tostring(moveId),'Gen2AnimPlayer: no animation data for move %s',tostring(moveId))
  end
  return self.script~=nil
end
function Gen2AnimPlayer:isDone()return self.runtime.stopped end
function Gen2AnimPlayer:pollEffects()
  -- The hook holds this same channel for the life of this real runner.
  local out={}
  for i,event in ipairs(self.effects)do out[i]=event end
  for i=#self.effects,1,-1 do self.effects[i]=nil end
  return out
end
function Gen2AnimPlayer:update()
  if self.runtime.stopped then return false end
  local active=self.runtime:step()
  if not active and self.runtime.keepSprites then
    local kept={}
    for i,row in ipairs(self.runtime:oam())do
      local copy={};for key,value in pairs(row)do copy[key]=value end
      kept[i]=copy
    end
    kept.runner=self.runtime
    self.keptSprites=#kept>0 and kept or nil
  end
  return active
end
function Gen2AnimPlayer:oam(objects)return objects or self.runtime:oam()end
function Gen2AnimPlayer:finalSprites()return self.keptSprites end
function Gen2AnimPlayer:draw()return self.view:drawObjects(self.runtime,self.battle)end
function Gen2AnimPlayer:drawSprites(objects)
  if not objects then return self:draw()end
  local runner=setmetatable({oam=function()return objects end},{__index=objects.runner or self.runtime})
  return self.view:drawObjects(runner,self.battle)
end

-- The historical SE-reset lookup remains available to existing consumers.
-- The native VM no longer emits these substitutes: Gen2BgView and native
-- picture drawing consume the genuine BG owner directly.
local BG_EFFECTS_END = {
  [0x03] = "SE_RESET_SCREEN_PALETTE", -- WHITE_HUES
  [0x04] = "SE_RESET_SCREEN_PALETTE", -- BLACK_HUES
  [0x05] = "SE_RESET_SCREEN_PALETTE", -- ALTERNATE_HUES
  [0x08] = "SE_RESET_SCREEN_PALETTE", -- CYCLE_BGPALS_INVERTED
  [0x15] = "SE_RESET_SCREEN_PALETTE", -- RAPID_FLASH
  [0x16] = "SE_RESET_SCREEN_PALETTE", -- FADE_MON_TO_LIGHT
  [0x17] = "SE_RESET_SCREEN_PALETTE", -- FADE_MON_TO_BLACK
  [0x18] = "SE_RESET_SCREEN_PALETTE", -- FADE_MON_TO_LIGHT_REPEATING
  [0x19] = "SE_RESET_SCREEN_PALETTE", -- FADE_MON_TO_BLACK_REPEATING
  [0x1A] = "SE_RESET_SCREEN_PALETTE", -- CYCLE_MON_LIGHT_DARK_REPEATING
  [0x1C] = "SE_RESET_SCREEN_PALETTE", -- FADE_MONS_TO_BLACK_REPEATING
  [0x1D] = "SE_RESET_SCREEN_PALETTE", -- FADE_MON_TO_WHITE_WAIT_FADE_BACK
  [0x1E] = "SE_RESET_SCREEN_PALETTE", -- FADE_MON_FROM_WHITE
  [0x1B] = "SE_RESET_MON_POSITION",   -- FLASH_MON_REPEATING
  [0x21] = "SE_RESET_MON_POSITION",   -- WITHDRAW
  [0x22] = "SE_RESET_MON_POSITION",   -- BOUNCE_DOWN
  [0x24] = "SE_RESET_MON_POSITION",   -- TACKLE
  [0x25] = "SE_RESET_MON_POSITION",   -- WOBBLE_MON
  [0x27] = "SE_RESET_MON_POSITION",   -- WAVE_DEFORM_MON
  [0x2B] = "SE_RESET_MON_POSITION",   -- FLAIL
  [0x32] = "SE_RESET_MON_POSITION",   -- VIBRATE_MON
  [0x33] = "SE_RESET_MON_POSITION",   -- WOBBLE_PLAYER
}
Gen2AnimPlayer.BG_EFFECTS_END = BG_EFFECTS_END

-- BG commands now execute their genuine register/picture state machines.
-- Battler-picture requests are drawn by the native lifted-row pass, while
-- the remaining approximate object runtime is replaced independently.
Gen2AnimPlayer.BG_EFFECTS_DROPPED = {}


return Gen2AnimPlayer
