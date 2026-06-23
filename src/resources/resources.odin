package resources

// generic resources manager thingy

//resources.load(^Texture) -> refcounts map[Texture_Ref]Texture, returns Texture


Loaded_Resource :: struct(T: typeid) {
    resource: T,
    refcount: uint,
}

//NO MORE HASHING WOOO
get_resource_map :: proc($K, $V: typeid) -> ^map[K]Loaded_Resource(V) {
    @(static) the_map: map[K]Loaded_Resource(V)
    return &the_map
}

get_loader :: proc($T: typeid) -> (^proc(^T), ^proc(^T)) {
    @(static) load_proc: proc(^T)
    @(static) unload_proc: proc(^T)
    return &load_proc, &unload_proc
}

register_loader :: proc(load_proc: proc(^$T), unload_proc: proc(^T)) {
    l, u := get_loader(T)
    l^ = load_proc
    u^ = unload_proc
}

load :: proc(resource: ^$V) {
    K :: type_of(resource.key)
    res_map := get_resource_map(K, V)
    if key, res, just_inserted, err := map_entry(res_map, resource.key); err == nil {
        if just_inserted {
            res.resource = resource^
            loader, _ := get_loader(V)
            loader^(&res.resource)
            res.resource.key = resource.key
        }
        res.refcount += 1
        resource^ = res.resource
    } 
}

unload :: proc(resource: ^$V) {
    K :: type_of(resource.key)
    res_map := get_resource_map(K, V)
    key := resource.key
    if res, ok := &res_map[key]; ok {
        res.refcount -= 1
        if res.refcount == 0 {
            _, unloader := get_loader(V)
            unloader^(&res.resource)
            delete_key(res_map, key)
        }
        resource^ = {}
        resource.key = key
    }
}

import "file_map"

preload :: file_map.preload
unload_files :: file_map.unload_files

//neat auto-loader for structs of resources

import "cookies:graphics"
load_mesh :: proc(mesh: ^graphics.Mesh) {
    mesh^ = graphics.make_mesh_from_file(file_map.read(mesh.path))
}
unload_mesh :: proc(mesh: ^graphics.Mesh) {
    graphics.delete_mesh(mesh^)
}
load_texture :: proc(tex: ^graphics.Texture) {
    tex^ = graphics.make_texture_from_image(file_map.read(tex.path), tex.linear)
}
unload_texture :: proc(tex: ^graphics.Texture) {
    graphics.delete_texture(tex^)
}
import "core:fmt"
load_material :: proc(mat: ^graphics.Material) {
    fmt.println("loading material:", mat.key)
    base_color_tex := graphics.Texture{path=mat.base_color}
    if mat.base_color == nil || string(mat.base_color) == "" {
        base_color_tex = graphics.white_tex
    } else {
        load(&base_color_tex)
    }
    normal_tex := graphics.Texture{path=mat.normal, linear=true}
    if mat.normal == nil || string(mat.normal) == "" {
       normal_tex = graphics.normal_tex 
    } else {
        load(&normal_tex)
    }
    pbr_tex := graphics.Texture{path=mat.pbr, linear=true}
    if mat.pbr == nil || string(mat.pbr) == "" {
        pbr_tex = graphics.white_tex
    } else {
        load(&pbr_tex)
    }
    emissive_tex := graphics.Texture{path=mat.emissive}
    if mat.emissive == nil || string(mat.emissive) == "" {
        emissive_tex = graphics.black_tex
    } else {
        load(&emissive_tex)
    }
    mat^ = graphics.make_material(base_color_tex, normal_tex, pbr_tex, emissive_tex)
}
unload_material :: proc(mat: ^graphics.Material) {
    if mat.base_color != nil || string(mat.base_color) != "" {
        unload(&mat.base_color_tex)
    }
    if mat.normal != nil || string(mat.normal) != "" {
        unload(&mat.normal_tex)
    }
    if mat.pbr != nil || string(mat.pbr) != "" {
        unload(&mat.pbr_tex)
    }
    if mat.emissive != nil || string(mat.emissive) != "" {
        unload(&mat.emissive_tex)
    }
    graphics.delete_material(mat^)
}
load_scene :: proc(s: ^graphics.Scene) {
    //should ideally use resources but all assets are specific to the scene anyway...
    s^ = graphics.make_scene_from_file(s.path, file_map.read(s.path), s.tree)
}
unload_scene :: proc(s: ^graphics.Scene) {
    graphics.delete_scene(s^)
}
import "cookies:audio"
load_sound :: proc(s: ^audio.Sound) {
    s^ = audio.make_sound_from_file(file_map.read(s.path))
}
unload_sound :: proc(s: ^audio.Sound) {
    audio.delete_sound(s^)
}

register_loaders :: proc() {
    register_loader(load_mesh, unload_mesh)
    register_loader(load_texture, unload_texture)
    register_loader(load_material, unload_material)
    register_loader(load_scene, unload_scene)
    register_loader(load_sound, unload_sound)
}
unregister_loaders :: proc() {
    delete(get_resource_map(graphics.Mesh_Key, graphics.Mesh)^) 
    delete(get_resource_map(graphics.Texture_Key, graphics.Texture)^) 
    delete(get_resource_map(graphics.Material_Key, graphics.Material)^) 
    delete(get_resource_map(graphics.Scene_Key, graphics.Scene)^) 
    delete(get_resource_map(audio.Sound_Key, audio.Sound)^) 
}

import "core:reflect"
load_all :: proc(res: ^$T) {
    for field, i in reflect.struct_fields_zipped(T) {
        ptr := rawptr(uintptr(res) + field.offset)
        switch field.type.id {
        case graphics.Mesh:
            r := cast(^graphics.Mesh)(ptr)
            load(r)
        case graphics.Texture:
            r := cast(^graphics.Texture)(ptr)
            load(r)
        case graphics.Material:
            r := cast(^graphics.Material)(ptr)
            load(r)
        case graphics.Scene:
            r := cast(^graphics.Scene)(ptr)
            load(r)
        case audio.Sound:
            r := cast(^audio.Sound)(ptr)
            load(r)
        }
    }
}

unload_all :: proc(res: ^$T) {
    for field, i in reflect.struct_fields_zipped(T) {
        ptr := rawptr(uintptr(res) + field.offset)
        switch field.type.id {
        case graphics.Mesh:
            r := cast(^graphics.Mesh)(ptr)
            unload(r)
        case graphics.Texture:
            r := cast(^graphics.Texture)(ptr)
            unload(r)
        case graphics.Material:
            r := cast(^graphics.Material)(ptr)
            unload(r)
        case graphics.Scene:
            r := cast(^graphics.Scene)(ptr)
            unload(r)
        case audio.Sound:
            r := cast(^audio.Sound)(ptr)
            unload(r)
        }
    }
}
