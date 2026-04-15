package graphics

import "core:fmt"
import "base:runtime"
import "vendor:cgltf"
import "core:strings"
import "core:encoding/base64"
import "core:slice"
import "core:mem"

Loaded_File :: struct {
    data: []u8,
    preloaded: bool,
}

loaded_files: map[cstring]Loaded_File
loaded_paths: map[rawptr]cstring

unload_files :: proc() {
    delete(loaded_files)
    delete(loaded_paths)
}

check :: proc() {
    if loaded_files == nil {
        loaded_files = make(map[cstring]Loaded_File)
    }
    if loaded_paths == nil {
        loaded_paths = make(map[rawptr]cstring)
    }
}

read :: proc "c" (memory_options: ^cgltf.memory_options, file_options: ^cgltf.file_options, path: cstring, size: ^uint, data: ^rawptr) -> (res: cgltf.result) {
    context = (^runtime.Context)(file_options.user_data)^
    check()
    if !(path in loaded_files) {
        data := make([]u8, 500)
        loaded_files[path] = {data, false}
        loaded_paths[raw_data(data)] = path
    }
    data^ = raw_data(loaded_files[path].data)
    size^ = len(loaded_files[path].data)
    return
}
release :: proc "c" (memory_options: ^cgltf.memory_options, file_options: ^cgltf.file_options, data: rawptr) {
    context = (^runtime.Context)(file_options.user_data)^
    check()
    file := loaded_files[loaded_paths[data]]
    if !file.preloaded {
        delete(file.data)
        delete_key(&loaded_files, loaded_paths[data])
        delete_key(&loaded_paths, data)
    }
}

preload :: proc(path: cstring, file: []u8) {
    check()
    loaded_files[path] = {file, true}
    loaded_paths[raw_data(file)] = path
}


load :: proc(path: cstring) -> []u8 {
    check()
    if path in loaded_files {
        return loaded_files[path].data
    }
    data := read_from_disk(path)
    if data == nil {
        fmt.eprintln("failed to read file:", path)
        return nil
    }
    loaded_files[path] = {data, false}
    loaded_paths[raw_data(data)] = path
    return data
}

import "cookies:transform"
import "cookies:spatial"

Node_Type :: enum {
    Node, //i.e. non-renderable
    Model,
    Camera,
    Light,
}

Node :: struct {
    name: string,
    transform: transform.Transform,
    original_position: [3]f32, //to be used when not-animated
    original_orientation: quaternion128,
    original_scale: [3]f32,
    parent_node: uint, //for easier copying
    type: Node_Type,
    data: uint, //index into Models/Cameras/Lights
}

//a 'scene' is merely an arrangment of assets.
Layout :: struct {
    name: string,
    roots: []uint,
}


Scene :: struct {
    //assets
    meshes: []Mesh, //'primitives'
    colliders: []spatial.Tri_Mesh,
    textures: []Texture,
    materials: []Material,
    skeletons: []Skeleton, //'skins'
    animations: []Animation,
    //instanced data
    copied: bool,
    models: []Model, //'meshes'
    cameras: []Camera,
    lights: []Light,
    //actual scene
    name: string,
    nodes: []Node,
    layouts: []Layout, //'scenes'
    active_layout: uint,
}

copy_scene :: proc(scene: ^Scene, new_name: string = "") -> (s: Scene) {
    //assets
    s.meshes = scene.meshes
    s.colliders = scene.colliders
    s.textures = scene.textures
    s.materials = scene.materials
    s.skeletons = scene.skeletons
    s.animations = scene.animations
    //instanced data
    s.copied = true
    s.models = make([]Model, len(scene.models))
    for &model, i in s.models {
        model.materials = make([]^Material, len(scene.models[i].materials))
        copy(model.materials, scene.models[i].materials)
        model.meshes = make([]^Mesh, len(scene.models[i].meshes))
        copy(model.meshes, scene.models[i].meshes)
    }
    s.cameras = make([]Camera, len(scene.cameras))
    copy(s.cameras, scene.cameras)
    s.lights = make([]Light, len(scene.lights))
    copy(s.lights, scene.lights)
    //actual scene
    if new_name != "" {
        s.name = new_name
    } else {
        s.name = scene.name
    }
    s.nodes = make([]Node, len(scene.nodes))
    copy(s.nodes, scene.nodes)
    //have to do this in 2 passes to preserve relationships
    for &node in s.nodes {
        //can't use 'unlink' bc we don't want to mess up the original's hierarchy
        node.transform.first_child = nil
        node.transform.last_child = nil
        node.transform.prev_sibling = nil
        node.transform.next_sibling = nil
    }
    for &node in s.nodes {
        if node.transform.parent != nil {
            transform.link(&s.nodes[node.parent_node].transform, &node.transform)
        }
    }
    s.layouts = make([]Layout, len(scene.layouts))
    for &layout, i in s.layouts {
        layout.roots = make([]uint, len(scene.layouts[i].roots))
        copy(layout.roots, scene.layouts[i].roots)
    }
    s.active_layout = scene.active_layout
    
    return
}

