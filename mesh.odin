package glodin

import "base:intrinsics"

import "core:fmt"
import glm "core:math/linalg/glsl"
import "core:os"
import "core:reflect"
import "core:strings"

import gl "vendor:OpenGL"
import "vendor:cgltf"

Instanced_Mesh :: distinct Index

@(private)
instanced_meshes: ^Generational_Array(_Instanced_Mesh)

@(private)
get_instanced_mesh :: proc(instanced_mesh: Instanced_Mesh) -> ^_Instanced_Mesh {
	return ga_get(instanced_meshes, instanced_mesh)
}

@(private)
get_instanced_mesh_base :: proc(instanced_mesh: Instanced_Mesh) -> Mesh {
	return ga_get(instanced_meshes, instanced_mesh).mesh
}

get_instanced_mesh_info :: proc(instanced_mesh: Instanced_Mesh) -> _Instanced_Mesh {
	return ga_get(instanced_meshes, instanced_mesh)^
}

@(private)
_Instanced_Mesh :: struct {
	mesh:           Mesh,
	instance_type:  typeid,
	n_attributes:   u32,
	instance_vbo:   u32,
	instance_count: i32,
}

set_instanced_mesh_data :: proc(
	mesh: Instanced_Mesh,
	data: $T/[]$P,
	location := #caller_location,
) {
	mesh := get_instanced_mesh(mesh)
	assert(len(data) == int(mesh.instance_count), location = location)
	assertf(
		P == mesh.instance_type,
		"set_instanced_mesh_data type mismatch: %v != %v",
		mesh.instance_type,
		typeid_of(P),
		location = location,
	)

	gl.NamedBufferSubData(mesh.instance_vbo, 0, len(data) * size_of(P), raw_data(data))
}

create_instanced_mesh :: proc {
	create_instanced_mesh_indices,
	create_instanced_mesh_no_indices,
	create_instanced_mesh_from_base,
}

create_instanced_mesh_indices :: proc(
	vertices: $T/[]$V,
	indices: $T2/[]$I,
	per_instance: $T3/[]$P,
	location := #caller_location,
) -> Instanced_Mesh {
	return _create_instanced_mesh(vertices, indices, per_instance, location)
}

create_instanced_mesh_no_indices :: proc(
	vertices: $T/[]$V,
	per_instance: $T3/[]$P,
	location := #caller_location,
) -> Instanced_Mesh {
	return _create_instanced_mesh(vertices, []u32{}, per_instance, location)
}

@(private)
_create_instanced_mesh :: proc(
	vertices: $T/[]$V,
	indices: $T2/[]$I,
	per_instance: $T3/[]$P,
	location: Source_Code_Location,
) -> Instanced_Mesh {
	return create_instanced_mesh_from_base(
		create_mesh(vertices, indices, location),
		per_instance,
		location,
	)
}

create_instanced_mesh_from_base :: proc(
	mesh: Mesh,
	per_instance: $T/[]$P,
	location := #caller_location,
) -> Instanced_Mesh {
	m: _Instanced_Mesh
	m.mesh = mesh

	mesh := get_mesh(mesh)^

	gl.CreateBuffers(1, &m.instance_vbo)
	gl.NamedBufferStorage(
		m.instance_vbo,
		len(per_instance) * size_of(P),
		raw_data(per_instance),
		gl.DYNAMIC_STORAGE_BIT,
	)

	gl.VertexArrayVertexBuffer(mesh.vao, 1, m.instance_vbo, 0, size_of(P))
	gl.VertexArrayBindingDivisor(mesh.vao, 1, 1)

	n_attributes := mesh.n_attributes
	offset: u32
	set_vertex_attribute_from_type(mesh.vao, type_info_of(P), &n_attributes, &offset, location, 1)
	m.n_attributes = n_attributes - mesh.n_attributes

	m.instance_count = i32(len(per_instance))
	m.instance_type = P

	return Instanced_Mesh(ga_append(instanced_meshes, m))
}

