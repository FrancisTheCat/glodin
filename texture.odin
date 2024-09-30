package glodin

import "base:intrinsics"

import "core:image"
import "core:math"
import "core:reflect"
import "core:slice"
import "core:strings"

import gl "vendor:OpenGL"
import stbi "vendor:stb/image"

@(private = "file")
Base_Texture_2D :: struct {
	handle:        u32,
	width, height: int,
	layers:        int,
	samples:       int,
	format:        Texture_Format,
}

Texture_Array :: distinct Index

@(private)
texture_arrays: ^Generational_Array(_Texture_Array)

@(private)
get_texture_array :: proc(texture_array: Texture_Array) -> ^_Texture_Array {
	return ga_get(texture_arrays, texture_array)
}

@(private)
get_texture_array_handle :: proc(texture_array: Texture_Array) -> (handle: u32, ok: bool) {
	ptr := ga_get(texture_arrays, texture_array)
	if ptr == nil {
		return
	}
	return ptr.handle, true
}

_get_texture_array_handle :: proc(texture_array: Texture_Array) -> (handle: u32, ok: bool) {
	return get_texture_array_handle(texture_array)
}

get_texture_array_info :: proc(texture_array: Texture_Array) -> (info: _Texture_Array, ok: bool) {
	ptr := get_texture_array(texture_array)
	if ptr == nil {
		return
	}
	return ptr^, true
}


@(private)
_Texture_Array :: struct {
	using elem: _Texture,
	count:      int,
}

create_texture_array :: proc(
	width, height: int,
	count: int,
	format: Texture_Format = .RGBA8,
	layers: int = 1,
	samples: int = 0,
	mag_filter: Texture_Mag_Filter = .Linear,
	min_filter: Texture_Min_Filter = .Nearest_Mipmap_Linear,
	wrap: [2]Texture_Wrap = {},
	border_color: [4]f32 = {},
	location := #caller_location,
) -> Texture_Array {
	t: _Texture_Array = {
		width        = width,
		height       = height,
		format       = format,
		min_filter   = min_filter,
		mag_filter   = mag_filter,
		count        = count,
		border_color = border_color,
	}

	if samples > 1 {
		samples := check_multisampling_parameters(
			format,
			samples,
			layers,
			mag_filter,
			min_filter,
			wrap,
			border_color,
			location,
		)
		t.samples = samples
		gl.CreateTextures(gl.TEXTURE_2D_MULTISAMPLE_ARRAY, 1, &t.handle)
		gl.TextureStorage3DMultisample(
			t.handle,
			i32(samples),
			u32(format),
			i32(width),
			i32(height),
			i32(count),
			false,
		)
	} else {
		t.samples = 0
		layers := check_texture_layer_count(layers, location, width, height)
		t.layers = layers

		gl.CreateTextures(gl.TEXTURE_2D_ARRAY, 1, &t.handle)
		gl.TextureStorage3D(
			t.handle,
			i32(layers),
			u32(format),
			i32(width),
			i32(height),
			i32(count),
		)

		for w, direction in wrap {
			gl.TextureParameteri(
				t.handle,
				GL_TEXTURE_WRAP_DIRECTION[direction],
				GL_TEXTURE_WRAP[w],
			)
		}
		gl.TextureParameteri(t.handle, gl.TEXTURE_MAG_FILTER, i32(mag_filter))
		gl.TextureParameteri(t.handle, gl.TEXTURE_MIN_FILTER, i32(min_filter))

		border_color := border_color
		gl.TextureParameterfv(t.handle, gl.TEXTURE_BORDER_COLOR, &border_color[0])
	}

	return Texture_Array(ga_append(texture_arrays, t))
}

destroy_texture_array :: proc(texture_array: Texture_Array) {
	ta := get_texture_array(texture_array)
	gl.DeleteTextures(1, &ta.handle)
	ga_remove(texture_arrays, texture_array)
}

set_texture_array_data :: proc {
	set_texture_array_data_at,
	set_texture_array_data_all,
}

set_texture_array_data_at :: proc(ta: Texture_Array, data: $T/[]$E, location := #caller_location) {
	ta := get_texture_array(ta)
	assert(ta.samples == 0, "Cannot set texture data of multisampled texture")
	assert(len(data) == ta.width * ta.height * ta.count)
	format, type := texture_parameters_from_slice(data, location)
	gl.TextureSubImage3D(
		ta.handle,
		0,
		0,
		0,
		i32(ta.width),
		i32(ta.height),
		0,
		format,
		type,
		raw_data(data),
	)
}

set_texture_array_data_all :: proc(ta: Texture_Array, index: int, data: $T/[]$E) {
	texture := get_texture(texture)
	assert(texture.samples == 0, "Cannot set texture data of multisampled texture")
	assert(len(data) == texture.width * texture.height)
	format, type := texture_parameters_from_slice(data)
	gl.TextureSubImage3D(
		texture.handle,
		0,
		0,
		0,
		i32(texture.width),
		i32(texture.height),
		i32(index),
		format,
		type,
		raw_data(data),
	)
}

