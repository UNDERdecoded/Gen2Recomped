-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Cartridge indices belong to this imported dataset, including sparse species
-- slots. Portable names and National Dex numbers are not substitutes for them.
local M={}
local schema={pokemon={'speciesOrder','pokemon'},moves={'moveOrder','moves'},items={'itemOrder','items'},
 abilities={'abilityOrder','abilities',1},types={'typeOrder','types',1},trainers={'trainerOrder','trainers'}}
function M.new(data)
 local indexes={}
 local function index(kind)
  if indexes[kind]then return indexes[kind]end
  local spec=assert(schema[kind],'unknown battle identifier kind')
  local constants=data.constants or{};local rows=data[spec[2]]or constants[spec[2]]or{}
  local order=constants[spec[1]]or{};local forward,reverse={},{}
  local function add(number,key)
   if type(number)~='number'or number<0 or number%1~=0 then return end
   if forward[number]~=nil and forward[number]~=key then forward[number]=false else forward[number]=key end
   if reverse[key]~=nil and reverse[key]~=number then reverse[key]=false else reverse[key]=number end
  end
  for number,key in pairs(order)do if type(number)=='number'and rows[key]~=nil then add(number-(spec[3]or 0),key)end end
  for key,row in pairs(rows)do
   if type(row)=='table'and type(row.index)=='number'and order[row.index+(spec[3]or 0)]==nil then add(row.index,key)end
  end
  local result={forward=forward,reverse=reverse,rows=rows};indexes[kind]=result;return result
 end
 return {
  read=function(_,kind,key)
   if key==nil or key==false then return(kind=='items'or kind=='abilities')and 0 or nil end
   local i=index(kind);local n=i.reverse[key]
   if n~=nil then return n or nil end
   if type(key)=='number'and i.rows[key]then return key end
  end,
  native=function(_,kind,value)
   if value==nil or value==0 and(kind=='items'or kind=='abilities')then return nil end
   local i=index(kind)
   if type(value)=='number'then return i.forward[value]or nil end
   if i.rows[value]then return value end
  end,
 }
end
return M
