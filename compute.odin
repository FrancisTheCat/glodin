package glodin

import "core:fmt"
import "core:os"
import "core:mem"
import "core:strings"

import gl "vendor:OpenGL"

Compute :: distinct Index

@(private)
computes: ^Generational_Array(_Compute)

@(private)
get_compute :: proc(compute: Compute) -> ^_Compute {
	return ga_get(computes, compute)
}

@(private)
get_compute_handle :: proc(compute: Compute) -> u32 {
	return ga_get(computes, compute).handle
}

_get_compute_handle :: proc(compute: Compute) -> u32 {
	return get_compute_handle(compute)
}

@(private)
_Compute :: struct {
	using base: Base_Program,
}

create_compute_file :: proc(
	path: string,
	location := #caller_location,
) -> (
	compute: Compute,
	ok:      bool,
) {
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil {
		return
	}
	return create_compute_source(string(data), location)
}

create_compute_source :: proc(
	source: string,
	location := #caller_location,
) -> (
	compute: Compute,
	ok: bool,
) {
	id := Compute(ga_append(computes, _Compute{}))
	c  := ga_get(computes, id)

	mem.dynamic_arena_init(&c.arena, alignment = 64)
	c.textures.allocator = mem.dynamic_arena_allocator(&c.arena)

	c.handle, ok = gl.load_compute_source(source)
	if !ok {
		error("Failed to compile progam:", gl.get_last_error_messages(), location = location)
		return
	}
	get_uniforms_from_program(c)
	get_uniform_blocks_from_program(c, location)
	return id, true
}

dispatch_compute :: proc(
	compute: Compute,
	groups: [3]int,
	uniforms: []Uniform,
	location := #caller_location,
) {
	c := get_compute(compute)

	gl.UseProgram(c.handle)
	current_program = max(Program)

	for uniform in uniforms {
		set_uniform(&c.base, uniform, location)
	}

	bind_program_textures(c, location)

	gl.DispatchCompute(u32(groups.x), u32(groups.y), u32(groups.z))
	gl.MemoryBarrier(gl.SHADER_IMAGE_ACCESS_BARRIER_BIT)
}

destroy_compute :: proc(compute: Compute) {
	c := get_compute(compute)
	mem.dynamic_arena_destroy(&c.arena)
	gl.DeleteProgram(c.handle)
	ga_remove(computes, compute)
}


import hep "hephaistos"
import hep_types "hephaistos/types"

@(private, require_results)
compile_shader_hephaistos :: proc(
	source:        string,
	defines:       map[string]hep.Const_Value = {},
	shared_types:  []typeid                   = {},
	allocator       := context.allocator,
	error_allocator := context.allocator,
) -> (code: []u32, reflection_info: map[string]hep.Reflection_Info, errors: []hep.Error) {
	tokens: []hep.Token
	tokens, errors = hep.tokenize(source, false, context.temp_allocator, error_allocator)
	if len(errors) != 0 {
		return
	}

	stmts: []^hep.Ast_Stmt
	stmts, errors = hep.parse(tokens, context.temp_allocator, error_allocator)
	if len(errors) != 0 {
		return
	}

	checker: hep.Checker
	checker, errors = hep.check(stmts, defines, shared_types, true, true, context.temp_allocator, error_allocator)
	if len(errors) != 0 {
		return
	}

	reflection_info = checker.reflection.data

	code = hep.cg_generate(&checker, stmts, nil, source, hep.SPIR_V_VERSION_1_0, allocator = allocator)

	return
}

