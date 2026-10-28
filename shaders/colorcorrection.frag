#version 440
// KWin's color blindness correction, which it applies to each window as it draws it, so not to the overview, which
// draws them itself: the same, over the whole overview, see KWin's colorblindnesscorrection.frag; in linear light,
// as KWin does it
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // 1 protanopia, 2 deuteranopia, 3 tritanopia, 4 monochrome
    int mode;
    float intensity;
};
layout(binding = 1) uniform sampler2D source;

const mat3 srgbToLMS = mat3(
    17.8824, 3.45565, 0.0299566,
    43.5161, 27.1554, 0.184309,
    4.11935, 3.86714, 1.46709
);
const mat3 errorMat = mat3(
    0.0809444479, -0.0102485335, -0.000365296938,
   -0.130504409,   0.0540193266, -0.00412161469,
    0.116721066,  -0.113614708,   0.693511405
);

vec3 toLinear(vec3 color) {
    return mix(color / 12.92, pow((color + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), color));
}

vec3 toSrgb(vec3 color) {
    return mix(color * 12.92, 1.055 * pow(color, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), color));
}

void main() {
    vec4 tex = texture(source, qt_TexCoord0);
    // the layer's colors are premultiplied
    vec3 color = toLinear(tex.a > 0.0 ? tex.rgb / tex.a : vec3(0.0));
    if (mode == 4) {
        float y = dot(color, vec3(0.2126, 0.7152, 0.0722));
        color = mix(color, vec3(y), intensity);
    } else {
        // the columns of KWin's defect matrices
        mat3 defect = mode == 2 ? mat3(1.0, 0.494207, 0.0, 0.0, 0.0, 0.0, 0.0, 1.24827, 1.0)
            : mode == 3 ? mat3(1.0, 0.0, -0.395913, 0.0, 1.0, 0.801109, 0.0, 0.0, 0.0)
            : mat3(0.0, 0.0, 0.0, 2.02344, 1.0, 0.0, -2.52581, 0.0, 1.0);
        vec3 error = errorMat * (defect * (srgbToLMS * color));
        vec3 diff = (color - error) * intensity;
        color += vec3(0.0, diff.r * 0.7 + diff.g, diff.r * 0.7 + diff.b);
    }
    fragColor = vec4(toSrgb(clamp(color, 0.0, 1.0)) * tex.a, tex.a) * qt_Opacity;
}
