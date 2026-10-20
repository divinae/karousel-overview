#version 440
// rounds the corners of a layer, without the mask texture that OpacityMask needs
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float radius;
};
layout(binding = 1) uniform sampler2D source;

void main() {
    // signed distance to the rounded rectangle, antialiased over one pixel
    // at most half the smaller side, like a rounded Rectangle, small items aren't turned into pills
    float r = min(radius, 0.5 * min(itemSize.x, itemSize.y));
    vec2 q = abs((qt_TexCoord0 - 0.5) * itemSize) - itemSize * 0.5 + r;
    float distance = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    fragColor = texture(source, qt_TexCoord0) * clamp(0.5 - distance, 0.0, 1.0) * qt_Opacity;
}
