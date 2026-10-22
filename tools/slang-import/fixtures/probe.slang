#version 450
// Original ROM-free test shader. Also exercises includes, parameters and a vertex varying.
#include "probe.inc"
#pragma parameter gain "GAIN" 1.0 0.0 1.0 0.1
#pragma parameter unused "UNUSED PARAMETER" 0.5 0.0 1.0 0.1
layout(push_constant) uniform Push {
    vec4 SourceSize;
    vec4 OriginalSize;
    vec4 OutputSize;
    vec4 FinalViewportSize;
    float gain;
    float unused;
} params;
layout(std140, set=0, binding=0) uniform UBO { mat4 MVP; } global;
#pragma stage vertex
layout(location=0) in vec4 Position;
layout(location=1) in vec2 TexCoord;
layout(location=0) out vec2 sourcePixel;
void main() {
    gl_Position = global.MVP * Position;
    sourcePixel = TexCoord * params.SourceSize.xy;
}
#pragma stage fragment
layout(location=0) in vec2 sourcePixel;
layout(location=0) out vec4 FragColor;
layout(set=0, binding=2) uniform sampler2D Source;
layout(set=0, binding=3) uniform sampler2D Original;
void main() {
    vec2 uv = sourcePixel * params.OriginalSize.zw;
    vec4 c = (texture(Source, uv) + texture(Original, uv)) * 0.5;
    FragColor = vec4(probeGain(c.r, params.gain), params.SourceSize.x / 64.0,
                    (params.OutputSize.y + params.FinalViewportSize.y) / 512.0, c.a);
}
