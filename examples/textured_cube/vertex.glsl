layout (location = 0) in vec3 a_position;
layout (location = 1) in vec3 a_normal;
layout (location = 2) in vec2 a_tex_coords;

layout (location = 0) out vec3 v_position;
layout (location = 1) out vec3 v_normal;
layout (location = 2) out vec2 v_tex_coords;

uniform mat4 u_model;
uniform mat4 u_view;
uniform mat4 u_perspective;

void main() {
    v_tex_coords = a_tex_coords;
    v_normal     = transpose(inverse(mat3(u_model))) * a_normal;
    v_position   = vec3(u_model * vec4(a_position, 1));
    gl_Position  = u_perspective * u_view * vec4(v_position, 1);
}
