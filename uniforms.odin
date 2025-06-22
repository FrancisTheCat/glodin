package glodin

import "base:intrinsics"

import glm "core:math/linalg/glsl"
import "core:reflect"
import "core:hash"

import gl "vendor:OpenGL"

Uniform_Buffer :: distinct Index

@(private)
uniform_buffers: ^Generational_Array(_Uniform_Buffer)

@(private)
_Uniform_Buffer :: struct {
	handle:  u32,
	type:    typeid,
	using _: bit_field int {
		len:     int  | 63,
		is_ssbo: bool | 1,
	},
}

@(private)
get_uniform_buffer :: proc(ub: Uniform_Buffer) -> ^_Uniform_Buffer {
	return ga_get(uniform_buffers, ub)
}

@(private)
max_uniform_buffer_size: int
@(private)
max_shader_storage_buffer_size: int

create_uniform_buffer :: proc(data: []$T, location := #caller_location) -> Uniform_Buffer {
	// when intrinsics.type_is_struct(T) {
	// 	#assert(
	// 		!intrinsics.type_struct_has_implicit_padding(T),
	// 		"Struct types passed in uniform buffers can not have implicit padding",
	// 	)
	// }
	ub: _Uniform_Buffer
	ub.type = T
	ub.len = len(data) * size_of(T)
	gl.CreateBuffers(1, &ub.handle)
	// just use storage buffers everywhere even tho they are slower, because switching between them in a macro isn't possible so we'd have to add our own preprocessor, so uhh TODO!
	if ub.len > max_uniform_buffer_size * 0 {
		gl.NamedBufferStorage(
			ub.handle,
			ub.len,
			raw_data(data),
			gl.DYNAMIC_STORAGE_BIT,
		)
	} else if ub.len < max_shader_storage_buffer_size {
		gl.NamedBufferStorage(
			ub.handle,
			ub.len,
			raw_data(data),
			gl.DYNAMIC_STORAGE_BIT,
		)
		ub.is_ssbo = true
	} else {
		panicf(
			"Size of uniform buffer %m exceeds maximum size of %m",
			ub.len,
			max_uniform_buffer_size,
			location = location,
		)
	}
	// assert(is_valid_uniform_buffer_elem_type(type_info_of(T)), location = location)
	return Uniform_Buffer(ga_append(uniform_buffers, ub))
}

is_valid_uniform_buffer_elem_type :: proc(type: ^reflect.Type_Info) -> bool {
	type := reflect.type_info_core(type)

	#partial switch v in type.variant {
	case reflect.Type_Info_Array:
		return v.count != 3 && is_valid_uniform_buffer_elem_type(v.elem)
	case reflect.Type_Info_Matrix:
		return v.row_count != 3 && v.column_count != 3 && is_valid_uniform_buffer_elem_type(v.elem)

	case reflect.Type_Info_Float:
		return true
	case reflect.Type_Info_Integer:
		return true
	case reflect.Type_Info_Complex:
		return true
	case reflect.Type_Info_Quaternion:
		return true
	case reflect.Type_Info_Struct:
		current_offset: uintptr = 0
		for f in reflect.struct_fields_zipped(type.id) {
			if f.offset != current_offset {
				return false
			}
			current_offset += uintptr(f.type.size)
		}
		return current_offset == uintptr(type.size)
	case:
		return false
	}
	unreachable()
}

set_uniform_buffer_data :: proc(ub: Uniform_Buffer, data: []$T, offset: int = 0, location := #caller_location) {
	ub := get_uniform_buffer(ub)
	assertf(
		ub.type == T,
		"Data type to update uniform buffer with (%v) differs from type that it was initialized with (%v)",
		typeid_of(T),
		ub.type,
		location = location,
	)
	assert(len(data) + offset <= ub.len, location = location)
	gl.NamedBufferSubData(ub.handle, offset, len(data) * size_of(T), raw_data(data))
}

