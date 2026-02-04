layout (local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

layout(rgba8) uniform image2D   img_output;
              uniform sampler2D img_noise;

#define Cmplx vec2

Cmplx cmul(Cmplx a, Cmplx b) {
    return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

void main() {
    ivec2 texel_coord = ivec2(gl_GlobalInvocationID.xy);

    vec2 uv = vec2(
        float(texel_coord.x) / (gl_NumWorkGroups.x),
        float(texel_coord.y) / (gl_NumWorkGroups.y)
    );

    uv *= 2;
    uv -= 1;

    float aspect = float(imageSize(img_output).x) / float(imageSize(img_output).y);
    uv.y /= aspect;

    uv *= 0.5;
    uv += 0.5;

    Cmplx c = Cmplx(-0.4, 0.6);
    Cmplx z = 3 * (uv - 0.5);

    float i = 0;
    while (i < 255 && length(z) < 2) {
        z = cmul(z, z) + c;
        i += 1;
    }

    // add some noise to reduce banding
    const float NOISE = 5;
    float t = (i - log2(max(length(z), 1)) + (texture(img_noise, uv).r - 0.5) * NOISE) / 256.0;

    vec4 value = vec4(mix(vec3(0.1), vec3(92 / 255.0, 162 / 255.0, 219 / 255.0), t), 1);
    // vec4 value = vec4(mix(vec3(0.1), vec3(228 / 255.0, 146 / 255.0, 99 / 255.0), t), 1);

    imageStore(img_output, texel_coord, value);
}
