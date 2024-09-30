package glodin

import "base:intrinsics"

import "core:os"

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
	ok: bool,
) {
	data := os.read_entire_file(path, context.temp_allocator) or_return
	return create_compute_source(string(data), location)
}

create_compute_source :: proc(
	source: string,
	location := #caller_location,
) -> (
	compute: Compute,
	ok: bool,
) {
	c: _Compute
	c.handle, ok = gl.load_compute_source(source)
	if !ok {
		error("Failed to compile progam:", gl.get_last_error_messages(), location = location)
		return
	}
	c.uniforms = gl.get_uniforms_from_program(c.handle)
	return Compute(ga_append(computes, c)), true
}

dispatch_compute :: proc(
	compute: Compute,
	groups: [3]int,
	uniforms: ..Uniform,
	location := #caller_location,
) {
	c := get_compute(compute)

	gl.UseProgram(c.handle)
	current_program = max(Program)

	for uniform in uniforms {
		set_uniform(&c.base, uniform, location)
	}

	bind_program_textures(c, location, true)

	gl.DispatchCompute(u32(groups.x), u32(groups.y), u32(groups.z))
	gl.MemoryBarrier(gl.SHADER_IMAGE_ACCESS_BARRIER_BIT)
}

destroy_compute :: proc(compute: Compute) {
	c := get_compute(compute)
	context.allocator = program_data_allocator
	gl.destroy_uniforms(c.uniforms)
	gl.DeleteProgram(c.handle)

	ga_remove(computes, compute)
}