destroy_uniform_buffer :: proc(ub: Uniform_Buffer) {
	{
		ub := get_uniform_buffer(ub)
		gl.DeleteBuffers(1, &ub.handle)
	}

	ga_remove(uniform_buffers, ub)
}

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
	glm.ivec2,
	glm.ivec3,
	glm.ivec4,
	u32,
	glm.uvec2,
	glm.uvec3,
	glm.uvec4,
	bool,
	Texture,
	Uniform_Buffer,
}

Uniform :: struct {
	name: string,
	type: Uniform_Type,
}

@(private)
Uniforms :: map[string]struct {
	using info: gl.Uniform_Info,
	hash:       u64,
}

@(private)
hash_uniform :: proc(u: Uniform_Type) -> u64 {
	#partial switch _ in u {
	case Texture:
		return 0
	case Uniform_Buffer:
		return 0
	}
	u    := u
	data := ([^]byte)(&u)[:reflect.union_variant_type_info(u).size]
	return hash.fnv64a(data)
}

@(private)
set_uniform :: proc(program: ^Base_Program, uniform: Uniform, location: Source_Code_Location) {
	p_uniform, ok := &program.uniforms[uniform.name]

	if !ok {
		if ub, ok := uniform.type.(Uniform_Buffer); ok {
			ub := get_uniform_buffer(ub)
			for block in program.uniform_blocks {
				if block.name == uniform.name {
					assertf(
						block.size == ub.len,
						"Uniform buffer `%v` has incorrect size: %v, expected %v",
						block.name,
						ub.len,
						block.size,
						location = location,
					)
					if ub.is_ssbo {
						gl.BindBufferBase(gl.UNIFORM_BUFFER,        u32(block.binding), ub.handle)
					} else {
						gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, u32(block.binding), ub.handle)
					}
					return
				}
			}
		}
		errorf("Invalid Uniform: %v with value: %v not found", uniform.name, uniform.type, location = location)
		return
	}

	hash := hash_uniform(uniform.type)
	if p_uniform.hash != 0 {
		if hash == p_uniform.hash {
			return
		}
	}
	p_uniform.hash = hash

	loc := p_uniform.location
	#partial switch &u in uniform.type {
	case f32:
		assert_uniform_type(p_uniform.kind, .FLOAT, location)
		gl.ProgramUniform1f(program.handle, loc, u)
	case glm.vec2:
		assert_uniform_type(p_uniform.kind, .FLOAT_VEC2, location)
		gl.ProgramUniform2f(program.handle, loc, u.x, u.y)
	case glm.vec3:
		assert_uniform_type(p_uniform.kind, .FLOAT_VEC3, location)
		gl.ProgramUniform3f(program.handle, loc, u.x, u.y, u.z)
	case glm.vec4:
		assert_uniform_type(p_uniform.kind, .FLOAT_VEC4, location)
		gl.ProgramUniform4f(program.handle, loc, u.x, u.y, u.z, u.w)

	case glm.mat2:
		assert_uniform_type(p_uniform.kind, .FLOAT_MAT2, location)
		gl.ProgramUniformMatrix2fv(program.handle, loc, 1, false, &u[0][0])
	case glm.mat3:
		assert_uniform_type(p_uniform.kind, .FLOAT_MAT3, location)
		gl.ProgramUniformMatrix3fv(program.handle, loc, 1, false, &u[0][0])
	case glm.mat4:
		assert_uniform_type(p_uniform.kind, .FLOAT_MAT4, location)
		gl.ProgramUniformMatrix4fv(program.handle, loc, 1, false, &u[0][0])

	case f64:
		assert_uniform_type(p_uniform.kind, .DOUBLE, location)
		gl.ProgramUniform1d(program.handle, loc, u)
	case glm.dvec2:
		assert_uniform_type(p_uniform.kind, .DOUBLE_VEC2, location)
		gl.ProgramUniform2d(program.handle, loc, u.x, u.y)
	case glm.dvec3:
		assert_uniform_type(p_uniform.kind, .DOUBLE_VEC3, location)
		gl.ProgramUniform3d(program.handle, loc, u.x, u.y, u.z)
	case glm.dvec4:
		assert_uniform_type(p_uniform.kind, .DOUBLE_VEC4, location)
		gl.ProgramUniform4d(program.handle, loc, u.x, u.y, u.z, u.w)

	case glm.dmat2:
		assert_uniform_type(p_uniform.kind, .DOUBLE_MAT2, location)
		gl.ProgramUniformMatrix2dv(program.handle, loc, 1, false, &u[0][0])
	case glm.dmat3:
		assert_uniform_type(p_uniform.kind, .DOUBLE_MAT3, location)
		gl.ProgramUniformMatrix3dv(program.handle, loc, 1, false, &u[0][0])
	case glm.dmat4:
		assert_uniform_type(p_uniform.kind, .DOUBLE_MAT4, location)
		gl.ProgramUniformMatrix4dv(program.handle, loc, 1, false, &u[0][0])

	case i32:
		assert_uniform_type(p_uniform.kind, .INT, location)
		gl.ProgramUniform1i(program.handle, loc, u)
	case glm.ivec2:
		assert_uniform_type(p_uniform.kind, .INT_VEC2, location)
		gl.ProgramUniform4iv(program.handle, loc, 1, &u[0])
	case glm.ivec3:
		assert_uniform_type(p_uniform.kind, .INT_VEC3, location)
		gl.ProgramUniform4iv(program.handle, loc, 1, &u[0])
	case glm.ivec4:
		assert_uniform_type(p_uniform.kind, .INT_VEC4, location)
		gl.ProgramUniform4iv(program.handle, loc, 1, &u[0])

	case u32:
		assert_uniform_type(p_uniform.kind, .UNSIGNED_INT, location)
		gl.ProgramUniform1ui(program.handle, loc, u)
	case glm.uvec2:
		assert_uniform_type(p_uniform.kind, .UNSIGNED_INT_VEC2, location)
		gl.ProgramUniform4uiv(program.handle, loc, 1, &u[0])
	case glm.uvec3:
		assert_uniform_type(p_uniform.kind, .UNSIGNED_INT_VEC3, location)
		gl.ProgramUniform4uiv(program.handle, loc, 1, &u[0])
	case glm.uvec4:
		assert_uniform_type(p_uniform.kind, .UNSIGNED_INT_VEC4, location)
		gl.ProgramUniform4uiv(program.handle, loc, 1, &u[0])

	case bool:
		assert_uniform_type(p_uniform.kind, .BOOL, location)
		gl.ProgramUniform1i(program.handle, loc, u ? 1 : 0)

	case Texture:
		tex := get_texture(u)
		assert(tex.samples == 0, "Cannot use multisampled texture as uniform", location)

		switch tex.kind {
		case .Texture_1D:
			assert_uniform_types(
				p_uniform.kind,
				{
					.SAMPLER_1D,
					.IMAGE_1D,
					.INT_SAMPLER_1D,
					.INT_IMAGE_1D,
					.UNSIGNED_INT_SAMPLER_1D,
					.UNSIGNED_INT_IMAGE_1D,
				},
				location,
			)
		case .Texture_2D:
			assert_uniform_types(
				p_uniform.kind,
				{
					.SAMPLER_2D,
					.IMAGE_2D,
					.INT_SAMPLER_2D,
					.INT_IMAGE_2D,
					.UNSIGNED_INT_SAMPLER_2D,
					.UNSIGNED_INT_IMAGE_2D,
				},
				location,
			)
		case .Texture_3D:
			assert_uniform_types(
				p_uniform.kind,
				{
					.SAMPLER_3D,
					.IMAGE_3D,
					.INT_SAMPLER_3D,
					.INT_IMAGE_3D,
					.UNSIGNED_INT_SAMPLER_3D,
					.UNSIGNED_INT_IMAGE_3D,
				},
				location,
			)
		case .Texture_1D_Array:
			assert_uniform_types(
				p_uniform.kind,
				{
					.SAMPLER_1D_ARRAY,
					.IMAGE_1D_ARRAY,
					.INT_SAMPLER_1D_ARRAY,
					.INT_IMAGE_1D_ARRAY,
					.UNSIGNED_INT_SAMPLER_1D_ARRAY,
					.UNSIGNED_INT_IMAGE_1D_ARRAY,
				},
				location,
			)
		case .Texture_2D_Array:
			assert_uniform_types(
				p_uniform.kind,
				{
					.SAMPLER_2D_ARRAY,
					.IMAGE_2D_ARRAY,
					.INT_SAMPLER_2D_ARRAY,
					.INT_IMAGE_2D_ARRAY,
					.UNSIGNED_INT_SAMPLER_2D_ARRAY,
					.UNSIGNED_INT_IMAGE_2D_ARRAY,
				},
				location,
			)
		case .Cube_Map:
			assert_uniform_types(
				p_uniform.kind,
				{
					.SAMPLER_CUBE,
					.IMAGE_CUBE,
					.INT_SAMPLER_CUBE,
					.INT_IMAGE_CUBE,
					.UNSIGNED_INT_SAMPLER_CUBE,
					.UNSIGNED_INT_IMAGE_CUBE,
				},
				location,
			)
		case .Cube_Map_Array:
			assert_uniform_types(
				p_uniform.kind,
				{
					.SAMPLER_CUBE,
					.IMAGE_CUBE,
					.INT_SAMPLER_CUBE,
					.INT_IMAGE_CUBE,
					.UNSIGNED_INT_SAMPLER_CUBE,
					.UNSIGNED_INT_IMAGE_CUBE,
				},
				location,
			)
		}

		register_texture: {
			for &texture in program.textures {
				if texture.location == p_uniform.location {
					texture.texture = u
					break register_texture
				}
			}

			append(&program.textures, Texture_Binding{location = p_uniform.location, texture = u})
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
	p := get_program(program)
	for uniform in uniforms {
		set_uniform(p, uniform, location)
	}
}

