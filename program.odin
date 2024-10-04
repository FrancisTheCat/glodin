package glodin

import "base:runtime"

import "core:os"
import "core:reflect"
import "core:strings"

import gl "vendor:OpenGL"

@(private)
program_data_allocator: runtime.Allocator

Program :: distinct Index

@(private)
programs: ^Generational_Array(_Program)

@(private)
get_program :: proc(program: Program) -> ^_Program {
	return ga_get(programs, program)
}

@(private)
get_program_handle :: proc(program: Program) -> u32 {
	return ga_get(programs, program).handle
}

_get_program_handle :: proc(program: Program) -> u32 {
	return get_program_handle(program)
}

@(private)
Attribute :: struct {
	name:     string,
	size:     i32,
	location: i32,
	type:     Attribute_Type,
}

@(private)
_Program :: struct {
	using base:           Base_Program,
	valid_vertex_types:   [dynamic]typeid,
	valid_instance_types: [dynamic]typeid,
	attributes:           []Attribute,
}

@(private)
Texture_Binding :: struct {
	location: i32,
	texture:  Texture,
}

@(private)
Uniform_Buffer_Block :: struct {
	name:      string,
	binding:   int,
	size:      int,
}

@(private)
Base_Program :: struct {
	handle:         u32,
	uniforms:       gl.Uniforms,
	uniform_blocks: []Uniform_Buffer_Block,
	textures:       #soa[dynamic]Texture_Binding,
}

@(private)
check_program_vertex_type :: proc(
	program: ^_Program,
	vertex_type: typeid,
	instance_type: typeid,
	location: Source_Code_Location,
) {
	for valid in program.valid_vertex_types {
		if valid == vertex_type {
			return
		}
	}
	for valid in program.valid_instance_types {
		if valid == instance_type {
			return
		}
	}

	type_to_attribute_type :: proc(ti: ^reflect.Type_Info) -> (type: Attribute_Type) {
		ti := reflect.type_info_base(ti)
		#partial switch v in ti.variant {
		case reflect.Type_Info_Float:
			switch ti.size {
			case 2:
				panic("Half precision floats are not supported as vertex attributes")
			case 4:
				return .Float
			case 8:
				return .Double
			case:
				unreachable()
			}
		case reflect.Type_Info_Integer:
			assert(ti.size == 4, "Integer vertex attributes have to be 4 bytes")
			return v.signed ? .Int : .Unsigned_Int
		case reflect.Type_Info_Array:
			switch v.count {
			case 2 ..= 4:
				elem := type_to_attribute_type(v.elem)
				#partial switch elem {
				case .Float:
					return Attribute_Type(v.count - 2) + .Float_Vec2
				case .Double:
					return Attribute_Type(v.count - 2) + .Double_Vec2
				case .Int:
					return Attribute_Type(v.count - 2) + .Int_Vec2
				case .Unsigned_Int:
					return Attribute_Type(v.count - 2) + .Unsigned_Int_Vec2
				case:
					unreachable()
				}
			case:
				panic("Invalid array length for vertex attribute:", v.count)
			}
		case reflect.Type_Info_Matrix:
			elem := type_to_attribute_type(v.elem)

			if v.column_count == v.row_count {
				#partial switch elem {
				case .Float:
					return Attribute_Type(v.column_count - 2) + .Float_Mat2
				case .Double:
					return Attribute_Type(v.column_count - 2) + .Double_Mat2
				case:
					unreachable()
				}
			}

			get_matrix_offset :: proc(rows, cols: int) -> u32 {
				tuple := [2]int{rows, cols}
				switch tuple {
				case {2, 3}:
					return 0
				case {2, 4}:
					return 1
				case {3, 2}:
					return 2
				case {3, 4}:
					return 3
				case {4, 2}:
					return 4
				case {4, 3}:
					return 5
				case:
					unreachable()
				}
			}

			#partial switch elem {
			case .Float:
				return Attribute_Type(get_matrix_offset(v.row_count, v.column_count)) + .Float_Mat2
			case .Double:
				return(
					Attribute_Type(get_matrix_offset(v.row_count, v.column_count)) +
					.Double_Mat2 \
				)
			case:
				unreachable()
			}
		case:
			panic("Invalid vertex attribute type:", ti.id)
		}
	}

	for field, i in reflect.struct_fields_zipped(vertex_type) {
		at_type := type_to_attribute_type(reflect.type_info_base(field.type))

		if i >= len(program.attributes) {
			warnf(
				"Unused vertex attribute at index: %v, type: %v, field name: `%v`",
				i,
				field.type,
				field.name,
				location = location,
			)
			continue
		}

		attrib := program.attributes[i]

		if attrib.type == nil {
			warnf(
				"Unused vertex attribute at index: %v, type: %v, field name: `%v`",
				i,
				field.type,
				field.name,
				location = location,
			)
			continue
		}

		if attrib.type != at_type {
			errorf(
				"Program attribute `%v`(`%v`) at index %v expects type %v and size %v, but vertex buffer contains data of type %v(%v)",
				attrib.name,
				field.name,
				i,
				attrib.type,
				attrib.size,
				at_type,
				field.type,
				location = location,
			)
		}
	}

	append(&program.valid_vertex_types, vertex_type)
}