get_texture_array_data :: proc(ta: Texture_Array, data: $T/[]$E, location := #caller_location) {
	ta := get_texture_array(tex)^
	assert(len(data) == ta.width * ta.height * ta.count)
	format, type := texture_parameters_from_slice(data, location)
	gl.GetTextureImage(ta.handle, 0, format, type, i32(len(data) * size_of(E)), &data[0])
}

Cube_Map :: distinct Index

@(private)
cube_maps: ^Generational_Array(_Cube_Map)

@(private)
get_cube_map :: proc(cube_map: Cube_Map) -> ^_Cube_Map {
	return ga_get(cube_maps, cube_map)
}

@(private)
get_cube_map_handle :: proc(cube_map: Cube_Map) -> (handle: u32, ok: bool) {
	ptr := ga_get(cube_maps, cube_map)
	if ptr == nil {
		return
	}
	return ptr.handle, true
}

_get_cube_map_handle :: proc(cube_map: Cube_Map) -> (handle: u32, ok: bool) {
	return get_cube_map_handle(cube_map)
}

get_cube_map_info :: proc(cube_map: Cube_Map) -> (info: _Cube_Map, ok: bool) {
	ptr := get_cube_map(cube_map)
	if ptr == nil {
		return
	}
	return ptr^, true
}

@(private)
_Cube_Map :: struct {
	using base: Base_Texture_2D,
	mag_filter: Texture_Mag_Filter,
	min_filter: Texture_Min_Filter,
}

Cube_Map_Face :: enum {
	Positive_X = gl.TEXTURE_CUBE_MAP_POSITIVE_X,
	Negative_X = gl.TEXTURE_CUBE_MAP_NEGATIVE_X,
	Positive_Y = gl.TEXTURE_CUBE_MAP_POSITIVE_Y,
	Negative_Y = gl.TEXTURE_CUBE_MAP_NEGATIVE_Y,
	Positive_Z = gl.TEXTURE_CUBE_MAP_POSITIVE_Z,
	Negative_Z = gl.TEXTURE_CUBE_MAP_NEGATIVE_Z,
}

create_cube_map :: proc(
	width: int,
	format: Texture_Format = .RGBA8,
	mag_filter: Texture_Mag_Filter = .Linear,
	min_filter: Texture_Min_Filter = .Linear_Mipmap_Nearest,
) -> Cube_Map {
	t: _Cube_Map = {
		width      = width,
		format     = format,
		min_filter = min_filter,
		mag_filter = mag_filter,
	}

	gl.CreateTextures(gl.TEXTURE_CUBE_MAP, 1, &t.handle)
	gl.TextureStorage2D(t.handle, 1, u32(format), i32(width), i32(width))
	gl.TextureParameteri(t.handle, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TextureParameteri(t.handle, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TextureParameteri(t.handle, gl.TEXTURE_MAG_FILTER, i32(mag_filter))
	gl.TextureParameteri(t.handle, gl.TEXTURE_MIN_FILTER, i32(min_filter))
	return Cube_Map(ga_append(cube_maps, t))
}

destroy_cube_map :: proc(cube_map: Cube_Map) {
	cm := get_cube_map(cube_map)
	gl.DeleteTextures(1, &cm.handle)
	ga_remove(cube_maps, cube_map)
}

@(private)
texture_parameters_from_slice :: proc(
	data: $T/[]$E,
	location: Source_Code_Location,
) -> (
	format, type: u32,
) {
	elem_type: typeid
	when intrinsics.type_is_array(E) {
		N :: len(E)
		when N == 1 {
			format = gl.RED
		} else when N == 2 {
			format = gl.RG
		} else when N == 3 {
			format = gl.RGB
		} else when N == 4 {
			format = gl.RGBA
		} else {
			#panic("Invalid texture data type, array size has to be between 1 and 4")
		}
		#assert(
			intrinsics.type_is_float(intrinsics.type_elem_type(E)) ||
			intrinsics.type_is_integer(intrinsics.type_elem_type(E)),
			"Invalid texture data type",
		)
		elem_type = intrinsics.type_elem_type(E)
	} else {
		#assert(
			intrinsics.type_is_float(E) || intrinsics.type_is_integer(E),
			"Invalid texture data type",
		)
		format = gl.RED
		elem_type = E
	}

	elem_ti := type_info_of(elem_type)
	#partial switch v in elem_ti.variant {
	case reflect.Type_Info_Integer:
		switch elem_ti.size {
		case 1:
			type = v.signed ? gl.BYTE : gl.UNSIGNED_BYTE
		case 2:
			type = v.signed ? gl.SHORT : gl.UNSIGNED_SHORT
		case 4:
			type = v.signed ? gl.INT : gl.UNSIGNED_INT
		case 8, 16:
			panic("Invalid texture component integer size:", elem_ti.size, location = location)
		}
	case reflect.Type_Info_Float:
		switch elem_ti.size {
		case 2:
			type = gl.HALF_FLOAT
		case 4:
			type = gl.FLOAT
		case 8:
			panic("Invalid texture component float size:", elem_ti.size, location = location)
		}
	case:
		unreachable()
	}

	return
}

