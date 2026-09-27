#version 440
// Rebuild both .qsb files after editing either source (qsb = Qt Shader Baker):
//   qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o tintedtexture.vert.qsb tintedtexture.vert
//   qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o tintedtexture.frag.qsb tintedtexture.frag
// TreeScene tinted-texture material (Phase 4 Part 4.3): legacy SetDrawColor
// multiplies every tree sprite by a colour (heat map, compare, dependents).
layout(location = 0) in vec4 vertexCoord;
layout(location = 1) in vec2 vertexTexCoord;
layout(location = 2) in vec4 vertexColor;
layout(location = 0) out vec2 texCoord;
layout(location = 1) out vec4 color;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
};
void main()
{
    texCoord = vertexTexCoord;
    color = vertexColor * qt_Opacity;
    gl_Position = qt_Matrix * vertexCoord;
}
