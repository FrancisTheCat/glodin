layout(location = 0) in  vec2 v_uv;

layout(location = 0) out vec4 f_color;

uniform sampler2D u_texture;

void main() {
    f_color = texture(u_texture, vec2(0, 1) + v_uv * vec2(1, -1));
}