set_cube_map_face_texture :: proc(
	cm: Cube_Map,
	face: Cube_Map_Face,
	data: $T/[]$E,
	location := #caller_location,
) {
	cm := get_cube_map(cm)
	assert(len(data) == cm.width * cm.width)
	format, type := texture_parameters_from_slice(data, location)
	gl.TexSubImage3D(
		cm.handle,
		0,
		0,
		0,
		i32(face),
		i32(cm.width),
		i32(cm.width),
		0,
		format,
		type,
		raw_data(data),
	)
}

Texture :: distinct Index

@(private)
textures: ^Generational_Array(_Texture)

@(private)
get_texture :: proc(texture: Texture) -> ^_Texture {
	return ga_get(textures, texture)
}

@(private)
get_texture_handle :: proc(texture: Texture) -> (handle: u32, ok: bool) {
	ptr := ga_get(textures, texture)
	if ptr == nil {
		return
	}
	return ptr.handle, true
}

_get_texture_handle :: proc(texture: Texture) -> (handle: u32, ok: bool) {
	return get_texture_handle(texture)
}

get_texture_info :: proc(texture: Texture) -> (info: _Texture, ok: bool) {
	ptr := get_texture(texture)
	if ptr == nil {
		return
	}
	return ptr^, true
}

@(private)
_Texture :: struct {
	using base: Base_Texture_2D,
	using _:    Texture_Sampling_Parameters,
}

Texture_Format_Type :: enum {
	Unsigned_Byte                  = gl.UNSIGNED_BYTE,
	Byte                           = gl.BYTE,
	Unsigned_Short                 = gl.UNSIGNED_SHORT,
	Short                          = gl.SHORT,
	Unsigned_Int                   = gl.UNSIGNED_INT,
	Int                            = gl.INT,
	Half_Float                     = gl.HALF_FLOAT,
	Float                          = gl.FLOAT,
	Unsigned_Byte_3_3_2            = gl.UNSIGNED_BYTE_3_3_2,
	Unsigned_Byte_2_3_3_Rev        = gl.UNSIGNED_BYTE_2_3_3_REV,
	Unsigned_Short_5_6_5           = gl.UNSIGNED_SHORT_5_6_5,
	Unsigned_Short_5_6_5_Rev       = gl.UNSIGNED_SHORT_5_6_5_REV,
	Unsigned_Short_4_4_4_4         = gl.UNSIGNED_SHORT_4_4_4_4,
	Unsigned_Short_4_4_4_4_Rev     = gl.UNSIGNED_SHORT_4_4_4_4_REV,
	Unsigned_Short_5_5_5_1         = gl.UNSIGNED_SHORT_5_5_5_1,
	Unsigned_Short_1_5_5_5_Rev     = gl.UNSIGNED_SHORT_1_5_5_5_REV,
	Unsigned_Int_8_8_8_8           = gl.UNSIGNED_INT_8_8_8_8,
	Unsigned_Int_8_8_8_8_Rev       = gl.UNSIGNED_INT_8_8_8_8_REV,
	Unsigned_Int_10_10_10_2        = gl.UNSIGNED_INT_10_10_10_2,
	Unsigned_Int_2_10_10_10_Rev    = gl.UNSIGNED_INT_2_10_10_10_REV,
	Unsigned_Int_24_8              = gl.UNSIGNED_INT_24_8,
	Unsigned_Int_10F_11F_11F_Rev   = gl.UNSIGNED_INT_10F_11F_11F_REV,
	Unsigned_Int_5_9_9_9_Rev       = gl.UNSIGNED_INT_5_9_9_9_REV,
	Float_32_Unsigned_Int_24_8_Rev = gl.FLOAT_32_UNSIGNED_INT_24_8_REV,
}

Texture_Base_Format :: enum {
	Stencil_Index   = gl.STENCIL_INDEX,
	Depth_Component = gl.DEPTH_COMPONENT,
	Depth_Stencil   = gl.DEPTH_STENCIL,
	Red             = gl.RED,
	Green           = gl.GREEN,
	Blue            = gl.BLUE,
	Rg              = gl.RG,
	Rgb             = gl.RGB,
	Rgba            = gl.RGBA,
	Bgr             = gl.BGR,
	Bgra            = gl.BGRA,
	Red_Integer     = gl.RED_INTEGER,
	Green_Integer   = gl.GREEN_INTEGER,
	Blue_Integer    = gl.BLUE_INTEGER,
	Rg_Integer      = gl.RG_INTEGER,
	Rgb_Integer     = gl.RGB_INTEGER,
	Rgba_Integer    = gl.RGBA_INTEGER,
	Bgr_Integer     = gl.BGR_INTEGER,
	Bgra_Integer    = gl.BGRA_INTEGER,
}

get_texture_data :: proc(tex: Texture, data: $T/[]$E, layer := 0, location := #caller_location) {
	tex := get_texture(tex)^
	assert(len(data) == (tex.width >> uint(layer)) * (tex.height >> uint(layer)))
	format, type := texture_parameters_from_slice(data, location)
	gl.GetTextureImage(tex.handle, i32(layer), format, type, i32(len(data) * size_of(E)), &data[0])
}

