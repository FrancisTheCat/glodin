// this is largely following this really nice gist by Ginger Bill https://gist.github.com/gingerBill/c7a91318bd7b3be96d63d428b24d19ea
package glodin_microui

import "base:runtime"

import "core:fmt"
import la "core:math/linalg"
import glm "core:math/linalg/glsl"
import "core:os"
import "core:unicode/utf8"

import "vendor:glfw"
import mu "vendor:microui"

import glodin "../.."

window_x, window_y: i32

input_string_len: int
input_string: [512]byte

input_scroll: [2]f64

current_clip_rect: [4]i32 = {0, 0, max(i32), max(i32)}

main :: proc() {
	ok := glfw.Init();assert(bool(ok))
	glfw.WindowHint(glfw.DECORATED, false)
	window := glfw.CreateWindow(900, 600, "", nil, nil)

	glfw.SetWindowSizeCallback(window, proc "c" (window: glfw.WindowHandle, x, y: i32) {
		window_x, window_y = x, y
	})

	glfw.SetCharCallback(window, proc "c" (window: glfw.WindowHandle, char: rune) {
		context = runtime.default_context()

		b, w := utf8.encode_rune(char)
		copy(input_string[input_string_len:], b[:w])
		input_string_len += w
	})

	glfw.SetScrollCallback(window, proc "c" (window: glfw.WindowHandle, x, y: f64) {
		input_scroll.x -= x * 50
		input_scroll.y -= y * 50
	})

	glodin.init_glfw(window)
	defer glodin.uninit()

	window_x, window_y = 900, 600
	glodin.clear_color(0, 0.1)
	glodin.window_size_callback(900, 600)

	program :=
		glodin.create_program_file("vertex.glsl", "fragment.glsl") or_else panic(
			"Failed to compile program",
		)
	defer glodin.destroy(program)

	data := os.read_entire_file("iosevka.ttf") or_else panic("Failed to open font file")
	defer delete(data)

	state.atlas_texture = glodin.create_texture_with_data(
		mu.DEFAULT_ATLAS_WIDTH,
		mu.DEFAULT_ATLAS_HEIGHT,
		mu.default_atlas_alpha[:],
		.R8,
		mag_filter = .Nearest,
	)
	defer glodin.destroy(state.atlas_texture)

	glodin.set_uniforms(program, {{"u_texture", state.atlas_texture}})
	glodin.set_draw_flags({.Blend})

	ctx := &state.mu_ctx
	mu.init(ctx)

	ctx.text_width = mu.default_atlas_text_width
	ctx.text_height = mu.default_atlas_text_height

	mouse_buttons: [mu.Mouse]bool

	Vertex :: struct {
		position: glm.vec2,
	}

	vertex_buffer: []Vertex = {
		{position = {0, 0}},
		{position = {0, 1}},
		{position = {1, 1}},
		{position = {0, 0}},
		{position = {1, 0}},
		{position = {1, 1}},
	}

	quad_mesh := glodin.create_mesh(vertex_buffer)
	defer glodin.destroy(quad_mesh)

	keys: [mu.Key]bool
	glfw_keys: [mu.Key]i32 = {
		.SHIFT     = glfw.KEY_LEFT_SHIFT,
		.CTRL      = glfw.KEY_LEFT_CONTROL,
		.ALT       = glfw.KEY_LEFT_ALT,
		.BACKSPACE = glfw.KEY_BACKSPACE,
		.DELETE    = glfw.KEY_DELETE,
		.RETURN    = glfw.KEY_ENTER,
		.LEFT      = glfw.KEY_LEFT,
		.RIGHT     = glfw.KEY_RIGHT,
		.HOME      = glfw.KEY_HOME,
		.END       = glfw.KEY_END,
		.A         = glfw.KEY_A,
		.X         = glfw.KEY_X,
		.C         = glfw.KEY_C,
		.V         = glfw.KEY_V,
	}

	for !glfw.WindowShouldClose(window) {
		{
			if input_scroll != 0 {
				mu.input_scroll(ctx, i32(input_scroll.x), i32(input_scroll.y))
				input_scroll = 0
			}

			x, y := glfw.GetCursorPos(window)
			mu.input_mouse_move(ctx, i32(x), i32(y))

			for &pressed, btn in mouse_buttons {
				if glfw.GetMouseButton(window, i32(btn)) == glfw.PRESS {
					if !pressed {
						mu.input_mouse_down(ctx, i32(x), i32(y), btn)
						pressed = true
					}
				} else {
					if pressed {
						mu.input_mouse_up(ctx, i32(x), i32(y), btn)
						pressed = false
					}
				}
			}

			for &pressed, key in keys {
				if glfw.GetKey(window, glfw_keys[key]) == glfw.PRESS {
					if !pressed {
						mu.input_key_down(ctx, key)
						pressed = true
					}
				} else {
					if pressed {
						mu.input_key_up(ctx, key)
						pressed = false
					}
				}
			}

			if input_string_len != 0 {
				mu.input_text(ctx, string(input_string[:input_string_len]))
				input_string_len = 0
			}
		}

		mu.begin(ctx)
		all_windows(ctx)
		mu.end(ctx)

		pcm: ^mu.Command
		for cmd in mu.next_command_iterator(ctx, &pcm) {
			switch cmd in cmd {
			case ^mu.Command_Jump:
				unreachable()
			case ^mu.Command_Clip:
				current_clip_rect = transmute([4]i32)cmd.rect
			case ^mu.Command_Rect:
				draw_rectangle(cmd.rect, cmd.color)
			case ^mu.Command_Text:
				draw_string(cmd.str, cmd.pos, cmd.color)
			case ^mu.Command_Icon:
				draw_icon(cmd.id, cmd.rect, cmd.color)
			}
		}

		glodin.clear_color(0, glm.vec4(la.array_cast(transmute([4]u8)state.bg, f32) / 255.0))

		glodin.set_uniforms(
			program,
			{
				{"u_inv_resolution", 1 / glm.vec2{f32(window_x), f32(window_y)}},
				{"u_resolution", glm.vec2{f32(window_x), f32(window_y)}},
			},
		)

		{
			mesh := glodin.create_instanced_mesh(quad_mesh, instance_buffer[:])
			defer glodin.destroy(mesh)

			glodin.draw(0, program, mesh)
		}

		clear(&instance_buffer)

		glfw.SwapBuffers(window)

		glfw.PollEvents()
	}

	glodin.write_texture_to_png(state.atlas_texture, "atlas.png")
}

