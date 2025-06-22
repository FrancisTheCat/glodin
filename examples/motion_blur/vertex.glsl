layout(location = 0) in  vec2 a_position;

layout(location = 0) out vec2 v_uv;

uniform vec2 u_position;
uniform vec2 u_scale;

void main() {
    v_uv = a_position;
    gl_Position = vec4(u_position + u_scale * (a_position * 2 - 1), 0, 1);
}
