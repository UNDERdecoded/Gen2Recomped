-- Animation observes the existing native clock. It never advances the game,
-- source scripts, RNG or a second terrain timer.
local A={_visible={}}
local function native()return require('src.core.game3.tileset_native')end
function A.install()A.invalidate()end
function A.invalidate()A._visible={};A._current=nil end
function A.enterMap(pair)A._current=pair;A._visible[pair]=true;return true end
function A.bindPair(pair,atlas)if not(pair and atlas)then return false end;A._visible[pair]=true;return true end
function A.unbindPair(pair)A._visible[pair]=nil end
function A.setVisiblePairs(pairs)A._visible=pairs or{}end
function A.step()native().update()end
A.stepRse=A.step
A.release=A.invalidate
return setmetatable(A,{__index=function(_,key)
 if key=='_pairs'then
  -- Resident native animation owners, observed without loading an atlas or
  -- advancing a decoder. Authored legacy RGBA banks are a separate format;
  -- do not invent those when only native VRAM animation programs exist.
  local out={};local rse=not require('src.core.GameVersion').isFRLG()
  for pair,atlas in pairs(native().animationPairs())do
   if atlas.image and not atlas._retired and atlas._model then out[pair]={native=true,rse=rse}end
  end
  return out
 end
end})
