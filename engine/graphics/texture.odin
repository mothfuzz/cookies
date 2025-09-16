package graphics

import "vendor:wgpu"
import stbi "vendor:stb/image"
import "core:math"
import "core:fmt"

Texture :: struct {
    image: wgpu.Texture,
    view: wgpu.TextureView,
    size: [2]uint,
}

make_scaled_image_nearest :: proc(input: []u32, in_size, out_size: [2]uint) -> (output: []u32) {
    output = make([]u32, out_size.x * out_size.y)
    scale: [2]f32
    scale.x = f32(out_size.x) / f32(in_size.x)
    scale.y = f32(out_size.y) / f32(in_size.y)
    for i in 0..<out_size.y {
        for j in 0..<out_size.x {
            //nearest neighbor
            x := uint(math.floor((f32(j)+0.5)/f32(scale.x)))
            y := uint(math.floor((f32(i)+0.5)/f32(scale.y)))
            output[i*out_size.x+j] = input[y*in_size.x+x]
        }
    }
    return
}

to_bgra8 :: #force_inline proc(i: u32) -> (o: [4]f32) {
    o.a = f32(i & 0xff000000 >> (3*8))/255.0
    o.r = f32(i & 0x00ff0000 >> (2*8))/255.0
    o.g = f32(i & 0x0000ff00 >> (1*8))/255.0
    o.b = f32(i & 0x000000ff >> (0*8))/255.0
    return
}
from_bgra8 :: #force_inline proc(i: [4]f32) -> (o: u32) {
    o |= u32(i.a*255.0) << (3*8)
    o |= u32(i.r*255.0) << (2*8)
    o |= u32(i.g*255.0) << (1*8)
    o |= u32(i.b*255.0) << (0*8)
    return
}

make_scaled_image_bilinear :: proc(input: []u32, in_size, out_size: [2]uint) -> (output: []u32) {
    output = make([]u32, out_size.x * out_size.y)
    scale: [2]f32
    scale.x = f32(out_size.x) / f32(in_size.x)
    scale.y = f32(out_size.y) / f32(in_size.y)
    //scale.x = max(1, f32(out_size.x-1)) / max(1, f32(in_size.x-1))
    //scale.y = max(1, f32(out_size.y-1)) / max(1, f32(in_size.y-1))
    for i in 0..<out_size.y {
        for j in 0..<out_size.x {
            //bilinear
            x := clamp(f32(j)/scale.x-0.5, 0, f32(in_size.x-1))
            y := clamp(f32(i)/scale.y-0.5, 0, f32(in_size.y-1))
            xi := uint(x)
            yi := uint(y)
            dx := x - f32(xi)
            dy := y - f32(yi)
            l := clamp(xi+0, 0, in_size.x-1)
            r := clamp(xi+1, 0, in_size.x-1)
            u := clamp(yi+0, 0, in_size.y-1)
            d := clamp(yi+1, 0, in_size.y-1)
            ul := to_bgra8(input[u*in_size.x + l])
            ur := to_bgra8(input[u*in_size.x + r])
            dl := to_bgra8(input[d*in_size.x + l])
            dr := to_bgra8(input[d*in_size.x + r])
            top := ul * (1 - dx) + ur * dx
            bot := dl * (1 - dx) + dr * dx
            mix := top * (1 - dy) + bot * dy

            output[i*out_size.x+j] = from_bgra8(mix)
        }
    }
    return
}

make_mips :: proc(input: []u32, size: [2]uint, include_original: bool = false) -> (mips: [dynamic][]u32) {
    mip_size := size
    if include_original {
        append(&mips, input)
    }
    for {
        mip_size /= 2
        if mip_size == {0, 0} {
            break;
        }
        fmt.println("generating:", mip_size)
        append(&mips, make_scaled_image_bilinear(input, size, mip_size))
    }
    return
}

make_texture_2D :: proc(input: []u32, size: [2]uint) -> (tex: Texture) {
    //create texture & write all mips, including original
    mips := make_mips(input, size, true)
    defer delete(mips)
    tex.image = wgpu.DeviceCreateTexture(ren.device, &{
        usage = {.TextureBinding, .CopyDst},
        dimension = ._2D,
        size = {
            width = u32(size.x),
            height = u32(size.y),
            depthOrArrayLayers = 1,
        },
        format = .RGBA8UnormSrgb,
        mipLevelCount = u32(len(mips)),
        sampleCount = 1,
    })
    tex.size = size
    mip_size := size
    for mip, i in mips {
        if mip_size.x == 0 || mip_size.y == 0 {
            break;
        }
        wgpu.QueueWriteTexture(ren.queue, &{texture = tex.image, mipLevel = u32(i)},
                               raw_data(mip),
                               len(mip)*size_of(u32),
                               &{
                                   bytesPerRow = u32(mip_size.x*size_of(u32)),
                                   rowsPerImage = u32(mip_size.y),
                               },
                               &{
                                   width = u32(mip_size.x),
                                   height = u32(mip_size.y),
                                   depthOrArrayLayers=1,
                               },
                              )
        if i != 0 {
            delete(mips[i])
        }
        mip_size /= 2
    }
    tex.view = wgpu.TextureCreateView(tex.image)
    return
}

delete_texture :: proc(tex: Texture) {
    wgpu.TextureRelease(tex.image)
    wgpu.TextureViewRelease(tex.view)
}

//inherently 2D
make_texture_from_image :: proc(image: []byte) -> (tex: Texture) {
    x, y, channels: i32
    img: [^]byte = stbi.load_from_memory(raw_data(image), i32(len(image)), &x, &y, &channels, 4)
    img_u32 := make([]u32, x*y)
    for i in 0..<int(x*y) {
        for b in 0..<4 {
            img_u32[i] |= u32(img[i*4+b]) << uint(b*8)
        }
    }
    tex = make_texture_2D(img_u32, {uint(x), uint(y)})
    stbi.image_free(img)
    delete(img_u32)
    return
}