instance_buffer: [dynamic]Instance

Instance :: struct {
	position:  [2]i32,
	size:      [2]i32,
	tex_rect:  [4]f32,
	clip_rect: [4]i32,
	color:     [4]f32,
}

Font :: struct {
	texture: glodin.Texture,
}

draw_icon :: proc(icon: mu.Icon, rect: mu.Rect, color: mu.Color) {
	color := la.array_cast(transmute([4]u8)color, f32) / 255.0

	quad := mu.default_atlas[int(icon)]

	screen_quad := rect
	screen_quad.w /= 2
	screen_quad.h /= 2
	screen_quad.x += screen_quad.w / 2
	screen_quad.y += screen_quad.h / 2

	tex_quad := struct {
		x, y, w, h: f32,
	} {
		x = f32(quad.x) / mu.DEFAULT_ATLAS_WIDTH,
		y = f32(quad.y) / mu.DEFAULT_ATLAS_HEIGHT,
		w = f32(quad.w) / mu.DEFAULT_ATLAS_WIDTH,
		h = f32(quad.h) / mu.DEFAULT_ATLAS_HEIGHT,
	}

	append(
		&instance_buffer,
		Instance {
			position = {screen_quad.x, screen_quad.y},
			size = {screen_quad.w, screen_quad.h},
			tex_rect = {tex_quad.x, tex_quad.y, tex_quad.w, tex_quad.h},
			clip_rect = current_clip_rect,
			color = color,
		},
	)
}

draw_string :: proc(str: string, position: mu.Vec2, color: mu.Color) {
	color := la.array_cast(transmute([4]u8)color, f32) / 255.0

	start_position := position
	position := position

	for ch in str {
		if ch == '\n' {
			position.x = start_position.x
			position.y += mu.default_atlas_text_height(nil)
			continue
		}
		if ch & 0xc0 == 0x80 {
			continue
		}
		r := min(int(ch), 127)
		quad := mu.default_atlas[mu.DEFAULT_ATLAS_FONT + r]

		screen_quad := quad

		screen_quad.x = position.x
		screen_quad.y = position.y

		tex_quad := struct {
			x, y, w, h: f32,
		} {
			x = f32(quad.x) / mu.DEFAULT_ATLAS_WIDTH,
			y = f32(quad.y) / mu.DEFAULT_ATLAS_HEIGHT,
			w = f32(quad.w) / mu.DEFAULT_ATLAS_WIDTH,
			h = f32(quad.h) / mu.DEFAULT_ATLAS_HEIGHT,
		}

		defer position.x += quad.w

		append(
			&instance_buffer,
			Instance {
				position = {screen_quad.x, screen_quad.y},
				size = {screen_quad.w, screen_quad.h},
				tex_rect = {tex_quad.x, tex_quad.y, tex_quad.w, tex_quad.h},
				clip_rect = current_clip_rect,
				color = color,
			},
		)
	}
}

