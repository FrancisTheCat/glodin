package glodin

import "base:intrinsics"

import "core:slice"
import glm "core:math/linalg/glsl"

import gl "vendor:OpenGL"

Draw_Mode :: enum {
	Lines     = gl.LINES,
	Triangles = gl.TRIANGLES,
	Points    = gl.POINTS,
}

Draw_Flag :: enum {
	Depth_Test,
	Cull_Face,
	Blend,
}

@(private, rodata)
draw_flag_values := [Draw_Flag]u32 {
	.Depth_Test = gl.DEPTH_TEST,
	.Cull_Face  = gl.CULL_FACE,
	.Blend      = gl.BLEND,
}

Draw_Flags :: bit_set[Draw_Flag]

set_draw_flags :: proc(flags: Draw_Flags) {
	for flag in Draw_Flag {
		value := draw_flag_values[flag]
		if flag in flags {
			gl.Enable(value)
		} else {
			gl.Disable(value)
		}
	}
}

// Depth_Func :: enum {
// 	Never    = gl.NEVER,
// 	Less     = gl.LESS,
// 	Lequal   = gl.LEQUAL,
// 	Greater  = gl.GREATER,
// 	Gequal   = gl.GEQUAL,
// 	Equal    = gl.EQUAL,
// 	Notequal = gl.NOTEQUAL,
// 	Always   = gl.ALWAYS,
// }

// Stencil_Func :: enum {
// 	Never    = gl.NEVER,
// 	Less     = gl.LESS,
// 	Lequal   = gl.LEQUAL,
// 	Greater  = gl.GREATER,
// 	Gequal   = gl.GEQUAL,
// 	Equal    = gl.EQUAL,
// 	Notequal = gl.NOTEQUAL,
// 	Always   = gl.ALWAYS,
// }

// Face :: enum {
// 	Back  = gl.BACK,
// 	Front = gl.FRONT,
// }

// Polygon_Mode :: enum {
// 	Point = gl.POINT,
// 	Line  = gl.LINE,
// 	Fill  = gl.FILL,
// }

// Draw_State :: struct {
// 	flags:        Draw_Flags,
// 	line_width:   int,
// 	point_size:   int,
// 	depth_func:   Depth_Func,
// 	stencil_func: Stencil_Func,
// 	cull_face:    Face,
// 	polygon_mode: [Face]Polygon_Mode,
// }

@(private)
current_framebuffer := max(Framebuffer)

draw :: proc {
	draw_mesh,
	draw_instanced_mesh,
}

@(private)
prepare_drawing :: proc(
	framebuffer: Framebuffer,
	program: Program,
	vertex_type: typeid,
	per_instance_type: typeid,
	location: Source_Code_Location,
) {
	if framebuffer != current_framebuffer {
		current_framebuffer = framebuffer

		framebuffer := get_framebuffer(framebuffer)
		gl.BindFramebuffer(gl.FRAMEBUFFER, framebuffer.handle)
		gl.Viewport(0, 0, i32(framebuffer.width), i32(framebuffer.height))
	}
	set_program_active(program)

	program := get_program(program)

	bind_program_textures(program, location)

	check_program_vertex_type(program, vertex_type, per_instance_type, location)
}

@(private)
texture_units: []Texture

@(private)
bind_program_textures :: proc(
	program: ^Base_Program,
	location: Source_Code_Location,
) {
	n := len(program.textures)
	assert(n < int(max_texture_units), location = location)

	// is this necessary? No.
	size         := n * (size_of(Texture) + size_of(bool)) + int(max_texture_units) * size_of(bool)
	scratch_data := intrinsics.alloca(size, align_of(Texture))
	intrinsics.mem_zero(&scratch_data[0], size)

	textures := ([^]Texture)(scratch_data[:                        ])[:n                ]
	done     := ([^]bool   )(scratch_data[n * size_of(Texture):    ])[:n                ]
	used     := ([^]bool   )(scratch_data[n * size_of(Texture) + n:])[:max_texture_units]

	assert(len(textures) * size_of(Texture) + len(done) + len(used) == size)

	n_done := 0

	for texture, i in program.textures {
		for bound, unit in texture_units {
			if bound == texture.texture {
				gl.Uniform1i(texture.location, i32(unit))
				used[unit] = true
				done[i]    = true
				n_done += 1
				break
			}
		}
	}

	if intrinsics.expect(n == n_done, true) {
		return
	}

	bind_missing_textures: for texture, i in program.textures {
		if !done[i] {
			for &tex, unit in texture_units {
				if used[unit] do continue
				used[unit] = true

				tex = texture.texture
				gl.Uniform1i(texture.location, i32(unit))

				t := get_texture(texture.texture)
				gl.BindTextureUnit(u32(unit), t.handle)
				if !is_depth_format(t.format) && t.format != .Stencil8 {
					gl.BindImageTexture(u32(unit), t.handle, 0, false, 0, gl.READ_WRITE, u32(t.format))
				}
				continue bind_missing_textures
			}

			error("Ran out of texture units", location)
		}
	}
}

draw_mesh :: proc(
	framebuffer: Framebuffer,
	program: Program,
	mesh: Mesh,
	mode: Draw_Mode = .Triangles,
	location := #caller_location,
) {
	mesh := get_mesh(mesh)
	prepare_drawing(framebuffer, program, mesh.vertex_type, nil, location)

	gl.BindVertexArray(mesh.vao)
	if mesh.ibo == 0 {
		gl.DrawArrays(u32(mode), 0, mesh.count)
	} else {
		gl.DrawElements(u32(mode), mesh.count, mesh.index_type, nil)
	}
}

draw_instanced_mesh :: proc(
	framebuffer: Framebuffer,
	program: Program,
	instanced_mesh: Instanced_Mesh,
	mode: Draw_Mode = .Triangles,
	location := #caller_location,
) {
	instanced_mesh := get_instanced_mesh(instanced_mesh)
	mesh := get_mesh(instanced_mesh.mesh)
	prepare_drawing(framebuffer, program, mesh.vertex_type, instanced_mesh.instance_type, location)

	gl.BindVertexArray(mesh.vao)
	if mesh.ibo == 0 {
		gl.DrawArraysInstanced(u32(mode), 0, mesh.count, instanced_mesh.instance_count)
	} else {
		gl.DrawElementsInstanced(
			u32(mode),
			mesh.count,
			mesh.index_type,
			nil,
			instanced_mesh.instance_count,
		)
	}
}

clear_color :: proc(framebuffer: Framebuffer, color: glm.vec4) {
	color := color
	gl.ClearNamedFramebufferfv(get_framebuffer_handle(framebuffer), gl.COLOR, 0, &color[0])
}

clear_depth :: proc(framebuffer: Framebuffer, depth: f32) {
	depth := depth
	gl.ClearNamedFramebufferfv(get_framebuffer_handle(framebuffer), gl.DEPTH, 0, &depth)
}