write_texture_to_png :: proc {
	write_texture_to_png_default,
	_write_texture_to_png,
}

@(private)
write_texture_to_png_default :: proc(tex: Texture, file_name: string) -> bool {
	return _write_texture_to_png(tex, file_name, 4)
}

@(private)
_write_texture_to_png :: proc(tex: Texture, file_name: string, $C: int) -> (ok: bool) where 1 <= C,
	C <= 4 {
	t := get_texture(tex)
	data := make([][C]byte, t.width * t.height, context.temp_allocator)
	get_texture_data(tex, data)
	return(
		stbi.write_png(
			strings.clone_to_cstring(file_name, context.temp_allocator),
			i32(t.width),
			i32(t.height),
			i32(C),
			raw_data(data),
			0,
		) !=
		0 \
	)
}

Texture_Component_Type :: enum {
	Color,
	Uint,
	Int,
	S_Norm,
	Float,
	Depth,
	Depth_Stencil,
	Depthf,
	Depthf_Stencil,
	Stencil,
}

// format_size :: proc(format: Texture_Format) -> (size: int) {
// 	_, size, _ = format_info(format)
// 	return
// }

// format_channels :: proc(format: Texture_Format) -> (channels: int) {
// 	channels, _, _ = format_info(format)
// 	return
// }

// format_type :: proc(format: Texture_Format) -> (type: Texture_Component_Type) {
// 	_, _, type = format_info(format)
// 	return
// }

format_channels :: proc(format: Texture_Format) -> (channels: int) {
	// type: Texture_Component_Type,
	// format_type: Texture_Base_Format,
	// base_format: Texture_Format_Type,
	switch format {
	case .R8:
		return 1 // 1, .Color, .Red, .Unsigned_Byte
	case .R8_SNORM:
		return 1 // 1, .S_Norm, .Red, .Byte
	case .R16:
		return 1 // 2, .Color, .Red, .Unsigned_Short
	case .R16_SNORM:
		return 1 // 2, .S_Norm, .Red, .Short
	case .RG8:
		return 2 // 2, .Color
	case .RG8_SNORM:
		return 2 // 2, .S_Norm
	case .RG16:
		return 2 // 2, .Color
	case .RG16_SNORM:
		return 2 // 2, .S_Norm
	case .R3_G3_B2:
		return 3 // 1, .Color
	case .RGB4:
		return 3 // 2, .Color
	case .RGB5:
		return 3 // 2, .Color
	case .RGB8:
		return 3 // 3, .Color
	case .RGB8_SNORM:
		return 3 // 3, .S_Norm
	case .RGB10:
		return 3 // 4, .Color
	case .RGB12:
		return 3 // 5, .Color
	case .RGB16_SNORM:
		return 3 // 6, .S_Norm
	case .RGBA2:
		return 4 // 1, .Color
	case .RGBA4:
		return 4 // 2, .Color
	case .RGB5_A1:
		return 4 // 2, .Color
	case .RGBA8:
		return 4 // 4, .Color
	case .RGBA8_SNORM:
		return 4 // 4, .S_Norm
	case .RGB10_A2:
		return 4 // 4, .Color
	case .RGB10_A2UI:
		return 4 // 4, .Uint
	case .RGBA12:
		return 4 // 6, .Color
	case .RGBA16:
		return 4 // 8, .Color
	case .SRGB8:
		return 3 // 3, .Color
	case .SRGB8_ALPHA8:
		return 4 // 4, .Color
	case .R16F:
		return 1 // 2, .Float
	case .RG16F:
		return 2 // 4, .Float
	case .RGB16F:
		return 3 // 6, .Float
	case .RGBA16F:
		return 4 // 8, .Float
	case .R32F:
		return 1 // 4, .Float
	case .RG32F:
		return 2 // 8, .Float
	case .RGB32F:
		return 3 // 12, .Float
	case .RGBA32F:
		return 4 // 16, .Float
	case .R11F_G11F_B10F:
		return 3 // 4, .Float
	case .RGB9_E5:
		return 3 // 4, .Color
	case .R8I:
		return 1 // 1, .Int
	case .R8UI:
		return 1 // 1, .Uint
	case .R16I:
		return 1 // 2, .Int
	case .R16UI:
		return 1 // 2, .Uint
	case .R32I:
		return 1 // 4, .Int
	case .R32UI:
		return 1 // 4, .Uint
	case .RG8I:
		return 2 // 2, .Int
	case .RG8UI:
		return 2 // 2, .Uint
	case .RG16I:
		return 2 // 4, .Int
	case .RG16UI:
		return 2 // 4, .Uint
	case .RG32I:
		return 2 // 8, .Int
	case .RG32UI:
		return 2 // 8, .Uint
	case .RGB8I:
		return 3 // 3, .Int
	case .RGB8UI:
		return 3 // 3, .Uint
	case .RGB16I:
		return 3 // 6, .Int
	case .RGB16UI:
		return 3 // 6, .Uint
	case .RGB32I:
		return 3 // 12, .Int
	case .RGB32UI:
		return 3 // 12, .Uint
	case .RGBA8I:
		return 4 // 4, .Int
	case .RGBA8UI:
		return 4 // 4, .Uint
	case .RGBA16I:
		return 4 // 8, .Int
	case .RGBA16UI:
		return 4 // 8, .Uint
	case .RGBA32I:
		return 4 // 16, .Int
	case .RGBA32UI:
		return 4 // 16, .Uint
	case .Depth16:
		return 1 // 2, .Depth, .Short, .Depth_Component
	case .Depth24:
		return 1 // 3, .Depth, .Unsigned_Int, .Depth_Component
	case .Depth32f:
		return 1 // 4, .Depthf, .Float, .Depth_Component
	case .Depth24_Stencil8:
		return 2 // 4, .Depth_Stencil, .Unsigned_Int_24_8, .Depth_Stencil
	case .Depth32f_Stencil8:
		return 2 // 5, .Depthf_Stencil, .Float_32_Unsigned_Int_24_8_Rev, .Depth_Stencil
	case .Stencil8:
		return 1 // 1, .Stencil, .Unsigned_Byte, .Stencil_Index
	}
	unreachable()
}