@(private)
load_image :: proc(opts: cgltf.options, image: cgltf.image) -> Texture {
        //load textures
        if prefix, ok := strings.substring(string(image.uri), 0, 5); ok {
            if prefix == "data:" {
                //load base64
                header, comma, img_base64 := strings.partition(string(image.uri), ",")
                img_size := base64.decoded_len(img_base64)
                img_base64_cstring := strings.clone_to_cstring(img_base64)
                img_data, res := cgltf.load_buffer_base64(opts, uint(img_size), img_base64_cstring)
                delete(img_base64_cstring)
                return make_texture_from_image(slice.bytes_from_ptr(img_data, img_size))
            }
        }
        //load texture from buffer
        if image.buffer_view != nil {
            buffer_data := slice.bytes_from_ptr(image.buffer_view.buffer.data, int(image.buffer_view.buffer.size))
            img_data := buffer_data[image.buffer_view.offset:image.buffer_view.size]
            return make_texture_from_image(img_data)
        }
        //lastly but not leastly... it's a file. use the file manager
        return make_texture_from_image(load(image.uri))
}

@(private)
load_material :: proc(data: ^cgltf.data, scene: ^Scene, material: cgltf.material) -> Material {
    filtering := true
    tiling := [2]bool{false, false}
    base_color_tex: Texture = white_tex
    if material.pbr_metallic_roughness.base_color_texture.texture != nil {
        base_color_index := cgltf.image_index(data, material.pbr_metallic_roughness.base_color_texture.texture.image_)
        base_color_tex = scene.textures[base_color_index]

        sampler := material.pbr_metallic_roughness.base_color_texture.texture.sampler
        filtering = sampler.mag_filter == .linear
        tiling[0] = sampler.wrap_s != .clamp_to_edge
        tiling[1] = sampler.wrap_t != .clamp_to_edge
    }

    normal_tex: Texture = normal_tex
    if material.normal_texture.texture != nil {
        normal_index := cgltf.image_index(data, material.normal_texture.texture.image_)
        normal_tex = scene.textures[normal_index]

    }

    pbr_tex: Texture = white_tex
    if material.pbr_metallic_roughness.metallic_roughness_texture.texture != nil {
        pbr_index := cgltf.image_index(data, material.pbr_metallic_roughness.metallic_roughness_texture.texture.image_)
        pbr_tex = scene.textures[pbr_index]
    }

    emissive_tex: Texture = black_tex
    if material.emissive_texture.texture != nil {
        emissive_index := cgltf.image_index(data, material.emissive_texture.texture.image_)
        emissive_tex = scene.textures[emissive_index]
    }

    return make_material(base_color_tex, normal_tex, pbr_tex, emissive_tex, filtering, tiling)
}

