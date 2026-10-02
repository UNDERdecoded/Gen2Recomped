-- Keep Platinum origin fields when Pokemon are received or hatch.
local Origin={}
function Origin.stamp(game,mon,kind,location,today)
  if not (game and game.data and (game.data.constants or {}).gen==4 and mon) then return end
  today=today or os.date('*t')
  local date={year=today.year,month=today.month,day=today.day}
  if kind=='egg' then
    mon.eggDate=mon.eggDate or date
    mon.eggLocation=mon.eggLocation or location
  elseif kind=='hatch' then
    mon.metDate=date
    mon.metLocation=location
    mon.hatched=true
  else
    mon.metDate=mon.metDate or date
    mon.metLocation=mon.metLocation or location
  end
end
return Origin
