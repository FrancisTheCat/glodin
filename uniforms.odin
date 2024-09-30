package glodin

import glm "core:math/linalg/glsl"

import gl "vendor:OpenGL"

Uniform_Type :: union {
	f32,
	glm.vec2,
	glm.vec3,
	glm.vec4,
	glm.mat2,
	glm.mat3,
	glm.mat4,
	f64,
	glm.dvec2,
	glm.dvec3,
	glm.dvec4,
	glm.dmat2,
	glm.dmat3,
	glm.dmat4,
	i32,
	u32,
	bool,
	Texture,
}

Uniform :: struct {
	name: string,
	type: Uniform_Type,
}

@(private)
set_uniform :: proc(program: ^Base_Program, uniform: Uniform, location: Source_Code_Location) {
	p_uniform, ok := program.uniforms[uniform.name]
	if !ok {
		errorf("Invalid Uniform: %v with value: %v not found", uniform.name, uniform.type)
		return
	}
	loc := p_uniform.location
	#partial switch &u in uniform.type {
	case f32:
		assert_uniform_type(p_uniform.kind, .FLOAT, location)
		gl.Uniform1f(loc, u)
	case glm.vec2:
		assert_uniform_type(p_uniform.kind, .FLOAT_VEC2, location)
		gl.Uniform2f(loc, u.x, u.y)
	case glm.vec3:
		assert_uniform_type(p_uniform.kind, .FLOAT_VEC3, location)
		gl.Uniform3f(loc, u.x, u.y, u.z)
	case glm.vec4:
		assert_uniform_type(p_uniform.kind, .FLOAT_VEC4, location)
		gl.Uniform4f(loc, u.x, u.y, u.z, u.w)

	case glm.mat2:
		assert_uniform_type(p_uniform.kind, .FLOAT_MAT2, location)
		gl.UniformMatrix2fv(loc, 1, false, &u[0][0])
	case glm.mat3:
		assert_uniform_type(p_uniform.kind, .FLOAT_MAT3, location)
		gl.UniformMatrix3fv(loc, 1, false, &u[0][0])
	case glm.mat4:
		assert_uniform_type(p_uniform.kind, .FLOAT_MAT4, location)
		gl.UniformMatrix4fv(loc, 1, false, &u[0][0])

	case f64:
		assert_uniform_type(p_uniform.kind, .DOUBLE, location)
		gl.Uniform1d(loc, u)
	case glm.dvec2:
		assert_uniform_type(p_uniform.kind, .DOUBLE_VEC2, location)
		gl.Uniform2d(loc, u.x, u.y)
	case glm.dvec3:
		assert_uniform_type(p_uniform.kind, .DOUBLE_VEC3, location)
		gl.Uniform3d(loc, u.x, u.y, u.z)
	case glm.dvec4:
		assert_uniform_type(p_uniform.kind, .DOUBLE_VEC4, location)
		gl.Uniform4d(loc, u.x, u.y, u.z, u.w)

	case glm.dmat2:
		assert_uniform_type(p_uniform.kind, .DOUBLE_MAT2, location)
		gl.UniformMatrix2dv(loc, 1, false, &u[0][0])
	case glm.dmat3:
		assert_uniform_type(p_uniform.kind, .DOUBLE_MAT3, location)
		gl.UniformMatrix3dv(loc, 1, false, &u[0][0])
	case glm.dmat4:
		assert_uniform_type(p_uniform.kind, .DOUBLE_MAT4, location)
		gl.UniformMatrix4dv(loc, 1, false, &u[0][0])

	case i32:
		assert_uniform_type(p_uniform.kind, .INT, location)
		gl.Uniform1i(loc, u)
	case u32:
		assert_uniform_type(p_uniform.kind, .UNSIGNED_INT, location)
		gl.Uniform1ui(loc, u)
	case bool:
		assert_uniform_type(p_uniform.kind, .BOOL, location)
		gl.Uniform1i(loc, u ? 1 : 0)

	case Texture:
		tex := get_texture(u)
		assert(tex.samples == 0, "Cannot use multisampled texture as uniform", location)

		switch tex.kind {
		case .Texture_1D:
			assert_uniform_types(p_uniform.kind, {.SAMPLER_1D,       .IMAGE_1D},       location)
		case .Texture_2D:
			assert_uniform_types(p_uniform.kind, {.SAMPLER_2D,       .IMAGE_2D},       location)
		case .Texture_3D:
			assert_uniform_types(p_uniform.kind, {.SAMPLER_3D,       .IMAGE_3D},       location)
		case .Texture_Array:
			assert_uniform_types(p_uniform.kind, {.SAMPLER_2D_ARRAY, .IMAGE_2D_ARRAY}, location)
		case .Cube_Map:
			assert_uniform_types(p_uniform.kind, {.SAMPLER_CUBE,     .IMAGE_CUBE},     location)
		}

		register_texture: {
			for &texture in program.textures {
				if texture.location == p_uniform.location {
					texture.texture = u
					break register_texture
				}
			}

			append(&program.textures, Texture_Binding{
				location = p_uniform.location,
				texture  = u,
			})
		}

	case:
		panicf("Invalid uniform type: %T", u, location)
	}
}

@(private)
assert_uniform_types :: proc(
	kind: gl.Uniform_Type,
	shader_kinds: []gl.Uniform_Type,
	location := #caller_location,
) {
	for shader_kind in shader_kinds {
		if kind == shader_kind {
			return
		}
	}
	panicf(
		"Invalid Uniform: shader expected one of %v recieved %v",
		shader_kinds,
		kind,
		location = location,
	)
}

@(private)
assert_uniform_type :: proc(
	kind: gl.Uniform_Type,
	shader_kind: gl.Uniform_Type,
	location := #caller_location,
) {
	assertf(
		kind == shader_kind,
		"Invalid Uniform: shader expected %v recieved %v",
		shader_kind,
		kind,
		location = location,
	)
}

set_uniforms :: proc(program: Program, uniforms: []Uniform, location := #caller_location) {
	set_program_active(program)
	p := get_program(program)
	for uniform in uniforms {
		set_uniform(p, uniform, location)
	}
}

