package example

import "base:runtime"

import "core:log"
import la "core:math/linalg"
import glm "core:math/linalg/glsl"
import "core:math/rand"
import "core:strings"
import "core:time"

import "shared:back"

import gl "vendor:OpenGL"
import "vendor:glfw"

import glodin "../.."

main :: proc() {
	when ODIN_DEBUG {
		back.register_segfault_handler()
		context.assertion_failure_proc = back.assertion_failure_proc
	}

	context.logger = log.create_console_logger(ODIN_DEBUG ? .Debug : .Error)
	callback_context = context

	window_init()
	defer window_uninit()

	meshes := glodin.create_mesh("sphere.glb") or_else panic("Failed to load mesh")
	defer for mesh in meshes do glodin.destroy(mesh)

	Instance_Info :: struct {
		color:    glm.vec3,
		position: glm.vec3,
		scale:    f32,
	}

	N :: 10000
	velocities := make([]glm.vec3, N)
	per_instance_data := make([]Instance_Info, N)
	for &v in velocities {
		v = {rand.float32() - 0.5, rand.float32() - 0.5, rand.float32() - 0.5}
	}
	for &p in per_instance_data {
		p.color = {rand.float32(), rand.float32(), rand.float32()}
		p.position = 20 * {rand.float32() - 0.5, rand.float32() - 0.5, rand.float32() - 0.5}
		p.scale = 0.1 * rand.float32_range(0.5, 2)
	}

	sphere_instances := glodin.create_instanced_mesh(meshes[0], per_instance_data)
	defer glodin.destroy_instanced_mesh(sphere_instances)

	program :=
		glodin.create_program_file("vertex.glsl", "fragment.glsl") or_else panic(
			"Failed to compile program",
		)
	defer glodin.destroy(program)

	start_time := time.now()

	total_time: f64
	last_time: f64
	for !window.should_close {
		_time := f64(time.duration_seconds(time.since(start_time)))
		delta_time := _time - total_time
		total_time = _time

		for &p, i in per_instance_data {
			p.position += velocities[i] * f32(delta_time)
		}
		glodin.set_instanced_mesh_data(sphere_instances, per_instance_data)

		update_camera()
		glodin.set_uniforms(
			program,
			{
				{"u_view", camera.view},
				{"u_perspective", camera.perspective},
				{"u_model", glm.mat4(1)},
			},
		)

		glodin.clear_color(0, {0.2, 0.2, 0.4, 1})
		glodin.clear_depth(0, 1)
		glodin.set_draw_flags({.Depth_Test, .Cull_Face})
		glodin.draw(0, program, sphere_instances)

		window_poll()
		free_all(context.temp_allocator)
	}
}

window: Window

Window :: struct {
	handle:        glfw.WindowHandle,
	width, height: int,
	aspect_ratio:  f32,
	should_close:  bool,
}

set_window_title :: proc(title: string) {
	glfw.SetWindowTitle(window.handle, strings.clone_to_cstring(title, context.temp_allocator))
}

window_poll :: proc() {
	glfw.SwapBuffers(window.handle)

	glfw.PollEvents()
	window.should_close = bool(glfw.WindowShouldClose(window.handle))
}

window_init :: proc() {
	if !glfw.Init() {
		panic("GLFW has failed to load.")
	}

	window.handle = glfw.CreateWindow(900, 600, "GLODIN", nil, nil)

	if window.handle == nil {
		panic("GLFW has failed to load the window.")
	}

	w, h := glfw.GetWindowSize(window.handle)
	window.width = int(w)
	window.height = int(h)
	window.aspect_ratio = f32(w) / f32(h)

	glfw.SetWindowSizeCallback(window.handle, size_callback)

	glfw.MakeContextCurrent(window.handle)

	glodin.init(glfw.gl_set_proc_address)

	glfw.SwapInterval(0)

	recompute_perspective()
}

window_uninit :: proc() {
	glodin.uninit()
	glfw.DestroyWindow(window.handle)
	glfw.Terminate()
}

callback_context: runtime.Context

@(private = "file")
size_callback :: proc "c" (window_handle: glfw.WindowHandle, width, height: i32) {
	window.width = max(int(width), 1)
	window.height = max(int(height), 1)
	window.aspect_ratio = f32(width) / f32(height)

	context = callback_context
	recompute_perspective()
	glodin.window_size_callback(int(width), int(height))
}

// odinfmt: disable
UP       :: glm.vec3{+0, +1, +0}
DOWN     :: glm.vec3{+0, -1, +0}
FORWARD  :: glm.vec3{+0, +0, -1}
BACKWARD :: glm.vec3{+0, +0, +1}
LEFT     :: glm.vec3{+1, +0, +0}
RIGHT    :: glm.vec3{-1, +0, +0}
// odinfmt: enable

camera: Camera = {
	position = BACKWARD * 20,
	near     = 0.01,
	far      = 1000,
	fov      = 1,
}

Camera :: struct {
	perspective:        glm.mat4,
	view:               glm.mat4,
	position:           glm.vec3,
	forward, up, right: glm.vec3,
	near, far, fov:     f32,
	yaw, pitch:         f32,
}

update_camera :: proc() {
	camera.forward = (get_camera_rotation_matrix() * glm.vec4{0, 0, -1, 0}).xyz
	camera.right = glm.cross(camera.forward, UP)
	camera.up = glm.cross(camera.right, camera.forward)
	recompute_view()
}

get_camera_rotation_matrix :: proc() -> glm.mat4 {
	return(
		cast(glm.mat4)la.matrix4_from_euler_angles_f32(
			glm.clamp(camera.pitch, -glm.PI * 0.5, glm.PI * 0.5),
			camera.yaw,
			0,
			.ZYX,
		) \
	)
}

recompute_perspective :: proc "contextless" () {
	camera.perspective = glm.mat4Perspective(
		camera.fov,
		window.aspect_ratio,
		camera.near,
		camera.far,
	)
}

recompute_view :: proc() {
	camera.view = glm.mat4LookAt(
		camera.position,
		camera.position + camera.forward,
		glm.vec3{0, 1, 0},
	)
}

