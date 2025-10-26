package engine

import "core:fmt"
import "base:runtime"
import "vendor:cgltf"
import "core:strings"
import "core:encoding/base64"
import "core:slice"
import "core:os"

Loaded_File :: struct {
    data: []u8,
    preloaded: bool,
}

loaded_files: map[cstring]Loaded_File
loaded_paths: map[rawptr]cstring

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
    data, ok := os.read_entire_file(string(path))
    if !ok {
        fmt.eprintln("failed to read file:", path)
        return nil
    }
    loaded_files[path] = {data, false}
    loaded_paths[raw_data(data)] = path
    return data
}

import "graphics"
import "transform"

Node_Type :: union {
    ^graphics.Model,
    ^graphics.Camera,
    ^graphics.Light,
}

Node :: struct {
    transform: transform.Transform,
    has_renderable: bool,
    type: Node_Type,
}

//a 'scene' is merely an arrangment of assets.
Layout :: struct {
    name: string,
    roots: []^Node,
}

Scene :: struct {
    //assets
    models: []graphics.Model, //'meshes'
    meshes: []graphics.Mesh,
    textures: []graphics.Texture,
    materials: []graphics.Material,
    skeletons: []graphics.Skeleton, //'skins' //NOTE: when a mesh is animated, its local transform is ignored in favor of the root bone.
    animations: []graphics.Animation,
    cameras: []graphics.Camera,
    lights: []graphics.Light,
    //actual scene
    name: string,
    nodes: []Node,
    layouts: []Layout, //'scenes'
    active_layout: ^Layout,
}

@(private)
load_image :: proc(opts: cgltf.options, image: cgltf.image) -> graphics.Texture {
        //load textures
        if prefix, ok := strings.substring(string(image.uri), 0, 5); ok {
            if prefix == "data:" {
                //load base64
                header, comma, img_base64 := strings.partition(string(image.uri), ",")
                img_size := base64.decoded_len(img_base64)
                img_base64_cstring := strings.clone_to_cstring(img_base64)
                img_data, res := cgltf.load_buffer_base64(opts, uint(img_size), img_base64_cstring)
                delete(img_base64_cstring)
                return graphics.make_texture_from_image(slice.bytes_from_ptr(img_data, img_size))
            }
        }
        //load texture from buffer
        if image.buffer_view != nil {
            buffer_data := slice.bytes_from_ptr(image.buffer_view.buffer.data, int(image.buffer_view.buffer.size))
            img_data := buffer_data[image.buffer_view.offset:image.buffer_view.size]
            return graphics.make_texture_from_image(img_data)
        }
        //lastly but not leastly... it's a file. use the file manager
        return graphics.make_texture_from_image(load(image.uri))
}

@(private)
load_material :: proc(data: ^cgltf.data, scene: ^Scene, material: cgltf.material) -> graphics.Material {
    filtering := true
    tiling := [2]bool{false, false}
    base_color_tex: graphics.Texture = graphics.white_tex
    if material.pbr_metallic_roughness.base_color_texture.texture != nil {
        base_color_index := cgltf.image_index(data, material.pbr_metallic_roughness.base_color_texture.texture.image_)
        base_color_tex = scene.textures[base_color_index]

        sampler := material.pbr_metallic_roughness.base_color_texture.texture.sampler
        filtering = sampler.mag_filter == .linear
        tiling[0] = sampler.wrap_s != .clamp_to_edge
        tiling[1] = sampler.wrap_t != .clamp_to_edge
    }

    normal_tex: graphics.Texture = graphics.normal_tex
    if material.normal_texture.texture != nil {
        normal_index := cgltf.image_index(data, material.normal_texture.texture.image_)
        normal_tex = scene.textures[normal_index]

    }

    pbr_tex: graphics.Texture = graphics.white_tex
    if material.pbr_metallic_roughness.metallic_roughness_texture.texture != nil {
        pbr_index := cgltf.image_index(data, material.pbr_metallic_roughness.metallic_roughness_texture.texture.image_)
        pbr_tex = scene.textures[pbr_index]
    }

    emissive_tex: graphics.Texture = graphics.black_tex
    if material.emissive_texture.texture != nil {
        emissive_index := cgltf.image_index(data, material.emissive_texture.texture.image_)
        emissive_tex = scene.textures[emissive_index]
    }

    return graphics.make_material(base_color_tex, normal_tex, pbr_tex, emissive_tex, filtering, tiling)
}

