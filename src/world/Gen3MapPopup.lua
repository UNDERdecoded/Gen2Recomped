local Popup={}
function Popup.theme(record,section)
  if section>=88 then section=section>196 and section-109 or 0 end
  return record.themes[section] or 0
end
function Popup.new(name,section,weather)
  return {emerald=true,name=name,section=section,weather=weather,state="print",timer=0,offset=40}
end
function Popup.queue(active,incoming)
  active.state="out";active.pending=incoming
  return active
end
function Popup.tick(sign)
  if sign.state=="print" then
    sign.timer=sign.timer+1
    if sign.timer>30 then sign.state="in";sign.timer=0 end
  elseif sign.state=="in" then
    sign.offset=math.max(0,sign.offset-2)
    if sign.offset==0 then sign.state="wait";sign.timer=0 end
  elseif sign.state=="wait" then
    sign.timer=sign.timer+1
    if sign.timer>120 then sign.state="out" end
  elseif sign.state=="out" then
    sign.offset=math.min(40,sign.offset+2)
    if sign.offset==40 then
      if sign.pending then return sign.pending end
      sign.state="erase"
    end
  elseif sign.state=="erase" then sign.state="end"
  elseif sign.state=="end" then return nil end
  return sign
end
function Popup.draw(data,sign)
  if sign.state=="print" or sign.state=="erase" or sign.state=="end" then return end
  local record=data.constants and data.constants.gen3MapPopup
  if not record then return end
  local theme=Popup.theme(record,sign.section)
  local underwater=sign.weather==14 -- WEATHER_UNDERWATER_BUBBLES
  local paths=underwater and record.underwaterImages or record.images
  local colors=(underwater and record.underwaterColors or record.colors)[theme]
  local image=require("src.render.Assets").image(paths[theme])
  if not image then return end
  local Font=require("src.render.Font")
  love.graphics.setColor(1,1,1,1)
  love.graphics.draw(image,0,-sign.offset)
  local face=Font.pushFace("narrow")
  local function color(c) return {c[1]/255,c[2]/255,c[3]/255,1} end
  local two=Font.beginTwoTone(color(colors.ink),color(colors.shadow))
  Font.draw(sign.name,8+math.max(0,math.floor((80-Font.width(sign.name))/2)),11-sign.offset)
  if two then Font.endTwoTone() end
  if face then Font.popFace() end
  love.graphics.setColor(1,1,1,1)
end
return Popup
