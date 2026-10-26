-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local Views=require('src.compat.gen1.SessionView')
local Ids=require('src.compat.gen1.BattleIds')
local D={}
local function query(dex,species,seen)
  local g,s=Views.store(dex,'dex');if not g then return false end
  local key=Ids.new(g.data):native('pokemon',species)
  if not key then return false end
  if seen then return not not(s.pokedex and s.pokedex.seen and s.pokedex.seen[key])end
  return require('src.battle.CaughtMarker').caught(g,key)
end
function D.isCaught(dex,species)return query(dex,species,false)end
D.isOwned=D.isCaught
function D.isSeen(dex,species)return query(dex,species,true)end
return D
