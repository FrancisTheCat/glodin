#version 450

layout(location = 0) out vec4 f_color;

void main() {
    f_color.rgb = vec3(0.8, 0.8, 0.7);
    f_color.a = 1;
}