@(private)
set_vertex_attribute_from_type :: proc(
	vao: u32,
	ti: ^reflect.Type_Info,
	attr_index: ^u32,
	offset: ^u32,
	location: Source_Code_Location,
	binding_index: u32 = 0,
	array: i32 = -1,
) {
	n := array
	if n < 0 {
		n = 1
	}

	ti := reflect.type_info_core(ti)
	#partial switch v in ti.variant {
	case reflect.Type_Info_Float:
		gl.EnableVertexArrayAttrib(vao, attr_index^)
		gl.VertexArrayAttribBinding(vao, attr_index^, binding_index)
		type: u32
		switch ti.size {
		case 2:
			type = gl.HALF_FLOAT
		case 4:
			type = gl.FLOAT
		case 8:
			type = gl.DOUBLE
		case:
			panic("")
		}
		gl.VertexArrayAttribFormat(vao, attr_index^, n, type, false, offset^)
		offset^ += u32(ti.size) * u32(n)
		attr_index^ += 1
	case reflect.Type_Info_Complex:
		for _ in 0 ..< n {
			gl.EnableVertexArrayAttrib(vao, attr_index^)
			gl.VertexArrayAttribBinding(vao, attr_index^, binding_index)
			type: u32
			switch ti.size / 2 {
			case 2:
				type = gl.HALF_FLOAT
			case 4:
				type = gl.FLOAT
			case 8:
				type = gl.DOUBLE
			case:
				panic("")
			}
			gl.VertexArrayAttribFormat(vao, attr_index^, 2, type, false, offset^)
			offset^ += u32(ti.size)
			attr_index^ += 1
		}
	case reflect.Type_Info_Quaternion:
		for _ in 0 ..< n {
			gl.EnableVertexArrayAttrib(vao, attr_index^)
			gl.VertexArrayAttribBinding(vao, attr_index^, binding_index)
			type: u32
			switch ti.size / 4 {
			case 2:
				type = gl.HALF_FLOAT
			case 4:
				type = gl.FLOAT
			case 8:
				type = gl.DOUBLE
			case:
				panic("")
			}
			gl.VertexArrayAttribFormat(vao, attr_index^, 4, type, false, offset^)
			offset^ += u32(ti.size)
			attr_index^ += 1
		}
	case reflect.Type_Info_Matrix:
		unimplemented()

	case reflect.Type_Info_Integer:
		gl.EnableVertexArrayAttrib(vao, attr_index^)
		gl.VertexArrayAttribBinding(vao, attr_index^, binding_index)
		type: u32
		switch ti.size {
		case 1:
			type = v.signed ? gl.BYTE : gl.UNSIGNED_BYTE
		case 2:
			type = v.signed ? gl.SHORT : gl.UNSIGNED_SHORT
		case 4:
			type = v.signed ? gl.INT : gl.UNSIGNED_INT
		case:
			panic("")
		}
		gl.VertexArrayAttribIFormat(vao, attr_index^, n, type, offset^)
		offset^ += u32(ti.size) * u32(n)
		attr_index^ += 1
	case reflect.Type_Info_Boolean:
		gl.EnableVertexArrayAttrib(vao, attr_index^)
		gl.VertexArrayAttribBinding(vao, attr_index^, binding_index)
		type: u32
		switch ti.size {
		case 1:
			type = gl.UNSIGNED_BYTE
		case 2:
			type = gl.UNSIGNED_SHORT
		case 4:
			type = gl.UNSIGNED_INT
		case:
			panic("")
		}
		gl.VertexArrayAttribIFormat(vao, attr_index^, n, type, 0)
		attr_index^ += 1
	case reflect.Type_Info_Bit_Set:
		set_vertex_attribute_from_type(
			vao,
			v.underlying,
			attr_index,
			offset,
			location,
			binding_index,
		)

	case reflect.Type_Info_Simd_Vector:
		set_vertex_attribute_from_type(
			vao,
			v.elem,
			attr_index,
			offset,
			location,
			binding_index,
			n * i32(v.count),
		)
	case reflect.Type_Info_Array:
		set_vertex_attribute_from_type(
			vao,
			v.elem,
			attr_index,
			offset,
			location,
			binding_index,
			n * i32(v.count),
		)
	case reflect.Type_Info_Enumerated_Array:
		a: reflect.Type_Info = {
			size = ti.align,
			align = ti.align,
			flags = ti.flags,
			id = ti.id,
			variant = reflect.Type_Info_Array {
				elem = reflect.type_info_core(v.elem),
				elem_size = v.elem_size,
				count = v.count,
			},
		}
		set_vertex_attribute_from_type(vao, &a, attr_index, offset, location, binding_index, array)
	case reflect.Type_Info_Struct:
		for _ in 0 ..< n {
			for type, i in v.types[:v.field_count] {
				_offset := u32(v.offsets[i]) + offset^
				set_vertex_attribute_from_type(
					vao,
					type,
					attr_index,
					&_offset,
					location,
					binding_index,
				)
			}
		}
		offset^ += u32(ti.size) * u32(n)

	case:
		panicf("%v is not a valid type for a vertex attribute", ti.id, location = location)
	}
}

