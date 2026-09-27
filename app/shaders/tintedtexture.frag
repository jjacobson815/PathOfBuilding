#version 440
layout(location = 0) in vec2 texCoord;
layout(location = 1) in vec4 color;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
};
layout(binding = 1) uniform sampler2D qt_Texture;
void main()
{
    // Texture is premultiplied; the tint is straight RGB with alpha, so
    // premultiply the tint's rgb by its alpha before modulating.
    fragColor = texture(qt_Texture, texCoord) * vec4(color.rgb * color.a, color.a);
}