get_texture_dimensions :: proc(texture: Texture) -> (width, height: int) {
	t := get_texture(texture)
	width = t.width
	height = t.height
	return
}

get_texture_width :: proc(texture: Texture) -> (width: int) {
	t := get_texture(texture)
	width = t.width
	return
}

get_texture_height :: proc(texture: Texture) -> (height: int) {
	t := get_texture(texture)
	height = t.height
	return
}

set_raw_texture_data :: proc(texture: Texture, data: []byte, location := #caller_location) {
	texture := get_texture(texture)
	assert(texture.samples == 0, "Cannot set texture data of multisampled texture")
	assert(len(data) == texture.width * texture.height)
	format, type := texture_parameters_from_slice(data, location)
	gl.TextureSubImage2D(
		texture.handle,
		0,
		0,
		0,
		i32(texture.width),
		i32(texture.height),
		format,
		type,
		raw_data(data),
	)
}

// if width/height is below 0, it will be treated as the texture's width/height
set_texture_data :: proc(
	texture: Texture,
	data: $T/[]$E,
	x := 0,
	y := 0,
	width := -1,
	height := -1,
	layer := 0,
	location := #caller_location,
) {
	texture := get_texture(texture)
	if layer >= texture.layers {
		errorf(
			"Cannot set texture data at layer %v, since it is out of bounds for texture with %v layers",
			layer,
			texture.layers,
		)
		return
	}

	lw, lh := texture.width >> uint(layer), texture.height >> uint(layer)
	w, h := width, height
	if w < 0 {
		w = lw
	}
	if h < 0 {
		h = lh
	}

	if x < 0 {
		errorf(
			"x parameter of `" + #procedure + "` can not be negative, got: %v",
			x,
			location = location,
		)
	}
	if y < 0 {
		errorf(
			"y parameter of `" + #procedure + "` can not be negative, got: %v",
			y,
			location = location,
		)
	}
	if w + x > texture.width {
		errorf(
			"Invalid x dimensions for `" + #procedure + "`: x: %v, width: %v, layer width: %v",
			x,
			width,
			lw,
			location = location,
		)
		return
	}
	if h + y > texture.height {
		errorf(
			"Invalid y dimensions for `" + #procedure + "`: y: %v, height: %v, layer height: %v",
			y,
			height,
			lh,
			location = location,
		)
		return
	}

	assert(texture.samples == 0, "Cannot set texture data of multisampled texture")
	assertf(
		len(data) == w * h,
		"Size of data does not match dimensions: %v != %v * %v = %v",
		len(data),
		w,
		h,
		w * h,
	)
	format, type := texture_parameters_from_slice(data, location)
	gl.TextureSubImage2D(
		texture.handle,
		i32(layer),
		i32(x),
		i32(y),
		i32(w),
		i32(h),
		format,
		type,
		raw_data(data),
	)
}

create_texture :: proc {
	create_texture_empty,
	create_texture_from_file,
}

create_texture_from_file :: proc(
	path: string,
	layers := 1,
	image_options: image.Options = {},
	location := #caller_location,
) -> (
	texture: Texture,
	ok: bool,
) {
	img, err := image.load(path, image_options, context.temp_allocator)
	if err != nil {
		errorf(
			"Failed to load image from path '%v', due to error: '%v'",
			path,
			err,
			location = location,
		)
		return
	}
	format: Texture_Format
	switch img.channels {
	case 1:
		format = .R8
	case 2:
		format = .RG8
	case 3:
		format = .RGB8
	case 4:
		format = .RGBA8
	case:
		return
	}
	texture = create_texture(img.width, img.height, format, layers, location = location)
	switch img.channels {
	case 1:
		set_texture_data(texture, slice.reinterpret([][1]byte, img.pixels.buf[:]))
	case 2:
		set_texture_data(texture, slice.reinterpret([][2]byte, img.pixels.buf[:]))
	case 3:
		set_texture_data(texture, slice.reinterpret([][3]byte, img.pixels.buf[:]))
	case 4:
		set_texture_data(texture, slice.reinterpret([][4]byte, img.pixels.buf[:]))
	}
	if layers > 1 {
		generate_texture_mipmaps(texture)
	}

	ok = true
	return
}

