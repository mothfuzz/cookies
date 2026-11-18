package graphics

import "vendor:wgpu"

//growable buffers & texture arrays

Growable_Buffer :: struct {
    buffer: wgpu.Buffer,
    usage: wgpu.BufferUsageFlags,
    capacity: u64,
}

//new_size in bytes
grow_buffer :: proc(g: ^Growable_Buffer, new_len: int, $T: typeid) -> bool {
    new_cap := size_of(T) * max(1, new_len) //wgpu buffers can't be zero-sized
    if u64(new_cap) > g.capacity || g.buffer == nil {
        g.capacity = u64(new_cap) //g.capacity * 2
        if g.buffer != nil do wgpu.BufferRelease(g.buffer)
        g.buffer = wgpu.DeviceCreateBuffer(ren.device, &{usage = g.usage, size = g.capacity})
        return true
    }
    return false
}

write_buffer :: proc(g: ^Growable_Buffer, data: []$T) -> (rebind: bool) {
    rebind = grow_buffer(g, len(data), T)
    if len(data) > 0 {
        wgpu.QueueWriteBuffer(ren.queue, g.buffer, 0, raw_data(data), len(data)*size_of(T))
    }
    return
}

Growable_Texture_Array :: struct {
    texture: wgpu.Texture,
    texture_view: wgpu.TextureView,
    layers: []wgpu.TextureView, //per array layer (or per-face for cubes)
    size: [2]u32,
    format: wgpu.TextureFormat,
    usage: wgpu.TextureUsageFlags,
    mip_count: u32,
    cubemap: bool,
    preserve: bool, //copy-on-grow
    capacity: u32,
}

grow_texture_array :: proc(g: ^Growable_Texture_Array, new_len: int, command_encoder: wgpu.CommandEncoder = nil) -> bool {
    new_cap := max(1, new_len)
    if u32(new_cap) > g.capacity || g.texture == nil {
        prev_layers := 6*g.capacity if g.cubemap else g.capacity
        g.capacity = u32(new_cap) //g.capacity * 2

        extents := wgpu.Extent3D{
            width = g.size.x,
            height = g.size.y,
            depthOrArrayLayers = 6*g.capacity if g.cubemap else g.capacity
        }

        new_texture := wgpu.DeviceCreateTexture(ren.device, &{
            usage = g.usage,
            dimension = ._2D,
            size = extents,
            format = g.format,
            mipLevelCount = g.mip_count,
            sampleCount = 1
        })

        if g.preserve && command_encoder != nil && g.texture != nil {
            for i in 0..<g.mip_count {
                mip_extents := wgpu.Extent3D{
                    width = max(1, g.size.x >> i),
                    height = max(1, g.size.y >> i),
                    depthOrArrayLayers = prev_layers,
                }
                wgpu.CommandEncoderCopyTextureToTexture(command_encoder,
                                                        &{texture=g.texture, mipLevel=i},
                                                        &{texture=new_texture, mipLevel=i},
                                                        &mip_extents)
            }
        }

        if g.texture != nil do wgpu.TextureRelease(g.texture)
        if g.texture_view != nil do wgpu.TextureViewRelease(g.texture_view)
        for layer in g.layers {
            wgpu.TextureViewRelease(layer)
        }

        g.texture = new_texture

        g.texture_view = wgpu.TextureCreateView(g.texture, &{
            dimension = .CubeArray if g.cubemap else ._2DArray,
            mipLevelCount = g.mip_count,
            arrayLayerCount = extents.depthOrArrayLayers,
        })

        delete(g.layers)
        g.layers = make([]wgpu.TextureView, extents.depthOrArrayLayers)
        for i in 0..<extents.depthOrArrayLayers {
            g.layers[i] = wgpu.TextureCreateView(g.texture, &{
                dimension = ._2D,
                baseArrayLayer = i,
                arrayLayerCount = 1,
                baseMipLevel = 0,
                mipLevelCount = 1,
            })
        }
        
        return true
    }
    return false
}