set_uniforms_from_struct :: proc(program: Program, uniforms: $U, location := #caller_location) {
	p := get_program(program)
	uniforms := uniforms
	for field in reflect.struct_fields_zipped(U) {
		f: any = {
			data = rawptr(uintptr(&uniforms) + field.offset),
			id   = field.type.id,
		}
		u: Uniform
		u.name = field.name

		if tag, ok := reflect.struct_tag_lookup(field.tag, "glodin-uniform"); ok {
			if tag == "-" {
				continue
			}
			u.name = tag
		}

		switch v in f {
		case f32:
			u.type = v
		case glm.vec2:
			u.type = v
		case glm.vec3:
			u.type = v
		case glm.vec4:
			u.type = v
		case glm.mat2:
			u.type = v
		case glm.mat3:
			u.type = v
		case glm.mat4:
			u.type = v
		case f64:
			u.type = v
		case glm.dvec2:
			u.type = v
		case glm.dvec3:
			u.type = v
		case glm.dvec4:
			u.type = v
		case glm.dmat2:
			u.type = v
		case glm.dmat3:
			u.type = v
		case glm.dmat4:
			u.type = v
		case i32:
			u.type = v
		case glm.ivec2:
			u.type = v
		case glm.ivec3:
			u.type = v
		case glm.ivec4:
			u.type = v
		case u32:
			u.type = v
		case glm.uvec2:
			u.type = v
		case glm.uvec3:
			u.type = v
		case glm.uvec4:
			u.type = v
		case bool:
			u.type = v
		case Texture:
			u.type = v
		case Uniform_Buffer:
			u.type = v
		case:
			warnf(
				"Uniform struct field '%v' is of type '%v', which is not a valid uniform type",
				field.name,
				field.type.id,
				location = location,
			)
			continue
		}
		set_uniform(p, u, location)
	}
}