Mesh :: distinct Index

@(private)
meshes: ^Generational_Array(_Mesh)

@(private)
get_mesh :: proc(mesh: Mesh) -> ^_Mesh {
	return ga_get(meshes, mesh)
}

get_mesh_info :: proc(mesh: Mesh) -> _Mesh {
	return ga_get(meshes, mesh)^
}

@(private)
_Mesh :: struct {
	vertex_type:  typeid,
	vao:          u32,
	vbo:          u32,
	ibo:          u32,
	count:        i32,
	index_type:   u32,
	n_attributes: u32,
}

create_mesh_gltf :: proc(
	path: string,
	allocator := context.allocator,
) -> (
	meshes: [dynamic]Mesh,
	ok: bool,
) {
	meshes.allocator = allocator
	file_data := os.read_entire_file(path) or_return

	data, result := cgltf.parse(cgltf.options{}, &file_data[0], len(file_data))
	if result != .success {
		error("Failed to load gltf model from path", path, ":", result)
		return
	}
	defer cgltf.free(data)

	load_buffers_result := cgltf.load_buffers(
		{},
		data,
		strings.clone_to_cstring(path, context.temp_allocator),
	)
	if load_buffers_result != .success {
		error("Failed to load buffers for gltf model from path", path, ":", result)
		return
	}

	Mesh_Vertex :: struct {
		position:   glm.vec3,
		normal:     glm.vec3,
		tex_coords: glm.vec2,
	}

	vertex_buf := [dynamic]Mesh_Vertex{}
	index_buf := [dynamic]u32{}
	defer delete(vertex_buf)
	defer delete(index_buf)

	for node in data.nodes {
		mesh := node.mesh
		if mesh == nil {
			continue
		}

		for primitive in mesh.primitives {
			positions := primitive.attributes[0]
			normals := primitive.attributes[1]
			texcoords := primitive.attributes[2]
			assert(
				positions.data.count == normals.data.count &&
				positions.data.count == texcoords.data.count,
			)
			for i in 0 ..< positions.data.count {
				position: [3]f32
				normal: [3]f32
				tex_coord: [3]f32

				ok: b32
				ok &&= cgltf.accessor_read_float(positions.data, i, &position[0],  3) != false
				ok &&= cgltf.accessor_read_float(normals.data,   i, &normal[0],    3) != false
				ok &&= cgltf.accessor_read_float(texcoords.data, i, &tex_coord[0], 2) != false
				assert(ok != false)

				append(
					&vertex_buf,
					Mesh_Vertex {
						position = glm.vec3{position[0], position[1], position[2]},
						normal = glm.vec3{normal[0], normal[1], normal[2]},
						tex_coords = glm.vec2{tex_coord[0], tex_coord[1]},
					},
				)
			}

			for i in 0 ..= primitive.indices.count {
				append(&index_buf, u32(cgltf.accessor_read_index(primitive.indices, i)))
			}
		}

		append(&meshes, create_mesh(vertex_buf[:], index_buf[:]))
		clear(&vertex_buf)
		clear(&index_buf)
	}

	ok = true
	return
}

create_mesh :: proc {
	create_mesh_gltf,
	create_mesh_indices,
	create_mesh_no_indices,
}

create_mesh_indices :: proc(
	vertices: $T/[]$V,
	indices: $U/[]$I,
	location := #caller_location,
) -> Mesh {
	return Mesh(ga_append(meshes, _create_mesh(vertices, indices, location)))
}

create_mesh_no_indices :: proc(vertices: $T/[]$V, location := #caller_location) -> Mesh {
	return Mesh(ga_append(&meshes, _create_mesh(vertices, []u32{}, location)))
}