set_texture_sampling_state :: proc(
	texture: Texture,
	mag_filter: Texture_Mag_Filter = .Linear,
	min_filter: Texture_Min_Filter = .Nearest_Mipmap_Linear,
	wrap: [2]Texture_Wrap = {},
	border_color: [4]f32 = {},
	location := #caller_location,
) {
	t := get_texture(texture)
	if t.samples != 0 {
		error(
			"Multisampled textures cannot be sampled, ignoring sampling state changes",
			location = location,
		)
		return
	}

	for w, direction in wrap {
		if w != t.wrap[direction] {
			gl.TextureParameteri(
				t.handle,
				GL_TEXTURE_WRAP_DIRECTION[direction],
				GL_TEXTURE_WRAP[w],
			)
		}
	}

	if t.mag_filter != mag_filter do gl.TextureParameteri(t.handle, gl.TEXTURE_MAG_FILTER, i32(mag_filter))
	if t.min_filter != min_filter do gl.TextureParameteri(t.handle, gl.TEXTURE_MIN_FILTER, i32(min_filter))

	border_color := border_color
	if t.border_color != border_color do gl.TextureParameterfv(t.handle, gl.TEXTURE_BORDER_COLOR, &border_color[0])

	t.mag_filter = mag_filter
	t.min_filter = min_filter
	t.wrap = wrap
	t.border_color = border_color
}

@(private = "file")
check_multisampling_parameters :: proc(
	format: Texture_Format,
	layers: int,
	samples: int,
	mag_filter: Texture_Mag_Filter = .Linear,
	min_filter: Texture_Min_Filter = .Nearest_Mipmap_Linear,
	wrap: [2]Texture_Wrap = {},
	border_color: [4]f32 = {},
	location: Source_Code_Location,
) -> (
	corrected_samples: int,
) {
	corrected_samples = samples
	if intrinsics.count_ones(corrected_samples) != 1 {
		// go down to the next smaller power of two
		new_samples := 1 << uint(63 - intrinsics.count_leading_zeros(corrected_samples))
		errorf(
			"The number of samples for multisampled textures has to be a power of two, got: '%v'. Proceeding with %v samples",
			samples,
			new_samples,
			location = location,
		)
		corrected_samples = new_samples
	}
	max_samples: i32
	if is_depth_format(format) {
		gl.GetIntegerv(gl.MAX_DEPTH_TEXTURE_SAMPLES, &max_samples)
	} else {
		gl.GetIntegerv(gl.MAX_COLOR_TEXTURE_SAMPLES, &max_samples)
	}
	if corrected_samples > int(max_samples) {
		errorf(
			"Number of textures samples requested (%v) exceeds maximum supported value. Proceeding with %v samples.",
			corrected_samples,
			max_samples,
			location = location,
		)
		corrected_samples = int(max_samples)
	}

	if mag_filter != .Linear {
		warnf(
			"Texture sampler state `mag_filter` explictly set to value `%v` for multisampled texture which can not be sampled",
			mag_filter,
			location = location,
		)
	}
	if min_filter != .Nearest_Mipmap_Linear {
		warnf(
			"Texture sampler state `min_filter` explictly set to value `%v` for multisampled texture which can not be sampled",
			min_filter,
			location = location,
		)
	}
	if wrap != {} {
		warnf(
			"Texture sampler state `wrap` explictly set to value `%v` for multisampled texture which can not be sampled",
			wrap,
			location = location,
		)
	}
	if layers != 1 {
		warnf(
			"Multisampled textures cannot be layered, ignoring explicitly set value for layer count. Value: `%v`",
			layers,
			location = location,
		)
	}
	if border_color != {} {
		warnf(
			"Texture sampler state `border_color` explictly set to value `%v` for multisampled texture which can not be sampled",
			border_color,
			location = location,
		)
	}

	return corrected_samples
}

@(private = "file")
check_texture_layer_count :: proc(
	layers: int,
	location: Source_Code_Location,
	dimensions: ..int,
) -> (
	corrected: int,
) {
	max_mips := max_texture_mipmaps(..dimensions)
	if layers == 0 {
		errorf(
			"Layer count has to be at least one, was %v proceeding with 1",
			layers,
			location = location,
		)
		return 1
	}
	if layers < 1 {
		debugf(
			"Layer count below 0, using maximum number of mipmaps for dimensions, which is %v",
			max_mips,
			location = location,
		)
		return max_mips
	}

	return layers
}

generate_mipmaps :: proc {
	generate_texture_mipmaps,
	generate_texture_array_mipmaps,
}