draw_rectangle :: proc(rect: mu.Rect, color: mu.Color) {
	color := la.array_cast(transmute([4]u8)color, f32) / 255.0
	window_size := glm.vec2{f32(window_x), f32(window_y)}

	append(
		&instance_buffer,
		Instance {
			position = {rect.x, rect.y},
			size = {rect.w, rect.h},
			tex_rect = 0,
			clip_rect = current_clip_rect,
			color = color,
		},
	)
}

state := struct {
	mu_ctx:          mu.Context,
	log_buf:         [1 << 16]byte,
	log_buf_len:     int,
	log_buf_updated: bool,
	bg:              mu.Color,
	atlas_texture:   glodin.Texture,
} {
	bg = {90, 95, 100, 255},
}

u8_slider :: proc(ctx: ^mu.Context, val: ^u8, lo, hi: u8) -> (res: mu.Result_Set) {
	mu.push_id(ctx, uintptr(val))

	@(static)
	tmp: mu.Real
	tmp = mu.Real(val^)
	res = mu.slider(ctx, &tmp, mu.Real(lo), mu.Real(hi), 0, "%.0f", {.ALIGN_CENTER})
	val^ = u8(tmp)
	mu.pop_id(ctx)
	return
}

write_log :: proc(str: string) {
	state.log_buf_len += copy(state.log_buf[state.log_buf_len:], str)
	state.log_buf_len += copy(state.log_buf[state.log_buf_len:], "\n")
	state.log_buf_updated = true
}

read_log :: proc() -> string {
	return string(state.log_buf[:state.log_buf_len])
}
reset_log :: proc() {
	state.log_buf_updated = true
	state.log_buf_len = 0
}