@(private)
load_mesh :: proc(primitive: cgltf.primitive) -> graphics.Mesh {
    indices_len := cgltf.accessor_unpack_indices(primitive.indices, nil, 4, 0)
    indices := make([]u32, indices_len)
    if cgltf.accessor_unpack_indices(primitive.indices, raw_data(indices), 4, indices_len) < indices_len {
        fmt.eprintln("failed to load all indices!")
    }
    fmt.println(indices)
    vertices: #soa[]graphics.Vertex = nil
    default_colors := true
    for attribute in primitive.attributes {
        size := cgltf.accessor_unpack_floats(attribute.data, nil, 0)
        if vertices == nil {
            vertices = make(#soa[]graphics.Vertex, size)
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
    return graphics.make_mesh_from_soa(vertices, indices)
}

make_scene_from_file :: proc(filename: cstring, filedata: []u8) -> (scene: Scene) {

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

    //TODO: load lights...
    //TODO: load cameras...

    scene.textures = make([]graphics.Texture, len(data.images))
    for image, i in data.images {
        scene.textures[i] = load_image(opts, image)
    }

    scene.materials = make([]graphics.Material, len(data.materials))
    for material, i in data.materials {
        scene.materials[i] = load_material(data, &scene, material)
    }

    scene.models = make([]graphics.Model, len(data.meshes))
    total_meshes := 0
    for mesh in data.meshes {
        total_meshes += len(mesh.primitives)
    }
    scene.meshes = make([]graphics.Mesh, total_meshes)
    current_mesh := 0
    for mesh, i in data.meshes {
        model := &scene.models[i]
        model.meshes = make([]^graphics.Mesh, len(mesh.primitives))
        model.materials = make([]^graphics.Material, len(mesh.primitives))
        for primitive, j in mesh.primitives {

            material_index := cgltf.material_index(data, primitive.material)
            model.materials[j] = &scene.materials[material_index]

            scene.meshes[current_mesh] = load_mesh(primitive)
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
            fmt.println("parent node:", p, ", child node:", i)
            transform.link(&scene.nodes[p].transform, &scene.nodes[i].transform) //this should work but if it doesn't I guess I'll fix it
        }
        if node.has_matrix {
            //extract TRS from matrix
            mat := transmute(matrix[4,4]f32)(node.matrix_)
            position, orientation, scale := transform.extract(mat)
            transform.set_position(&scene.nodes[i].transform, position)
            transform.set_orientation_quaternion(&scene.nodes[i].transform, orientation)
            transform.set_scale(&scene.nodes[i].transform, scale)
        } else {
            //load TRS directly
            if node.has_translation {
                transform.set_position(&scene.nodes[i].transform, node.translation)
            }
            if node.has_rotation {
                rot := transmute(quaternion128)(node.rotation) //both are xyzw
                transform.set_orientation_quaternion(&scene.nodes[i].transform, rot)
            }
            if node.has_scale {
                transform.set_scale(&scene.nodes[i].transform, node.scale)
            }
        }
        if node.mesh != nil {
            index := cgltf.mesh_index(data, node.mesh)
            scene.nodes[i].type = &scene.models[index]
            scene.nodes[i].has_renderable = true
        }
        if node.camera != nil {
            index := cgltf.camera_index(data, node.camera)
            scene.nodes[i].type = &scene.cameras[index]
            scene.nodes[i].has_renderable = true
        }
        if node.light != nil {
            index := cgltf.light_index(data, node.light)
            scene.nodes[i].type = &scene.lights[index]
            scene.nodes[i].has_renderable = true
        }
    }
    scene.layouts = make([]Layout, len(data.scenes))
    for layout, i in data.scenes {
        scene.layouts[i].roots = make([]^Node, len(layout.nodes))
        for node, j in layout.nodes {
            scene.layouts[i].roots[j] = &scene.nodes[cgltf.node_index(data, node)]
        }
    }
    scene.active_layout = &scene.layouts[cgltf.scene_index(data, data.scene)]

    cgltf.free(data)
    return
}

node_from_transform :: proc(trans: ^transform.Transform) -> ^Node {
    return cast(^Node)(uintptr(trans) - offset_of(Node, transform))
}

draw_node :: proc(node: ^Node, t: f64) {
    //draw self
    if node.has_renderable {
        if model, ok := node.type.(^graphics.Model); ok {
            graphics.draw_model(model^, transform.smooth(&node.transform, t))
            //graphics.draw_model(model^, transform.compute(&node.transform))
        }
        //TODO: light
        //TODO: camera...?
    }
    //draw immediate sibling (will trigger subsequent draws)
    if node.transform.next_sibling != nil {
        draw_node(node_from_transform(node.transform.next_sibling), t)
    }
    //draw first child (will trigger subsequent draws)
    if node.transform.first_child != nil {
        draw_node(node_from_transform(node.transform.first_child), t)
    }
}
draw_scene :: proc(scene: ^Scene, t: f64) {
    for node in scene.active_layout.roots {
        draw_node(node, t)
    }
}