@(private)
_create_mesh :: proc(
	vertices: $T/[]$V,
	indices: $U/[]$I,
	location: Source_Code_Location,
) -> (
	m: _Mesh,
) {
	gl.CreateBuffers(1, &m.vbo)
	gl.NamedBufferStorage(
		m.vbo,
		size_of(V) * len(vertices),
		raw_data(vertices),
		gl.DYNAMIC_STORAGE_BIT,
	)
	m.vertex_type = V

	gl.CreateVertexArrays(1, &m.vao)

	gl.VertexArrayVertexBuffer(m.vao, 0, m.vbo, 0, size_of(V))

	m.count = i32(len(vertices))

	if len(indices) != 0 {
		gl.CreateBuffers(1, &m.ibo)
		gl.NamedBufferStorage(
			m.ibo,
			size_of(I) * len(indices),
			raw_data(indices),
			gl.DYNAMIC_STORAGE_BIT,
		)
		size := size_of(I)
		if reflect.type_info_base(type_info_of(I)).variant.(reflect.Type_Info_Integer).signed {
			warnf(
				"Index type should be unsigned, got signed type: '%v'",
				typeid_of(I),
				location = location,
			)
		}
		switch size {
		case 1:
			m.index_type = gl.UNSIGNED_BYTE
		case 2:
			m.index_type = gl.UNSIGNED_SHORT
		case 4:
			m.index_type = gl.UNSIGNED_INT
		}

		gl.VertexArrayElementBuffer(m.vao, m.ibo)
		m.count = i32(len(indices))
	}

	i: u32
	for field in reflect.struct_fields_zipped(V) {
		gl.EnableVertexArrayAttrib(m.vao, i)

		gl.VertexArrayAttribFormat(
			m.vao,
			i,
			gl_size_and_type(field.type),
			false,
			u32(field.offset),
		)

		gl.VertexArrayAttribBinding(m.vao, i, 0)

		i += 1
	}
	m.n_attributes = i

	return m
}

update_mesh_vertices :: proc(
	mesh: Mesh,
	offset: int,
	vertices: $T/[]$V,
	location := #caller_location,
) {
	mesh := get_mesh(mesh)
	assert(mesh.vertex_type == V, loc = location)
	gl.BufferSubData(mesh.vbo, i32(offset), i32(len(vertices)) * size_of(V), raw_data(vertices))
}

@(private)
gl_size_and_type :: proc(type: ^reflect.Type_Info) -> (size: i32, gl_type: u32) {
	#partial switch v in type.variant {
	case reflect.Type_Info_Named:
		return gl_size_and_type(v.base)
	case reflect.Type_Info_Integer:
		switch type.size {
		case 1:
			gl_type = v.signed ? gl.BYTE : gl.UNSIGNED_BYTE
		case 2:
			gl_type = v.signed ? gl.SHORT : gl.UNSIGNED_SHORT
		case 4:
			gl_type = v.signed ? gl.INT : gl.UNSIGNED_INT
		case:
			panicf("Invalid vertex attribute integer size: '%v'", type.size)
		}
		size = 1
	case reflect.Type_Info_Float:
		switch type.size {
		case 2:
			gl_type = gl.HALF_FLOAT
		case 4:
			gl_type = gl.FLOAT
		case 8:
			gl_type = gl.DOUBLE
		case:
			panicf("Invalid vertex attribute float size: '%v'", type.size)
		}
		size = 1
	case reflect.Type_Info_Array:
		size, gl_type = gl_size_and_type(v.elem)
		size *= i32(v.count)
	case reflect.Type_Info_Boolean:
		switch type.size {
		case 1:
			gl_type = gl.UNSIGNED_BYTE
		case 2:
			gl_type = gl.UNSIGNED_SHORT
		case 4:
			gl_type = gl.UNSIGNED_INT
		case:
			fmt.panicf("Invalid vertex attribute boolean size: '%v'", type.size)
		}
		size = 1
	case reflect.Type_Info_Matrix:
		size, gl_type = gl_size_and_type(v.elem)
		size *= i32(v.row_count * v.column_count)
	case reflect.Type_Info_Complex:
		switch type.size {
		case 4:
			gl_type = gl.HALF_FLOAT
		case 8:
			gl_type = gl.FLOAT
		case 16:
			gl_type = gl.DOUBLE
		case:
			fmt.panicf("Invalid vertex attribute complex size: '%v'", type.size)
		}
		size = 2
	case:
		fmt.panicf("Invalid vertex attribute type: '%v'", type.id)
	}
	return
}

destroy_mesh :: proc(mesh: Mesh) {
	im := get_mesh(mesh)
	gl.DeleteVertexArrays(1, &im.vao)
	gl.DeleteBuffers(1, &im.vbo)
	gl.DeleteBuffers(1, &im.ibo)

	ga_remove(meshes, mesh)
}

destroy_instanced_mesh :: proc(instanced_mesh: Instanced_Mesh, destroy_base: bool = false) {
	im := get_instanced_mesh(instanced_mesh)
	gl.DeleteBuffers(1, &im.instance_vbo)
	if destroy_base {
		destroy(im.mesh)
	}

	ga_remove(instanced_meshes, instanced_mesh)
}

