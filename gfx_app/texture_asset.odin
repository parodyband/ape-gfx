package gfx_app

import "core:fmt"
import "core:os"

@(private)
TEXTURE_MAGIC :: u32(0x58545041) // "APTX"
@(private)
TEXTURE_VERSION :: u32(1)
@(private)
TEXTURE_HEADER_SIZE :: 16

Texture_Asset :: struct {
	bytes:  []u8,
	pixels: []u8,
	width:  i32,
	height: i32,
}

load_texture_asset :: proc(path: string) -> (Texture_Asset, bool) {
	bytes, ok := os.read_entire_file(path)
	if !ok {
		return {}, false
	}

	if len(bytes) < TEXTURE_HEADER_SIZE {
		delete(bytes)
		return {}, false
	}

	if read_u32(bytes, 0) != TEXTURE_MAGIC || read_u32(bytes, 4) != TEXTURE_VERSION {
		delete(bytes)
		return {}, false
	}

	width := read_u32(bytes, 8)
	height := read_u32(bytes, 12)
	if width == 0 || height == 0 {
		delete(bytes)
		return {}, false
	}

	data_size := int(width) * int(height) * 4
	if len(bytes) < TEXTURE_HEADER_SIZE + data_size {
		delete(bytes)
		return {}, false
	}

	pixels := bytes[TEXTURE_HEADER_SIZE:TEXTURE_HEADER_SIZE + data_size]
	return {
		bytes = bytes,
		pixels = pixels,
		width = i32(width),
		height = i32(height),
	}, true
}

unload_texture_asset :: proc(asset: ^Texture_Asset) {
	if asset == nil {
		return
	}

	if asset.bytes != nil {
		delete(asset.bytes)
	}
	asset^ = {}
}

must_load_texture_asset :: proc(path: string) -> Texture_Asset {
	asset, ok := load_texture_asset(path)
	if !ok {
		fmt.eprintln("failed to load ", path, "; run tools/convert_texture_rgba8.ps1 first")
		os.exit(1)
	}
	return asset
}

@(private)
read_u32 :: proc(bytes: []u8, offset: int) -> u32 {
	return u32(bytes[offset]) |
	       (u32(bytes[offset + 1]) << 8) |
	       (u32(bytes[offset + 2]) << 16) |
	       (u32(bytes[offset + 3]) << 24)
}
