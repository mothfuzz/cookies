package graphics

import "core:log"
import "base:runtime"
import "vendor:cgltf"
import "core:strings"
import "core:encoding/base64"
import "core:slice"
import "core:mem"
import "core:math/linalg"

import "cookies:resources/file_map" //needed since gltf references sub-data
import "cookies:transform"
import "cookies:spatial"

//loader procs so cgltf can read from engine resources
read :: proc "c" (memory_options: ^cgltf.memory_options, file_options: ^cgltf.file_options, path: cstring, size: ^uint, data: ^rawptr) -> (res: cgltf.result) {
    context = (^runtime.Context)(file_options.user_data)^
    file := file_map.read(path)
    data^ = raw_data(file)
    size^ = len(file)
    return
}
release :: proc "c" (memory_options: ^cgltf.memory_options, file_options: ^cgltf.file_options, data: rawptr) {
    context = (^runtime.Context)(file_options.user_data)^
    file_map.release(data)
}

Node_Type :: enum {
    Node, //i.e. non-renderable
    Model,
    Camera,
    Light,
}

Node :: struct {
    name: string,
    using trans: transform.Node,
    original_trans: transform.Transform, //to be used when not-animated
    //for easier copying/traversal
    has_parent: bool,
    parent_node: uint,
    children: []uint,
    //for rendering
    type: Node_Type,
    data: uint, //index into Models/Cameras/Lights
    animated: bool,
    skin: uint,
}

//a 'scene' is merely an arrangment of assets.
Layout :: struct {
    name: string,
    roots: []uint,
}

Scene_Key :: struct {
    path: cstring,
    tree: ^transform.Tree,
}