@(private)
load_mesh :: proc(primitive: cgltf.primitive, make_tri_mesh: bool) -> (mesh: Mesh, collider: spatial.Tri_Mesh) {
    indices_len := cgltf.accessor_unpack_indices(primitive.indices, nil, 4, 0)
    indices := make([]u32, indices_len)
    defer delete(indices)
    if cgltf.accessor_unpack_indices(primitive.indices, raw_data(indices), 4, indices_len) < indices_len {
        fmt.eprintln("failed to load all indices!")
    }
    fmt.println(indices)
    vertices: #soa[]Vertex = nil
    defer delete(vertices)
    default_colors := true
    for attribute in primitive.attributes {
        size := cgltf.accessor_unpack_floats(attribute.data, nil, 0)
        if vertices == nil {
            vertices = make(#soa[]Vertex, size)
        }
        switch attribute.type {
        case .position:
            if cgltf.accessor_unpack_floats(attribute.data, raw_data(vertices.position), size) < size {
                fmt.eprintln("failed to load all positions!")
            }
        case .normal:
            if cgltf.accessor_unpack_floats(attribute.data, raw_data(vertices.normal), size) < size {
                fmt.eprintln("failed to load all normals!")
            }
        case .tangent:
            if cgltf.accessor_unpack_floats(attribute.data, raw_data(vertices.tangent), size) < size {
                fmt.eprintln("failed to load all tangents!")
            }
        case .texcoord:
            if cgltf.accessor_unpack_floats(attribute.data, raw_data(vertices.texcoord), size) < size {
                fmt.eprintln("failed to load all texcoords!")
            }
        case .color:
            default_colors = false
            if cgltf.accessor_unpack_floats(attribute.data, raw_data(vertices.color), size) < size {
                fmt.eprintln("failed to load all colors!")
            }
        case .joints:
            if cgltf.accessor_unpack_floats(attribute.data, raw_data(vertices.bones), size) < size {
                fmt.eprintln("failed to load all bones!")
            }
        case .weights:
            if cgltf.accessor_unpack_floats(attribute.data, raw_data(vertices.weights), size) < size {
                fmt.eprintln("failed to load all weights!")
            }
        case .invalid, .custom:
            //do nothing...?
        }
    }
    if default_colors {
        for &vertex in vertices {
            vertex.color = 1
        }
    }
    mesh = make_mesh_from_soa(vertices, indices)
    if make_tri_mesh {
        collider = spatial.make_tri_mesh(vertices.position[0:len(vertices)], indices)
    }
    return
}

@(private)
load_animation :: proc(data: ^cgltf.data, scene: ^Scene, animation: cgltf.animation) -> (a: Animation) {
    a.name = string(animation.name)
    a.channels = make([]Animation_Channel, len(animation.channels))
    for channel, i in animation.channels {
        out_channel := &a.channels[i]
        input_len := cgltf.accessor_unpack_floats(channel.sampler.input, nil, 0)
        out_channel.input = make([]f32, input_len)
        output_tmp: [^]f32
        if cgltf.accessor_unpack_floats(channel.sampler.input, raw_data(out_channel.input), input_len) < input_len {
            fmt.eprintln("failed to load all input keyframes!")
        }
        output_len := cgltf.accessor_unpack_floats(channel.sampler.output, nil, 0)
        //copy data into the animation itself, easier on the brain.
        switch channel.target_path {
        case .translation:
            out_channel.output = make(Keyframes_Translation, output_len/3)
            output_tmp = &out_channel.output.(Keyframes_Translation)[0].x
        case .rotation:
            out_channel.output = make(Keyframes_Rotation, output_len/4)
            output_tmp = &out_channel.output.(Keyframes_Rotation)[0].x
        case .scale:
            out_channel.output = make(Keyframes_Scale, output_len/3)
            output_tmp = &out_channel.output.(Keyframes_Scale)[0].x
        case .weights:
            //out_channel.output = make(Keyframes_Weights, ...)
            //not supported
        case .invalid:
            fmt.eprintln("invalid animation path type!")
        }
        if cgltf.accessor_unpack_floats(channel.sampler.output, output_tmp, output_len) < output_len {
            fmt.eprintln("failed to load all output keyframes!")
        }
        switch channel.sampler.interpolation {
        case .linear:
            out_channel.interp = .Linear
        case .step:
            out_channel.interp = .Step
        case .cubic_spline:
            //out_channel.interp = .Cubic_Spline
            //not supported
        }
        out_channel.target_node = cgltf.node_index(data, channel.target_node)
    }
    return
}

@(private)
load_skeleton :: proc(data: ^cgltf.data, scene: ^Scene, skin: cgltf.skin) -> (sk: Skeleton) {
    sk.bones = make([]Bone, len(skin.joints))
    inv_binds: []f32 = make([]f32, len(skin.joints)*16)
    defer delete(inv_binds)
    if cgltf.accessor_unpack_floats(skin.inverse_bind_matrices, raw_data(inv_binds), len(inv_binds)) < len(inv_binds) {
        fmt.eprintln("failed to load all inverse bind matrices!")
    }
    for joint, i in skin.joints {
        bone := &sk.bones[i]
        mem.copy(&bone.inv_bind, &inv_binds[i*16], size_of(matrix[4,4]f32))
        node := cgltf.node_index(data, joint)
        bone.node = node
        if joint == skin.skeleton {
            sk.root = uint(i)
        }
    }
    return
}

make_scene_from_file :: proc(filename: cstring, filedata: []u8, make_tri_mesh: bool = false) -> (scene: Scene) {

    ctx := context
    opts := cgltf.options{
        file = {read, release, &ctx},
    }

    data, res := cgltf.parse(opts, raw_data(filedata), len(filedata))
    if res != .success {
        fmt.eprintln(res)
        return
    }

    //load assets (starting with singular data, then compound data)
    res = cgltf.load_buffers(opts, data, filename)
    if res != .success {
        fmt.eprintln(res)
        return
    }

    // TODO: load lights...
    // TODO: load cameras...

    scene.textures = make([]Texture, len(data.images))
    for image, i in data.images {
        scene.textures[i] = load_image(opts, image)
    }

    scene.materials = make([]Material, len(data.materials))
    for material, i in data.materials {
        scene.materials[i] = load_material(data, &scene, material)
    }

    scene.models = make([]Model, len(data.meshes))
    total_meshes := 0
    for mesh in data.meshes {
        total_meshes += len(mesh.primitives)
    }
    scene.meshes = make([]Mesh, total_meshes)
    if make_tri_mesh {
        scene.colliders = make([]spatial.Tri_Mesh, total_meshes)
    }
    current_mesh := 0
    for mesh, i in data.meshes {
        model := &scene.models[i]
        model.meshes = make([]^Mesh, len(mesh.primitives))
        model.materials = make([]^Material, len(mesh.primitives))
        for primitive, j in mesh.primitives {

            material_index := cgltf.material_index(data, primitive.material)
            model.materials[j] = &scene.materials[material_index]

            mesh, collider := load_mesh(primitive, make_tri_mesh)
            scene.meshes[current_mesh] = mesh
            if make_tri_mesh {
                scene.colliders[current_mesh] = collider
            }
            model.meshes[j] = &scene.meshes[current_mesh]
            current_mesh += 1
        }
    }

    //load scene
    scene.nodes = make([]Node, len(data.nodes))
    for &node in scene.nodes {
        node.transform = transform.ORIGIN
    }
    for node, i in data.nodes {
        if node.parent != nil {
            p := cgltf.node_index(data, node.parent)
            scene.nodes[i].parent_node = p //otherwise 0
            transform.link(&scene.nodes[p].transform, &scene.nodes[i].transform) //this should work but if it doesn't I guess I'll fix it
        }
        if node.has_matrix {
            //extract TRS from matrix
            mat := transmute(matrix[4,4]f32)(node.matrix_)
            position, orientation, scale := transform.extract(mat)
            transform.set_position(&scene.nodes[i].transform, position)
            transform.set_orientation_quaternion(&scene.nodes[i].transform, orientation)
            transform.set_scale(&scene.nodes[i].transform, scale)
            scene.nodes[i].original_position = position
            scene.nodes[i].original_orientation = orientation
            scene.nodes[i].original_scale = scale
        } else {
            //load TRS directly
            if node.has_translation {
                transform.set_position(&scene.nodes[i].transform, node.translation)
                scene.nodes[i].original_position = node.translation
            }
            if node.has_rotation {
                rot := transmute(quaternion128)(node.rotation) //both are xyzw
                transform.set_orientation_quaternion(&scene.nodes[i].transform, rot)
                scene.nodes[i].original_orientation = rot
            }
            if node.has_scale {
                transform.set_scale(&scene.nodes[i].transform, node.scale)
                scene.nodes[i].original_scale = node.scale
            }
        }
        scene.nodes[i].type = .Node //by default
        if node.mesh != nil {
            index := cgltf.mesh_index(data, node.mesh)
            scene.nodes[i].type = .Model
            scene.nodes[i].data = index
        }
        if node.camera != nil {
            index := cgltf.camera_index(data, node.camera)
            scene.nodes[i].type = .Camera
            scene.nodes[i].data = index
        }
        if node.light != nil {
            index := cgltf.light_index(data, node.light)
            scene.nodes[i].type = .Light
            scene.nodes[i].data = index
        }
    }
    scene.layouts = make([]Layout, len(data.scenes))
    for layout, i in data.scenes {
        scene.layouts[i].roots = make([]uint, len(layout.nodes))
        for node, j in layout.nodes {
            scene.layouts[i].roots[j] = cgltf.node_index(data, node)
        }
    }
    scene.active_layout = cgltf.scene_index(data, data.scene)

    //now that we have nodes loaded, load animation data
    scene.animations = make([]Animation, len(data.animations))
    for animation, i in data.animations {
        scene.animations[i] = load_animation(data, &scene, animation)
    }
    scene.skeletons = make([]Skeleton, len(data.skins))
    for skin, i in data.skins {
        scene.skeletons[i] = load_skeleton(data, &scene, skin)
    }
    
    cgltf.free(data)
    return
}

node_from_transform :: proc(trans: ^transform.Transform) -> ^Node {
    return cast(^Node)(uintptr(trans) - offset_of(Node, transform))
}

draw_node :: proc(scene: ^Scene, node: ^Node, t: f64) {
    //draw self
    switch node.type {
    case .Node:
    case .Model:
        draw_model(scene.models[node.data], transform.smooth(&node.transform, t))
    case .Camera:
        //...
    case .Light:
        //...
    }
    //draw immediate sibling (will trigger subsequent draws)
    if node.transform.next_sibling != nil {
        draw_node(scene, node_from_transform(node.transform.next_sibling), t)
    }
    //draw first child (will trigger subsequent draws)
    if node.transform.first_child != nil {
        draw_node(scene, node_from_transform(node.transform.first_child), t)
    }
}
draw_scene :: proc(scene: ^Scene, alpha: f64, delta: f64, anim: ^Animation_State = nil) {
    if anim != nil {
        progress(scene, anim, delta)
    }
    for i in scene.layouts[scene.active_layout].roots {
        draw_node(scene, &scene.nodes[i], alpha)
    }
}

link_scene_transform :: proc(scene: ^Scene, parent: ^transform.Transform) {
    for i in scene.layouts[scene.active_layout].roots {
        node := &scene.nodes[i]
        transform.link(parent, &node.transform)
    }
}
unlink_scene_transform :: proc(scene: ^Scene) {
    for i in scene.layouts[scene.active_layout].roots {
        node := &scene.nodes[i]
        transform.unlink(&node.transform)
    }
}

delete_scene :: proc(scene: ^Scene) {
    if !scene.copied {
        for &texture in scene.textures {
            delete_texture(texture)
        }
        delete(scene.textures)
        for &mesh in scene.meshes {
            delete_mesh(mesh)
        }
        delete(scene.meshes)
        for &material in scene.materials {
            delete_material(material)
        }
        delete(scene.materials)
        for &tri_mesh in scene.colliders {
            spatial.delete_tri_mesh(tri_mesh)
        }
        delete(scene.colliders)
        for &skeleton in scene.skeletons {
            delete_skeleton(skeleton)
        }
        delete(scene.skeletons)
        for &animation in scene.animations {
            delete_animation(animation)
        }
        delete(scene.animations)
    }

    for &model in scene.models {
        delete(model.meshes)
        delete(model.materials)
    }
    delete(scene.models)
    /*for &camera in scene.cameras {
        delete_camera(camera)
    }
    delete(scene.cameras)
    for &light in scene.lights {
        delete_light(scene.lights)
    }
    delete(scene.lights)*/

    for &layout in scene.layouts {
        delete(layout.roots)
    }
    delete(scene.layouts)

    delete(scene.nodes)
}