all_windows :: proc(ctx: ^mu.Context) {
	@(static)
	opts := mu.Options{.NO_CLOSE}

	if mu.window(ctx, "Demo Window", {40, 40, 300, 450}, opts) {
		if .ACTIVE in mu.header(ctx, "Window Info") {
			win := mu.get_current_container(ctx)
			mu.layout_row(ctx, {54, -1}, 0)
			mu.label(ctx, "Position:")
			mu.label(ctx, fmt.tprintf("%d, %d", win.rect.x, win.rect.y))
			mu.label(ctx, "Size:")
			mu.label(ctx, fmt.tprintf("%d, %d", win.rect.w, win.rect.h))
		}

		if .ACTIVE in mu.header(ctx, "Window Options") {
			mu.layout_row(ctx, {120, 120, 120}, 0)
			for opt in mu.Opt {
				state := opt in opts
				if .CHANGE in mu.checkbox(ctx, fmt.tprintf("%v", opt), &state) {
					if state {
						opts += {opt}
					} else {
						opts -= {opt}
					}
				}
			}
		}

		if .ACTIVE in mu.header(ctx, "Test Buttons", {.EXPANDED}) {
			mu.layout_row(ctx, {86, -110, -1})
			mu.label(ctx, "Test buttons 1:")
			if .SUBMIT in mu.button(ctx, "Button 1") {write_log("Pressed button 1")}
			if .SUBMIT in mu.button(ctx, "Button 2") {write_log("Pressed button 2")}
			mu.label(ctx, "Test buttons 2:")
			if .SUBMIT in mu.button(ctx, "Button 3") {write_log("Pressed button 3")}
			if .SUBMIT in mu.button(ctx, "Button 4") {write_log("Pressed button 4")}
		}

		if .ACTIVE in mu.header(ctx, "Tree and Text", {.EXPANDED}) {
			mu.layout_row(ctx, {140, -1})
			mu.layout_begin_column(ctx)
			if .ACTIVE in mu.treenode(ctx, "Test 1") {
				if .ACTIVE in mu.treenode(ctx, "Test 1a") {
					mu.label(ctx, "Hello")
					mu.label(ctx, "world")
				}
				if .ACTIVE in mu.treenode(ctx, "Test 1b") {
					if .SUBMIT in mu.button(ctx, "Button 1") {write_log("Pressed button 1")}
					if .SUBMIT in mu.button(ctx, "Button 2") {write_log("Pressed button 2")}
				}
			}
			if .ACTIVE in mu.treenode(ctx, "Test 2") {
				mu.layout_row(ctx, {53, 53})
				if .SUBMIT in mu.button(ctx, "Button 3") {write_log("Pressed button 3")}
				if .SUBMIT in mu.button(ctx, "Button 4") {write_log("Pressed button 4")}
				if .SUBMIT in mu.button(ctx, "Button 5") {write_log("Pressed button 5")}
				if .SUBMIT in mu.button(ctx, "Button 6") {write_log("Pressed button 6")}
			}
			if .ACTIVE in mu.treenode(ctx, "Test 3") {
				@(static)
				checks := [3]bool{true, false, true}
				mu.checkbox(ctx, "Checkbox 1", &checks[0])
				mu.checkbox(ctx, "Checkbox 2", &checks[1])
				mu.checkbox(ctx, "Checkbox 3", &checks[2])

			}
			mu.layout_end_column(ctx)

			mu.layout_begin_column(ctx)
			mu.layout_row(ctx, {-1})
			mu.text(
				ctx,
				"Lorem ipsum dolor sit amet, consectetur adipiscing " +
				"elit. Maecenas lacinia, sem eu lacinia molestie, mi risus faucibus " +
				"ipsum, eu varius magna felis a nulla.",
			)
			mu.layout_end_column(ctx)
		}

		if .ACTIVE in mu.header(ctx, "Background Colour", {.EXPANDED}) {
			mu.layout_row(ctx, {-78, -1}, 68)
			mu.layout_begin_column(ctx)
			{
				mu.layout_row(ctx, {46, -1}, 0)
				mu.label(ctx, "Red:");u8_slider(ctx, &state.bg.r, 0, 255)
				mu.label(ctx, "Green:");u8_slider(ctx, &state.bg.g, 0, 255)
				mu.label(ctx, "Blue:");u8_slider(ctx, &state.bg.b, 0, 255)
			}
			mu.layout_end_column(ctx)

			r := mu.layout_next(ctx)
			mu.draw_rect(ctx, r, state.bg)
			mu.draw_box(ctx, mu.expand_rect(r, 1), ctx.style.colors[.BORDER])
			mu.draw_control_text(
				ctx,
				fmt.tprintf("#%02x%02x%02x", state.bg.r, state.bg.g, state.bg.b),
				r,
				.TEXT,
				{.ALIGN_CENTER},
			)
		}
	}

	if mu.window(ctx, "Log Window", {350, 40, 300, 200}, opts) {
		mu.layout_row(ctx, {-1}, -28)
		mu.begin_panel(ctx, "Log")
		mu.layout_row(ctx, {-1}, -1)
		mu.text(ctx, read_log())
		if state.log_buf_updated {
			panel := mu.get_current_container(ctx)
			panel.scroll.y = panel.content_size.y
			state.log_buf_updated = false
		}
		mu.end_panel(ctx)

		@(static)
		buf: [128]byte
		@(static)
		buf_len: int
		submitted := false
		mu.layout_row(ctx, {-70, -1})
		if .SUBMIT in mu.textbox(ctx, buf[:], &buf_len) {
			mu.set_focus(ctx, ctx.last_id)
			submitted = true
		}
		if .SUBMIT in mu.button(ctx, "Submit") {
			submitted = true
		}
		if submitted {
			write_log(string(buf[:buf_len]))
			buf_len = 0
		}
	}

	if mu.window(ctx, "Style Window", {350, 250, 300, 240}) {
		@(static)
		colors := [mu.Color_Type]string {
			.TEXT         = "text",
			.BORDER       = "border",
			.WINDOW_BG    = "window bg",
			.TITLE_BG     = "title bg",
			.TITLE_TEXT   = "title text",
			.PANEL_BG     = "panel bg",
			.BUTTON       = "button",
			.BUTTON_HOVER = "button hover",
			.BUTTON_FOCUS = "button focus",
			.BASE         = "base",
			.BASE_HOVER   = "base hover",
			.BASE_FOCUS   = "base focus",
			.SCROLL_BASE  = "scroll base",
			.SCROLL_THUMB = "scroll thumb",
			.SELECTION_BG = "selection bg",
		}

		sw := i32(f32(mu.get_current_container(ctx).body.w) * 0.14)
		mu.layout_row(ctx, {80, sw, sw, sw, sw, -1})
		for label, col in colors {
			mu.label(ctx, label)
			u8_slider(ctx, &ctx.style.colors[col].r, 0, 255)
			u8_slider(ctx, &ctx.style.colors[col].g, 0, 255)
			u8_slider(ctx, &ctx.style.colors[col].b, 0, 255)
			u8_slider(ctx, &ctx.style.colors[col].a, 0, 255)
			mu.draw_rect(ctx, mu.layout_next(ctx), ctx.style.colors[col])
		}
	}

}