Scene :: struct {
    using key: Scene_Key,
    //assets (TODO: move to resource manager)
    meshes: []Mesh, //'primitives'
    colliders: []spatial.Tri_Mesh, // TODO: get this out of here.
    materials: []Combined_Material,
    skeletons: []Skeleton, //'skins'
    animations: []Animation,
    //instanced data
    copied: bool,
    models: []Model, //'meshes'
    cameras: []Camera,
    //point_lights: []Point_Light,
    //directional_lights: []Directional_Light,
    //spot_lights: []Spot_Light,
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
    s.materials = scene.materials
    s.skeletons = scene.skeletons
    s.animations = scene.animations
    //instanced data
    s.copied = true
    s.models = make([]Model, len(scene.models))
    for &model, i in s.models {
        model.materials = make([]Combined_Material, len(scene.models[i].materials))
        copy(model.materials, scene.models[i].materials)
        model.meshes = make([]Mesh, len(scene.models[i].meshes))
        copy(model.meshes, scene.models[i].meshes)
    }
    s.cameras = make([]Camera, len(scene.cameras))
    copy(s.cameras, scene.cameras)
    // TODO: lights...
    //actual scene
    if new_name != "" {
        s.name = new_name
    } else {
        s.name = scene.name
    }
    s.tree = scene.tree
    s.nodes = make([]Node, len(scene.nodes))
    copy(s.nodes, scene.nodes)
    //have to do this in 2 passes to preserve relationships
    for &node, i in s.nodes {
        node.trans = transform.create_node(s.tree)
        trans := transform.write(s.tree, node)
        orig_trans := transform.read(scene.tree, scene.nodes[i])
        trans.translation = orig_trans.translation
        trans.rotation = orig_trans.rotation
        trans.scale = orig_trans.scale
        orig_children := scene.nodes[i].children
        if orig_children != nil {
            node.children = make([]uint, len(orig_children))
            copy(node.children, orig_children)
        }
    }
    for &node in s.nodes {
        if node.has_parent {
            transform.link(s.tree, s.nodes[node.parent_node].trans, node.trans)
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

// TODO: rewrite load_image and load_material to load w/correct linear + premultiplied alpha depending on how the image is used in the material
// skip loading textures not used in any material.
// if the user wants to load arbitrary data they can load the texture themselves :P

@(private)
load_image :: proc(gltf_path: cstring, opts: cgltf.options, image: ^cgltf.image, linear: bool = false) -> (tex: Texture) {
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
    
    path := resolve_image_path(gltf_path, image.uri)
    tex = make_texture_from_image(file_map.read(path), linear)
    file_map.release(path)
    return
}

@(private)
load_material :: proc(gltf_path: cstring, opts: cgltf.options, material: cgltf.material) -> Combined_Material {
    filtering := true
    tiling := [2]bool{false, false}
    base_color_tex: Texture = white_tex
    base_color_tint: [4]f32 = 1
    pbr_tint: [4]f32 = 1
    emissive_tint: [4]f32 = 1
    if material.pbr_metallic_roughness.base_color_texture.texture != nil {
        base_color_tex = load_image(gltf_path, opts, material.pbr_metallic_roughness.base_color_texture.texture.image_)

        sampler := material.pbr_metallic_roughness.base_color_texture.texture.sampler
        filtering = sampler.mag_filter == .linear
        tiling[0] = sampler.wrap_s != .clamp_to_edge
        tiling[1] = sampler.wrap_t != .clamp_to_edge
    }
    if material.pbr_metallic_roughness.base_color_factor != 0 {
        base_color_tint = material.pbr_metallic_roughness.base_color_factor
    }

    normal_tex: Texture = normal_tex
    if material.normal_texture.texture != nil {
        normal_tex = load_image(gltf_path, opts, material.normal_texture.texture.image_, true)

    }

    pbr_tex: Texture = pbr_tex
    if material.pbr_metallic_roughness.metallic_roughness_texture.texture != nil {
        pbr_tex = load_image(gltf_path, opts, material.pbr_metallic_roughness.metallic_roughness_texture.texture.image_, true)
    }
    //no such occlusion_factor, so no pbr_tint.r
    if material.pbr_metallic_roughness.roughness_factor != 0 {
        pbr_tint.g = material.pbr_metallic_roughness.roughness_factor
    }
    if material.pbr_metallic_roughness.metallic_factor != 0 {
        pbr_tint.b = material.pbr_metallic_roughness.metallic_factor
    }

    emissive_tex: Texture = black_tex
    if material.emissive_texture.texture != nil {
        emissive_tex = load_image(gltf_path, opts, material.emissive_texture.texture.image_)
    }
    if material.emissive_factor != 0 {
        emissive_tint.rgb = material.emissive_factor
    }

    ret_material := make_material(base_color_tex, normal_tex, pbr_tex, emissive_tex, filtering, tiling)
    return {ret_material, {base_color_tint=base_color_tint, pbr_tint=pbr_tint, emissive_tint=emissive_tint}}
}

@(private)
load_mesh :: proc(primitive: cgltf.primitive, make_tri_mesh: bool) -> (mesh: Mesh, collider: spatial.Tri_Mesh) {
    indices_len := cgltf.accessor_unpack_indices(primitive.indices, nil, 4, 0)
    indices := make([]u32, indices_len)
    defer delete(indices)
    if cgltf.accessor_unpack_indices(primitive.indices, raw_data(indices), 4, indices_len) < indices_len {
        log.error("failed to load all indices!")
    }
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
                log.error("failed to load all positions!")
            }
        case .normal:
            if cgltf.accessor_unpack_floats(attribute.data, raw_data(vertices.normal), size) < size {
                log.error("failed to load all normals!")
            }
        case .tangent:
            if cgltf.accessor_unpack_floats(attribute.data, raw_data(vertices.tangent), size) < size {
                log.error("failed to load all tangents!")
            }
        case .texcoord:
            if cgltf.accessor_unpack_floats(attribute.data, raw_data(vertices.texcoord), size) < size {
                log.error("failed to load all texcoords!")
            }
        case .color:
            default_colors = false
            if cgltf.accessor_unpack_floats(attribute.data, raw_data(vertices.color), size) < size {
                log.error("failed to load all colors!")
            }
        case .joints:
            if cgltf.accessor_unpack_floats(attribute.data, raw_data(vertices.bones), size) < size {
                log.error("failed to load all bones!")
            }
        case .weights:
            if cgltf.accessor_unpack_floats(attribute.data, raw_data(vertices.weights), size) < size {
                log.error("failed to load all weights!")
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
            log.error("failed to load all input keyframes!")
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
            log.error("invalid animation path type!")
        }
        if cgltf.accessor_unpack_floats(channel.sampler.output, output_tmp, output_len) < output_len {
            log.error("failed to load all output keyframes!")
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
        log.error("failed to load all inverse bind matrices!")
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

make_scene_from_file :: proc(filename: cstring, filedata: []u8, tree: ^transform.Tree, make_tri_mesh: bool = false) -> (scene: Scene) {

    ctx := context
    opts := cgltf.options{
        file = {read, release, &ctx},
    }

    data, res := cgltf.parse(opts, raw_data(filedata), len(filedata))
    if res != .success {
        log.error("could not parse scene:", filename)
        log.error(res)
        return
    }

    //load assets (starting with singular data, then compound data)
    res = cgltf.load_buffers(opts, data, filename)
    if res != .success {
        log.error("could not load buffers for scene", filename)
        log.error(res)
        return
    }

    // TODO: load lights...
    // TODO: load cameras...

    scene.materials = make([]Combined_Material, len(data.materials))
    for material, i in data.materials {
        scene.materials[i] = load_material(filename, opts, material)
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
        model.meshes = make([]Mesh, len(mesh.primitives))
        model.materials = make([]Combined_Material, len(mesh.primitives))
        for primitive, j in mesh.primitives {

            material_index := cgltf.material_index(data, primitive.material)
            model.materials[j] = scene.materials[material_index]

            mesh, collider := load_mesh(primitive, make_tri_mesh)
            scene.meshes[current_mesh] = mesh
            if make_tri_mesh {
                scene.colliders[current_mesh] = collider
            }
            model.meshes[j] = scene.meshes[current_mesh]
            current_mesh += 1
        }
    }

    //load scene
    scene.tree = tree
    scene.nodes = make([]Node, len(data.nodes))
    for &node in scene.nodes {
        node.trans = transform.create_node(scene.tree)
    }
    for node, i in data.nodes {
        if node.parent != nil {
            p := cgltf.node_index(data, node.parent)
            scene.nodes[i].has_parent = true
            scene.nodes[i].parent_node = p //otherwise 0
            transform.link(scene.tree, scene.nodes[p].trans, scene.nodes[i].trans)
        }
        if node.children != nil && len(node.children) > 0 {
            scene.nodes[i].children = make([]uint, len(node.children))
            for child, c in node.children {
                scene.nodes[i].children[c] = cgltf.node_index(data, child)
            }
        }
        trans := transform.write(scene.tree, scene.nodes[i].trans)
        if node.has_matrix {
            //extract TRS from matrix
            mat := transmute(matrix[4,4]f32)(node.matrix_)
            translation, rotation, scale := transform.get_world_trs(mat)
            trans.translation = translation
            trans.rotation = rotation
            trans.scale = scale
            scene.nodes[i].original_trans.translation = translation
            scene.nodes[i].original_trans.rotation = rotation
            scene.nodes[i].original_trans.scale = scale
        } else {
            //load TRS directly
            if node.has_translation {
                trans.translation = node.translation
                scene.nodes[i].original_trans.translation = node.translation
            } else {
                scene.nodes[i].original_trans.translation = 0
            }
            if node.has_rotation {
                rot := transmute(quaternion128)(node.rotation) //both are xyzw
                trans.rotation = rot
                scene.nodes[i].original_trans.rotation = rot
            } else {
                scene.nodes[i].original_trans.rotation = 1
            }
            if node.has_scale {
                trans.scale = node.scale
                scene.nodes[i].original_trans.scale = node.scale
            } else {
                scene.nodes[i].original_trans.scale = 1
            }
        }
        scene.nodes[i].type = .Node //by default
        if node.mesh != nil {
            index := cgltf.mesh_index(data, node.mesh)
            scene.nodes[i].type = .Model
            scene.nodes[i].data = index
            if node.skin != nil {
                scene.nodes[i].animated = true
                scene.nodes[i].skin = cgltf.skin_index(data, node.skin)
            }
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

@(private)
calculate_skeleton :: proc(scene: Scene, node: Node, alpha: f64) -> []matrix[4,4]f32 {
    bones: [dynamic]matrix[4,4]f32
    if node.animated {
        //look up the actual skeleton, and multiply with inv_bind
        //animation *should* be fully calculated at this point
        skeleton := &scene.skeletons[node.skin]
        bones = make([dynamic]matrix[4,4]f32)
        for &bone in skeleton.bones {
            inv_trans := linalg.inverse(transform.get_world_smooth(scene.tree, node, alpha))
            bone_trans := transform.get_world_smooth(scene.tree, scene.nodes[bone.node], alpha)
            append(&bones, inv_trans * bone_trans * bone.inv_bind)
        }
    } else {
        //just use identity
        bones = make([dynamic]matrix[4,4]f32)
        append(&bones, 1)
    }
    return bones[:]
}


@(private)
draw_node :: proc(scene: Scene, node: Node, alpha: f64, layers: Layer_Mask) {
    //draw self
    switch node.type {
    case .Node:
    case .Model:
        bones := calculate_skeleton(scene, node, alpha)
        defer delete(bones)
        draw_model(scene.models[node.data], transform.get_world_smooth(scene.tree, node, alpha), bones, layers)
    case .Camera:
        //...
    case .Light:
        //...
    }
    //draw children (will trigger subsequent draws)
    for child in node.children {
        draw_node(scene, scene.nodes[child], alpha, layers)
    }
}
draw_scene :: proc(scene: Scene, alpha: f64, layers: Layer_Mask = All_Layers) {
    for i in scene.layouts[scene.active_layout].roots {
        draw_node(scene, scene.nodes[i], alpha, layers)
    }
}

link_scene_transform :: proc(scene: ^Scene, parent: transform.Node) {
    for i in scene.layouts[scene.active_layout].roots {
        transform.link(scene.tree, parent, scene.nodes[i])
    }
}
unlink_scene_transform :: proc(scene: ^Scene) {
    for i in scene.layouts[scene.active_layout].roots {
        transform.unlink(scene.tree, scene.nodes[i])
    }
}

delete_scene :: proc(scene: Scene) {
    if !scene.copied {
        for mesh in scene.meshes {
            delete_mesh(mesh)
        }
        delete(scene.meshes)
        for material in scene.materials {
            //delete textures if not the defaults
            if material.base.base_color_tex.image != white_tex.image do delete_texture(material.base.base_color_tex)
            if material.base.normal_tex.image != normal_tex.image do delete_texture(material.base.normal_tex)
            if material.base.pbr_tex.image != pbr_tex.image do delete_texture(material.base.pbr_tex)
            if material.base.emissive_tex.image != black_tex.image do delete_texture(material.base.emissive_tex)
            delete_material(material.base)
        }
        delete(scene.materials)
        for tri_mesh in scene.colliders {
            spatial.delete_tri_mesh(tri_mesh)
        }
        delete(scene.colliders)
        for skeleton in scene.skeletons {
            delete_skeleton(skeleton)
        }
        delete(scene.skeletons)
        for animation in scene.animations {
            delete_animation(animation)
        }
        delete(scene.animations)
    }

    for model in scene.models {
        delete(model.meshes)
        delete(model.materials)
    }
    delete(scene.models)
    /*for camera in scene.cameras {
        delete_camera(camera)
    }
    delete(scene.cameras)*/
    // TODO: lights

    for layout in scene.layouts {
        delete(layout.roots)
    }
    delete(scene.layouts)

    for node in scene.nodes {
        transform.delete_node(scene.tree, node)
        if node.children != nil {
            delete(node.children)
        }
    }
    delete(scene.nodes)
}
