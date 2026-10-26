-- Original byte-indexed terrain flags; native behavior numbering is separate.
local Flags = {}
function Flags.read(rom, spec)
  if type(spec) ~= "table" then return nil, "source flag metadata unavailable" end
  local offset, count, digest = spec.offset, spec.count, spec.sha256
  if type(offset) ~= "number" or offset < 0 or offset % 1 ~= 0
      or count ~= 240 or type(digest) ~= "string" or #digest ~= 64
      or digest:find("[^0-9a-f]") then return nil, "invalid source flag metadata" end
  if not (rom and type(rom.data) == "string") or offset + count > #rom.data then
    return nil, "source flag table outside cartridge"
  end
  if not (love and love.data and love.data.hash) then return nil, "source flag checksum unavailable" end
  local raw = rom.data:sub(offset + 1, offset + count)
  local hash = love.data.hash("sha256", raw)
  local hex = hash:gsub(".", function(c) return ("%02x"):format(c:byte()) end)
  if hex ~= digest then return nil, "source flag checksum mismatch" end
  for i = 1, #raw do if raw:byte(i) > 7 then return nil, "invalid source flag bits" end end
  return raw
end
return Flags