create_program_file :: proc(
	vertex_path, fragment_path: string,
	location := #caller_location,
) -> (
	program: Program,
	ok: bool,
) {
	fragment_source := string(os.read_entire_file(fragment_path) or_return)
	vertex_source := string(os.read_entire_file(vertex_path) or_return)
	return create_program_source(vertex_source, fragment_source, location)
}

create_program_source :: proc(
	vertex_source, fragment_source: string,
	location := #caller_location,
) -> (
	program: Program,
	ok: bool,
) {
	p: _Program
	p.handle, ok = gl.load_shaders_source(vertex_source, fragment_source)
	if !ok {
		error("Failed to compile progam:", gl.get_last_error_messages(), location = location)
		return
	}
	context.allocator = program_data_allocator
	p.uniforms        = gl.get_uniforms_from_program(p.handle)
	p.uniform_blocks  = get_uniform_blocks_from_program(p.handle)
	p.attributes      = get_attributes_from_program(p.handle)

	return Program(ga_append(programs, p)), true
}

@(private)
Attribute_Type :: enum {
	Float             = gl.FLOAT,
	Float_Vec2        = gl.FLOAT_VEC2,
	Float_Vec3        = gl.FLOAT_VEC3,
	Float_Vec4        = gl.FLOAT_VEC4,
	Float_Mat2        = gl.FLOAT_MAT2,
	Float_Mat3        = gl.FLOAT_MAT3,
	Float_Mat4        = gl.FLOAT_MAT4,
	Float_Mat2x3      = gl.FLOAT_MAT2x3,
	Float_Mat2x4      = gl.FLOAT_MAT2x4,
	Float_Mat3x2      = gl.FLOAT_MAT3x2,
	Float_Mat3x4      = gl.FLOAT_MAT3x4,
	Float_Mat4x2      = gl.FLOAT_MAT4x2,
	Float_Mat4x3      = gl.FLOAT_MAT4x3,
	Int               = gl.INT,
	Int_Vec2          = gl.INT_VEC2,
	Int_Vec3          = gl.INT_VEC3,
	Int_Vec4          = gl.INT_VEC4,
	Unsigned_Int      = gl.UNSIGNED_INT,
	Unsigned_Int_Vec2 = gl.UNSIGNED_INT_VEC2,
	Unsigned_Int_Vec3 = gl.UNSIGNED_INT_VEC3,
	Unsigned_Int_Vec4 = gl.UNSIGNED_INT_VEC4,
	Double            = gl.DOUBLE,
	Double_Vec2       = gl.DOUBLE_VEC2,
	Double_Vec3       = gl.DOUBLE_VEC3,
	Double_Vec4       = gl.DOUBLE_VEC4,
	Double_Mat2       = gl.DOUBLE_MAT2,
	Double_Mat3       = gl.DOUBLE_MAT3,
	Double_Mat4       = gl.DOUBLE_MAT4,
	Double_Mat2x3     = gl.DOUBLE_MAT2x3,
	Double_Mat2x4     = gl.DOUBLE_MAT2x4,
	Double_Mat3x2     = gl.DOUBLE_MAT3x2,
	Double_Mat3x4     = gl.DOUBLE_MAT3x4,
	Double_Mat4x2     = gl.DOUBLE_MAT4x2,
	Double_Mat4x3     = gl.DOUBLE_MAT4x3,
}