generate_texture_mipmaps :: proc(texture: Texture, location := #caller_location) {
	handle, ok := get_texture_handle(texture)
	if !ok {
		error("Can not generate texture mipmaps: Invalid texture handle", location = location)
		return
	}
	gl.GenerateTextureMipmap(handle)
}

generate_texture_array_mipmaps :: proc(
	texture_array: Texture_Array,
	location := #caller_location,
) {
	handle, ok := get_texture_array_handle(texture_array)
	if !ok {
		error(
			"Can not generate texture array mipmaps: Invalid texture array handle",
			location = location,
		)
		return
	}
	gl.GenerateTextureMipmap(handle)
}

create_texture_empty :: proc(
	width, height: int,
	format: Texture_Format = .RGBA8,
	layers: int = 1,
	samples: int = 0,
	mag_filter: Texture_Mag_Filter = .Linear,
	min_filter: Texture_Min_Filter = .Nearest_Mipmap_Linear,
	wrap: [2]Texture_Wrap = {},
	border_color: [4]f32 = {},
	location := #caller_location,
) -> Texture {
	t: _Texture = {
		width        = width,
		height       = height,
		format       = format,
		min_filter   = min_filter,
		mag_filter   = mag_filter,
		border_color = border_color,
	}

	if samples > 1 {
		samples := check_multisampling_parameters(
			format,
			layers,
			samples,
			mag_filter,
			min_filter,
			wrap,
			border_color,
			location,
		)
		t.samples = samples
		gl.CreateTextures(gl.TEXTURE_2D_MULTISAMPLE, 1, &t.handle)
		gl.TextureStorage2DMultisample(
			t.handle,
			i32(samples),
			u32(format),
			i32(width),
			i32(height),
			false,
		)
	} else {
		t.samples = 0
		layers := check_texture_layer_count(layers, location, width, height)
		t.layers = layers

		gl.CreateTextures(gl.TEXTURE_2D, 1, &t.handle)
		gl.TextureStorage2D(t.handle, i32(layers), u32(format), i32(width), i32(height))

		for w, direction in wrap {
			gl.TextureParameteri(
				t.handle,
				GL_TEXTURE_WRAP_DIRECTION[direction],
				GL_TEXTURE_WRAP[w],
			)
		}
		gl.TextureParameteri(t.handle, gl.TEXTURE_MAG_FILTER, i32(mag_filter))
		gl.TextureParameteri(t.handle, gl.TEXTURE_MIN_FILTER, i32(min_filter))
		gl.TextureParameterf(t.handle, gl.TEXTURE_MAX_ANISOTROPY, 16)

		border_color := border_color
		gl.TextureParameterfv(t.handle, gl.TEXTURE_BORDER_COLOR, &border_color[0])
	}

	return Texture(ga_append(textures, t))
}

destroy_texture :: #force_inline proc(texture: Texture, location := #caller_location) {
	t, ok := get_texture_handle(texture)
	if !ok {
		error("Tried to delete invalid texture")
		return
	}
	gl.DeleteTextures(1, &t)
	ga_remove(textures, texture)
}

Texture_Format :: enum {
	R8                = gl.R8,
	R8_SNORM          = gl.R8_SNORM,
	R16               = gl.R16,
	R16_SNORM         = gl.R16_SNORM,
	RG8               = gl.RG8,
	RG8_SNORM         = gl.RG8_SNORM,
	RG16              = gl.RG16,
	RG16_SNORM        = gl.RG16_SNORM,
	R3_G3_B2          = gl.R3_G3_B2,
	RGB4              = gl.RGB4,
	RGB5              = gl.RGB5,
	RGB8              = gl.RGB8,
	RGB8_SNORM        = gl.RGB8_SNORM,
	RGB10             = gl.RGB10,
	RGB12             = gl.RGB12,
	RGB16_SNORM       = gl.RGB16_SNORM,
	RGBA2             = gl.RGBA2,
	RGBA4             = gl.RGBA4,
	RGB5_A1           = gl.RGB5_A1,
	RGBA8             = gl.RGBA8,
	RGBA8_SNORM       = gl.RGBA8_SNORM,
	RGB10_A2          = gl.RGB10_A2,
	RGB10_A2UI        = gl.RGB10_A2UI,
	RGBA12            = gl.RGBA12,
	RGBA16            = gl.RGBA16,
	SRGB8             = gl.SRGB8,
	SRGB8_ALPHA8      = gl.SRGB8_ALPHA8,
	R16F              = gl.R16F,
	RG16F             = gl.RG16F,
	RGB16F            = gl.RGB16F,
	RGBA16F           = gl.RGBA16F,
	R32F              = gl.R32F,
	RG32F             = gl.RG32F,
	RGB32F            = gl.RGB32F,
	RGBA32F           = gl.RGBA32F,
	R11F_G11F_B10F    = gl.R11F_G11F_B10F,
	RGB9_E5           = gl.RGB9_E5,
	R8I               = gl.R8I,
	R8UI              = gl.R8UI,
	R16I              = gl.R16I,
	R16UI             = gl.R16UI,
	R32I              = gl.R32I,
	R32UI             = gl.R32UI,
	RG8I              = gl.RG8I,
	RG8UI             = gl.RG8UI,
	RG16I             = gl.RG16I,
	RG16UI            = gl.RG16UI,
	RG32I             = gl.RG32I,
	RG32UI            = gl.RG32UI,
	RGB8I             = gl.RGB8I,
	RGB8UI            = gl.RGB8UI,
	RGB16I            = gl.RGB16I,
	RGB16UI           = gl.RGB16UI,
	RGB32I            = gl.RGB32I,
	RGB32UI           = gl.RGB32UI,
	RGBA8I            = gl.RGBA8I,
	RGBA8UI           = gl.RGBA8UI,
	RGBA16I           = gl.RGBA16I,
	RGBA16UI          = gl.RGBA16UI,
	RGBA32I           = gl.RGBA32I,
	RGBA32UI          = gl.RGBA32UI,
	Depth32f          = gl.DEPTH_COMPONENT32F,
	Depth24           = gl.DEPTH_COMPONENT24,
	Depth16           = gl.DEPTH_COMPONENT16,
	Depth32f_Stencil8 = gl.DEPTH32F_STENCIL8,
	Depth24_Stencil8  = gl.DEPTH24_STENCIL8,
	Stencil8          = gl.STENCIL_INDEX8,
}

