#version 450
layout(push_constant) uniform Push {
 vec4 SourceSize;vec4 OriginalSize;vec4 PassOutputSize0;vec4 TintSize;vec4 OutputSize;vec4 FinalViewportSize;
} params;
layout(std140,set=0,binding=0) uniform UBO { mat4 MVP; } global;
#pragma stage vertex
layout(location=0) in vec4 Position;
layout(location=1) in vec2 TexCoord;
layout(location=0) out vec2 uv;
void main(){gl_Position=global.MVP*Position;uv=TexCoord;}
#pragma stage fragment
layout(location=0) in vec2 uv;
layout(location=0) out vec4 FragColor;
layout(set=0,binding=2) uniform sampler2D Source;
layout(set=0,binding=3) uniform sampler2D Original;
layout(set=0,binding=4) uniform sampler2D PassOutput0;
layout(set=0,binding=5) uniform sampler2D Tint;
void main(){
 vec4 c=texture(Source,uv);vec4 original=texture(Original,uv);vec4 first=texture(PassOutput0,uv);
 float sizes=params.SourceSize.x/params.OriginalSize.x+params.PassOutputSize0.x/params.OriginalSize.x;
 float outputRatio=params.OutputSize.y/params.FinalViewportSize.y;
 FragColor=vec4(c.r+original.r*0.25,first.g,texture(Tint,vec2(0.75,0.5)).b*sizes*outputRatio/6.0,original.a);
}
