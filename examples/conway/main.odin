package conway

import glm "core:math/linalg/glsl"
import "core:math/rand"
import "core:simd"
import "core:time"

import "vendor:glfw"

import glodin "../.."

W :: 1920 / 4
H :: 1080 / 4

// you can probably increase this quite a bit without running into performance problems
TICK_RATE :: 1200000

main :: proc() {
	ok := glfw.Init()
	assert(bool(ok))
	window := glfw.CreateWindow(1920, 1080, "", glfw.GetPrimaryMonitor(), nil)

	glodin.init_glfw(window)
	defer glodin.uninit()

	compute :=
		glodin.create_compute_file("compute.glsl") or_else panic(
			"Failed to compile compute shader",
		)
	defer glodin.destroy(compute)

	compute_textures := [2]glodin.Texture {
		glodin.create_texture_empty(W, H, .R8UI, mag_filter = .Nearest, min_filter = .Linear),
		glodin.create_texture_empty(W, H, .R8UI, mag_filter = .Nearest, min_filter = .Linear),
	}
	defer for tex in compute_textures do glodin.destroy(tex)

	#assert(W * H % 8 == 0)
	data := make([]u8, W * H)
	for i in 0 ..< len(data) / 8 {
		i := i * 8

		r := transmute(#simd[8]u8)rand.uint64()
		value := simd.lanes_eq(
			simd.bit_and(
				r,
				// If you want a different ratio of dead/alive cells in the beginning, this is the value to change
				// the more bits the value has, the more cells will be dead
				(#simd[8]u8)(0xf),
			),
			(#simd[8]u8)(0),
		)
		((^#simd[8]u8)(&data[i]))^ = value
	}

	glodin.set_texture_data(compute_textures[0], data)

	Vertex_2D :: struct {
		position:   glm.vec2,
		tex_coords: glm.vec2,
	}

	vertices: []Vertex_2D = {
		{position = {-1, -1}, tex_coords = {0, 0}},
		{position = {+1, -1}, tex_coords = {1, 0}},
		{position = {-1, +1}, tex_coords = {0, 1}},
		{position = {+1, +1}, tex_coords = {1, 1}},
	}

	indices: []u32 = {0, 1, 2, 2, 1, 3}

	quad := glodin.create_mesh(vertices, indices)
	defer glodin.destroy(quad)

	program :=
		glodin.create_program_file("vertex.glsl", "fragment.glsl") or_else panic(
			"Failed to compile program",
		)
	defer glodin.destroy(program)

	last_tick := time.now()

	r_pressed: bool

	for !glfw.WindowShouldClose(window) {
		for time.duration_seconds(time.since(last_tick)) > 1.0 / TICK_RATE {
			last_tick = time.time_add(last_tick, time.Second / TICK_RATE)

			glodin.dispatch_compute(
				compute,
				{W, H, 1},
				{{"img_input", compute_textures.x}, {"img_output", compute_textures.y}},
			)
			compute_textures.xy = compute_textures.yx
		}

		if glfw.GetKey(window, glfw.KEY_R) == glfw.PRESS  {
			if !r_pressed {
				r_pressed = true

				data := make([]u8, W * H)
				for i in 0 ..< len(data) / 8 {
					i := i * 8

					r := transmute(#simd[8]u8)rand.uint64()
					value := simd.lanes_eq(
						simd.bit_and(
							r,
							// If you want a different ratio of dead/alive cells in the beginning, this is the value to change
							// the more bits the value has, the more cells will be dead
							(#simd[8]u8)(0xf),
						),
						(#simd[8]u8)(0),
					)
					((^#simd[8]u8)(&data[i]))^ = value
				}

				glodin.set_texture_data(compute_textures[0], data)
			}
		} else {
			r_pressed = false
		}

		glodin.set_uniforms(program, {{"u_game_state", compute_textures.x}})

		glodin.draw(0, program, quad)

		glfw.SwapBuffers(window)

		glfw.PollEvents()
	}
}