is_depth_stencil_format :: proc(format: Texture_Format) -> bool {
	#partial switch format {
	case .Depth32f_Stencil8, .Depth24_Stencil8:
		return true
	case:
		return false
	}
}

is_depth_format :: proc(format: Texture_Format) -> bool {
	#partial switch format {
	case .Depth32f, .Depth24, .Depth16, .Depth32f_Stencil8, .Depth24_Stencil8:
		return true
	case:
		return false
	}
}

Texture_Mag_Filter :: enum {
	Nearest = gl.NEAREST,
	Linear  = gl.LINEAR,
}

Texture_Min_Filter :: enum {
	Nearest                = gl.NEAREST,
	Linear                 = gl.LINEAR,
	Nearest_Mipmap_Nearest = gl.NEAREST_MIPMAP_NEAREST,
	Nearest_Mipmap_Linear  = gl.NEAREST_MIPMAP_LINEAR,
	Linear_Mipmap_Nearest  = gl.LINEAR_MIPMAP_NEAREST,
	Linear_Mipmap_Linear   = gl.LINEAR_MIPMAP_LINEAR,
}

@(rodata, private)
GL_TEXTURE_WRAP_DIRECTION := [3]u32{gl.TEXTURE_WRAP_S, gl.TEXTURE_WRAP_T, gl.TEXTURE_WRAP_R}

Texture_Wrap :: enum {
	Repeat = 0,
	Clamp_To_Edge,
	Clamp_To_Border,
	Mirrored_Repeat,
	Mirror_Clamp_To_Edge,
}

@(rodata, private)
GL_TEXTURE_WRAP := [Texture_Wrap]i32 {
	.Clamp_To_Edge        = gl.CLAMP_TO_EDGE,
	.Clamp_To_Border      = gl.CLAMP_TO_BORDER,
	.Mirrored_Repeat      = gl.MIRRORED_REPEAT,
	.Repeat               = gl.REPEAT,
	.Mirror_Clamp_To_Edge = gl.MIRROR_CLAMP_TO_EDGE,
}

@(private = "file")
max_texture_size: i32
@(private = "file")
max_cube_map_size: i32
@(private = "file")
max_texture_array_layers: i32
@(private = "file")
max_texture_max_anisotropy: i32
@(private)
max_texture_units: i32

@(private)
textures_init :: proc() {
	gl.Enable(gl.TEXTURE_CUBE_MAP_SEAMLESS)

	gl.GetIntegerv(gl.MAX_TEXTURE_SIZE,           &max_texture_size)
	gl.GetIntegerv(gl.MAX_ARRAY_TEXTURE_LAYERS,   &max_texture_array_layers)
	gl.GetIntegerv(gl.MAX_CUBE_MAP_TEXTURE_SIZE,  &max_cube_map_size)
	gl.GetIntegerv(gl.MAX_TEXTURE_MAX_ANISOTROPY, &max_texture_max_anisotropy)
	gl.GetIntegerv(gl.MAX_TEXTURE_IMAGE_UNITS,    &max_texture_units)

	max_texture_units = min(max_texture_units, 128)

	texture_units = make([]Texture, max_texture_units)

	debug("max_texture_size:", max_texture_size)
	debug("max_cube_map_size:", max_cube_map_size)
	debug("max_texture_array_layers:", max_texture_array_layers)
	debug("max_texture_max_anisotropy:", max_texture_max_anisotropy)
	debug("max_texture_units:", max_texture_units)
}

// indicates to `create_texture` (and similar procedures), that the maximum number of mipmaps for the specified dimensions should be allocated
MAX_MIPMAPS :: max(int)

max_texture_mipmaps :: proc(dimensions: ..int) -> (n: int) {
	m: int
	for d in dimensions {
		m = max(m, d)
	}
	return 1 + int(math.floor(math.log2(f64(m))))
}

