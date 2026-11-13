package graphics

import "vendor:wgpu"
import "core:hash"
import "core:slice"


Material_Hash :: distinct uintptr

Material_Key :: struct {
    base_color: cstring,
    normal: cstring,
    pbr: cstring,
    emissive: cstring,
}

Material :: struct {
    using key: Material_Key,
    bind_group: wgpu.BindGroup,
    sampler: wgpu.Sampler,
    base_color_tex: Texture,
    normal_tex: Texture,
    pbr_tex: Texture,
    emissive_tex: Texture,
    //
    hash: Material_Hash,
}

Material_Params :: struct {
    clip_rect: [4]f32,
    base_color_mul: [4]f32,
    base_color_add: [4]f32,
    pbr_mul: [3]f32,
    pbr_add: [3]f32,
    emissive_mul: [3]f32,
    emissive_add: [3]f32,
}

Default_Material_Params :: Material_Params {0, 1, 0, 1, 0, 1, 0}

//you can do so much with a material...
mat_params :: proc(clip_rect: [4]f32 = 0, base_color_mul: [3]f32 = 1, base_color_add: [3]f32 = 0,
                   alpha_mul: f32 = 1, alpha_add: f32 = 0,
                   ambient_mul: f32 = 1, ambient_add: f32 = 0,
                   roughness_mul: f32 = 1, roughness_add: f32 = 0,
                   metallic_mul: f32 = 1, metallic_add: f32 = 0,
                   emissive_mul: [3]f32 = 1, emissive_add: [3]f32 = 0,
                  ) -> (params: Material_Params) {
                      params.clip_rect = clip_rect
                      params.base_color_mul.rgb = base_color_mul
                      params.base_color_add.rgb = base_color_add
                      params.base_color_mul.a = alpha_mul
                      params.base_color_add.a = alpha_add
                      params.pbr_mul.r = ambient_mul
                      params.pbr_add.r = ambient_add
                      params.pbr_mul.g = roughness_mul
                      params.pbr_add.g = roughness_add
                      params.pbr_mul.b = metallic_mul
                      params.pbr_add.b = metallic_add
                      params.emissive_mul = emissive_mul
                      params.emissive_add = emissive_add
                      return
                  }

@(private)
//convert clip_rect to real uvs
normalize_clip_rect :: proc(rect: [4]f32, tex_size: [2]f32) -> (uv: [4]f32) {
    uv.xy = rect.xy / tex_size
    uv.zw = rect.zw / tex_size
    if rect[2] == 0 do uv[2] = 1
    if rect[3] == 0 do uv[3] = 1
    return
}

rebuild_material :: proc(mat: ^Material) {
    if mat.bind_group != nil {
        delete_material_bind_group(mat.bind_group)
    }
    mat.bind_group = make_material_bind_group(
        mat.base_color_tex.view,
        mat.normal_tex.view,
        mat.pbr_tex.view,
        mat.emissive_tex.view,
        mat.sampler,
    )
    mat.hash = 0 //do not hash hashes
    mat.hash = Material_Hash(hash.fnv32a(slice.bytes_from_ptr(mat, size_of(Material))))
}

make_material :: proc(base_color: Texture=white_tex, normal: Texture=normal_tex, pbr: Texture=pbr_tex, emissive: Texture=black_tex, filtering: bool = true, tiling: [2]bool = false) -> (mat: Material) {
    mat.sampler = wgpu.DeviceCreateSampler(ren.device, &{
        minFilter = .Linear if filtering else .Nearest,
        magFilter = .Linear if filtering else .Nearest,
        mipmapFilter = .Linear if filtering else .Nearest,
        maxAnisotropy = 16 if filtering else 1,
        addressModeU = .Repeat if tiling.x else .ClampToEdge,
        addressModeV = .Repeat if tiling.y else .ClampToEdge,
        lodMinClamp = 0,
        lodMaxClamp = 32,
    })
    mat.base_color_tex = base_color
    mat.normal_tex = normal
    mat.pbr_tex = pbr
    mat.emissive_tex = emissive
    rebuild_material(&mat)
    return
}

delete_material :: proc(mat: Material) {
    wgpu.SamplerRelease(mat.sampler)
    delete_material_bind_group(mat.bind_group)
}