create_compute_hephaistos :: proc(
	source:       string,
	path:         string                     = "",
	defines:      map[string]hep.Const_Value = {},
	shared_types: []typeid                   = {},
) -> (compute: Compute, ok: bool) {
	spirv, reflection_info, errors := compile_shader_hephaistos(source, defines, shared_types)
	lines := strings.split_lines(source)
	if len(errors) != 0 {
		for error in errors {
			hep.print_error(os.to_stream(os.stderr), path, lines, error)
		}
		return
	}

	id := Compute(ga_append(computes, _Compute{}))
	c  := ga_get(computes, id)

	mem.dynamic_arena_init(&c.arena, alignment = 64)

	c.textures.allocator = mem.dynamic_arena_allocator(&c.arena)

	shader := gl.CreateShader(gl.COMPUTE_SHADER)
	defer gl.DeleteShader(shader)

	gl.ShaderBinary(1, &shader, gl.SHADER_BINARY_FORMAT_SPIR_V, raw_data(spirv), i32(len(spirv)) * size_of(u32))

	_ = os.write_entire_file("a.spv", mem.slice_to_bytes(spirv))

	c.handle = gl.CreateProgram()

	gl.SpecializeShader(shader, "main", 0, nil, nil)
	gl.AttachShader(c.handle, shader)
	gl.LinkProgram(c.handle)

	status: i32
	gl.GetProgramiv(c.handle, gl.LINK_STATUS, &status)

	allocator       := mem.dynamic_arena_allocator(&c.arena)
	c.uniforms       = make(Uniforms, len(reflection_info), allocator)
	c.uniform_blocks = make([]Uniform_Buffer_Block, len(reflection_info), allocator)

	gl.GetProgramiv(c.handle, gl.LINK_STATUS, &status)
	if status == 0 {
		max_length: i32
		gl.GetProgramiv(c.handle, gl.INFO_LOG_LENGTH, &max_length)
		error_log := make([]u8, max_length)
		gl.GetProgramInfoLog(c.handle, max_length, &max_length, &error_log[0]);
		fmt.println(cstring(&error_log[0]))
		return
	}

	n_uniform_blocks := 0

	for name, info in reflection_info {
		switch info.interface {
		case .None:
		case .Uniform:
			hephaistos_type_to_gl :: proc(type: ^hep.Type) -> (gl_type: gl.Uniform_Type) {
				type := hep_types.base_type(type)

				#partial switch type.kind {
				case .Invalid, .Tuple, .Proc,  .Enum, .Bit_Set:
					panic("???")
				case .Uint:
					gl_type = .UNSIGNED_INT
				case .Int:
					gl_type = .INT
				case .Bool:
					gl_type = .BOOL
				case .Float:
					if type.size == 4 {
						gl_type = .FLOAT
					} else if type.size == 8 {
						gl_type = .DOUBLE
					}

				case .Struct:
					panic("Can not have struct uniforms, prefer using uniform buffers")
				case .Matrix:
					elem := hep_types.matrix_elem(type)
					#partial switch elem.kind {
					case .Float:
						if type.size == 4 {
							gl_type = .FLOAT_MAT4
						} else if type.size == 8 {
							gl_type = .DOUBLE_MAT4
						}
					}
					// TODO: non-4x4 matrices
				case .Vector:
					elem := hep_types.vector_elem(type)
					#partial switch elem.kind {
					case .Int:
						gl_type = .INT_VEC2
					case .Uint:
						gl_type = .UNSIGNED_INT_VEC2
					case .Bool:
						gl_type = .BOOL_VEC2
					case .Float:
						if type.size == 4 {
							gl_type = .FLOAT_VEC2
						} else if type.size == 8 {
							gl_type = .DOUBLE_VEC2
						}
					}

					gl_type += auto_cast (hep_types.vector_len(type) - 2)
				case .Buffer:
					panic("Can not have buffer uniforms, prefer using shader storage buffers")
				case .Sampler:
					sampler := type.variant.(^hep_types.Image)
					switch sampler.dimensions {
					case 1:
						gl_type = .SAMPLER_1D
					case 2:
						gl_type = .SAMPLER_2D
					case 3:
						gl_type = .SAMPLER_3D
					}
					texel := sampler.texel_type
					if texel.kind == .Vector {
						texel = hep_types.vector_elem(texel)
					}
					#partial switch sampler.texel_type.kind {
					case .Int:
						gl_type += gl.Uniform_Type.INT_SAMPLER_2D          - gl.Uniform_Type.SAMPLER_2D
					case .Uint:
						gl_type += gl.Uniform_Type.UNSIGNED_INT_SAMPLER_2D - gl.Uniform_Type.SAMPLER_2D
					}
				case .Image:
					image := type.variant.(^hep_types.Image)
					switch image.dimensions {
					case 1:
						gl_type = .IMAGE_1D
					case 2:
						gl_type = .IMAGE_2D
					case 3:
						gl_type = .IMAGE_3D
					}
					texel := image.texel_type
					if texel.kind == .Vector {
						texel = hep_types.vector_elem(texel)
					}
					#partial switch image.texel_type.kind {
					case .Int:
						gl_type += gl.Uniform_Type.INT_IMAGE_2D          - gl.Uniform_Type.IMAGE_2D
					case .Uint:
						gl_type += gl.Uniform_Type.UNSIGNED_INT_IMAGE_2D - gl.Uniform_Type.IMAGE_2D
					}
				}

				return
			}
			gl_type := hephaistos_type_to_gl(info.type)
			assert(gl_type != nil, "Something went wrong with determining uniform types, the implementation sucks. Using uniform buffers / shader storage buffers is much more reliable")
			c.uniforms[name] = {
				info = {
					location = i32(info.location),
					size     = i32(info.type.size),
					name     = name,
					kind     = gl_type,
				},
			}
		case .Uniform_Buffer, .Storage_Buffer:
			c.uniform_blocks[n_uniform_blocks] = {
				name    = name,
				binding = info.binding,
				size    = info.type.size,
				is_ssbo = info.interface == .Storage_Buffer,
			}
			n_uniform_blocks += 1
		case .Push_Constant:
			error("Push constants are not supported in OpenGL")
		}
	}

	c.uniform_blocks = c.uniform_blocks[:n_uniform_blocks]

	return id, true
}
