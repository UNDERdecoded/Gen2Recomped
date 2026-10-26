#version 450
#pragma parameter gain "GAIN" 0.5 0.0 1.0 0.1
layout(push_constant) uniform Push { float gain; } params;
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
void main(){vec4 c=texture(Source,uv);FragColor=vec4(c.r*params.gain,c.g,c.b,c.a);}
