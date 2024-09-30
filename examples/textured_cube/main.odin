package shadows

import "base:runtime"

@(require)
import "core:image/png"

import "core:log"
import la "core:math/linalg"
import glm "core:math/linalg/glsl"
import "core:time"

import "vendor:glfw"

import glodin "../.."

main :: proc() {
	window_init()
	defer window_uninit()

	cube := (glodin.create_mesh("cube.glb") or_else panic("Failed to load cube mesh"))[0]
	defer glodin.destroy(cube)

	program := glodin.create_program_file("vertex.glsl", "fragment.glsl") or_else
		panic("Failed to load program")
	defer glodin.destroy(program)

	texture := glodin.create_texture("texture.png") or_else panic("Failed to load texture")
	defer glodin.destroy(texture)

	glodin.set_texture_sampling_state(texture, .Nearest, .Nearest)

	glodin.set_draw_flags({.Depth_Test, .Cull_Face})

	start_time := time.now()

	for !window.should_close {
		t := f32(time.duration_seconds(time.since(start_time)))

		transform := glm.mat4Rotate(UP + RIGHT, t)

		glodin.clear_color(0, 0.1)
		glodin.clear_depth(0, 1)

		update_camera()
		glodin.set_uniforms(program,
			{
				{"u_view",        camera.view},
				{"u_perspective", camera.perspective},
				{"u_model",       transform},
				{"u_texture",     texture},
			},
		)
		glodin.draw(0, program, cube)

		window_poll()
	}
}

window: Window

Window :: struct {
	handle:        glfw.WindowHandle,
	width, height: int,
	aspect_ratio:  f32,
	should_close:  bool,
}

window_poll :: proc() {
	glfw.SwapBuffers(window.handle)

	glfw.PollEvents()
	window.should_close = bool(glfw.WindowShouldClose(window.handle))
}

window_init :: proc() {
	if !glfw.Init() {
		log.panic("GLFW has failed to load.")
	}

	window.handle = glfw.CreateWindow(900, 600, "GLODIN", nil, nil)

	if window.handle == nil {
		log.panic("GLFW has failed to load the window.")
	}

	w, h := glfw.GetWindowSize(window.handle)
	window.width = int(w)
	window.height = int(h)
	window.aspect_ratio = f32(w) / f32(h)

	glfw.SetWindowSizeCallback(window.handle, size_callback)

	glodin.init_glfw(window.handle)

	glfw.SwapInterval(0)

	recompute_perspective()
}

window_uninit :: proc() {
	glodin.uninit()
	glfw.DestroyWindow(window.handle)
	glfw.Terminate()
}

size_callback :: proc "c" (window_handle: glfw.WindowHandle, width, height: i32) {
	window.width        = max(int(width),  1)
	window.height       = max(int(height), 1)
	window.aspect_ratio = f32(width) / f32(height)

	recompute_perspective()
}

UP       :: glm.vec3{+0, +1, +0}
DOWN     :: glm.vec3{+0, -1, +0}
FORWARD  :: glm.vec3{+0, +0, -1}
BACKWARD :: glm.vec3{+0, +0, +1}
LEFT     :: glm.vec3{+1, +0, +0}
RIGHT    :: glm.vec3{-1, +0, +0}

camera: Camera = {
	position = BACKWARD * 5,
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
	camera.pitch   = glm.clamp(camera.pitch, -glm.PI * 0.5, glm.PI * 0.5)
	camera.forward = (get_camera_rotation_matrix() * glm.vec4{0, 0, -1, 0}).xyz
	camera.right   = glm.cross(camera.forward, UP)
	camera.up      = glm.cross(camera.right, camera.forward)

	recompute_view()
}

get_camera_rotation_matrix :: proc() -> glm.mat4 {
	return(
		cast(glm.mat4)la.matrix4_from_euler_angles_f32(
			camera.pitch,
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