@(private)
get_uniform_blocks_from_program :: proc(program: u32) -> []Uniform_Buffer_Block {
	blocks := make([dynamic]Uniform_Buffer_Block, program_data_allocator)

	n: i32
	gl.GetProgramInterfaceiv(program, gl.UNIFORM_BLOCK, gl.ACTIVE_RESOURCES, &n)

	max_len: i32
	gl.GetProgramInterfaceiv(program, gl.UNIFORM_BLOCK, gl.MAX_NAME_LENGTH, &max_len)

	buf := make([]byte, max_len, context.temp_allocator)

	properties := [?]u32{gl.BUFFER_BINDING, gl.BUFFER_DATA_SIZE, gl.NUM_ACTIVE_VARIABLES}
	values: [len(properties)]i32

	for i in 0 ..< n {
		length: i32
		gl.GetProgramResourceName(
			program,
			gl.UNIFORM_BLOCK,
			u32(i),
			max_len,
			&length,
			raw_data(buf),
		)
		gl.GetProgramResourceiv(
			program,
			gl.UNIFORM_BLOCK,
			u32(i),
			len(properties),
			&properties[0],
			size_of(values),
			nil,
			&values[0],
		)

		assert(values[2] == 1, "Currently only uniform buffers with one variable are supported")

		append(
			&blocks,
			Uniform_Buffer_Block {
				name      = strings.clone_from_ptr(raw_data(buf), int(length), program_data_allocator),
				binding   = int(values[0]),
				size      = int(values[1]),
			},
		)
	}

	return blocks[:]
}

@(private)
get_attributes_from_program :: proc(p: u32) -> []Attribute {
	n: i32
	gl.GetProgramInterfaceiv(p, gl.PROGRAM_INPUT, gl.ACTIVE_RESOURCES, &n)

	attributes := make([dynamic]Attribute, n, program_data_allocator)

	max_len: i32
	gl.GetProgramInterfaceiv(p, gl.PROGRAM_INPUT, gl.MAX_NAME_LENGTH, &max_len)

	buf := make([]byte, max_len, context.temp_allocator)

	properties := [?]u32{gl.TYPE, gl.ARRAY_SIZE, gl.LOCATION}
	values: [len(properties)]i32

	for i in 0 ..< n {
		length: i32
		gl.GetProgramResourceName(p, gl.PROGRAM_INPUT, u32(i), max_len, &length, raw_data(buf))
		gl.GetProgramResourceiv(
			p,
			gl.PROGRAM_INPUT,
			u32(i),
			len(properties),
			&properties[0],
			size_of(values),
			nil,
			&values[0],
		)

		for int(values[2]) >= len(attributes) {
			append(&attributes, Attribute{})
		}
		attributes[values[2]] = {
			name     = strings.clone_from_ptr(raw_data(buf), int(length), program_data_allocator),
			size     = values[1],
			type     = Attribute_Type(values[0]),
			location = values[2],
		}
	}

	return attributes[:]
}

destroy_program :: #force_inline proc(program: Program) {
	{
		context.allocator = program_data_allocator
		program := get_program(program)
		gl.destroy_uniforms(program.uniforms)
		for a in program.attributes {
			delete(a.name)
		}
		delete(program.attributes)
		for b in program.uniform_blocks {
			delete(b.name)
		}
		delete(program.uniform_blocks)
		gl.DeleteProgram(program.handle)
	}
	ga_remove(programs, program)
}

@(private)
current_program := max(Program)

@(private)
set_program_active :: proc(program: Program) {
	if program != current_program {
		gl.UseProgram(get_program_handle(program))
		current_program = program
	}
}

