local U={chars={},codes={},fonts={},next=-1}
function U.configure(language)
 U.path=nil;U.fonts={}
 if not language or language=="original"then return true end
 local name=require("src.translation.Languages").font(language)
 local path="translations/fonts/"..name
 if love.filesystem.getInfo(path)then U.path=path;return true end
 return false
end
function U.code(char)
 if not U.path then return nil end
 local code=U.codes[char]
 if not code then code=U.next;U.next=U.next-1;U.codes[char]=code;U.chars[code]=char end
 return code
end
function U.active() return U.path~=nil end
function U.font(height)
 if not U.path then return nil end
 height=math.max(8,tonumber(height) or 8)
 local font=U.fonts[height]
 if not font then font=love.graphics.newFont(U.path,height);U.fonts[height]=font end
 return font
end
function U.width(code,height)
 local font=U.font(height)
 return font and math.max(1,font:getWidth(U.chars[code] or "?")) or height
end
function U.draw(code,x,y,height)
 local font=U.font(height)
 if not font then return end
 local old=love.graphics.getFont()
 love.graphics.setFont(font)
 love.graphics.print(U.chars[code] or "?",x,y)
 love.graphics.setFont(old)
end
return U
