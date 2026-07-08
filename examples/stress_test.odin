package main

import "cookies:engine"
import "cookies:window"
import "cookies:transform"
import "cookies:graphics"
import "cookies:resources"
import "core:math/rand"
import "core:math/linalg"
import "core:fmt"


//All this tells me is that I need to remove the CPU overhead/allocator churn from renderer.odin

rand_quat :: proc() -> quaternion128 {
    q := quaternion(
        x = rand.float32_normal(0, 1),
        y = rand.float32_normal(0, 1),
        z = rand.float32_normal(0, 1),
        w = rand.float32_normal(0, 1),
    )
    return linalg.normalize(q)
}

Width :: 1600
Height :: 900

cam: graphics.Camera
tree: transform.Tree

light: graphics.Directional_Light

font: graphics.Font

Cube :: struct {
    trans: transform.Node,
}

Cube_Draw :: struct {
    mesh: graphics.Mesh,
    material: graphics.Material,
}
New_Cube_Draw :: Cube_Draw{
    mesh = {path = "../resources/cubie.obj"},
    material = {
        base_color = "../resources/wildbricks/albedo.png",
        normal = "../resources/wildbricks/normal.png",
        pbr = "../resources/wildbricks/glossy.png", //not technically accurate but eh
    },
}

cubes_draw := New_Cube_Draw
cubes: [100000]Cube

init :: proc() {
    window.set_size(Width, Height)
    tree = transform.make_tree()
    for &cube in cubes {
        x := f32(rand.int_range(-Width/2, Width/2))
        y := f32(rand.int_range(-Height/2, Height/2))
        rot := rand_quat()
        cube.trans = transform.create_node(&tree, {translation={x, y, 0}, rotation=rot, scale=3})
    }
    resources.load_all(&cubes_draw)

    cam = graphics.make_camera()
    graphics.look_at(&cam, {0, 0, graphics.z_2d(cam)}, {0, 0, 0})

    light = graphics.make_directional_light({0, 0.2, -0.8}, {1, 1, 1, 10}, false)

    unifont := #load("../resources/unifont.otf")
    font = graphics.make_font_from_file(unifont, 32)
}

tick :: proc() {
    //transform cubes
    for &cube in cubes {
        trans := transform.write(&tree, cube.trans)
        transform.rotatex(trans, 0.01)
        transform.rotatey(trans, 0.01)
        transform.rotatez(trans, 0.01)
    }
}

draw :: proc(alpha, delta: f64) {
    graphics.draw_camera(cam)
    graphics.draw_directional_light(light)
    for &cube in cubes {
        graphics.draw_mesh(cubes_draw.mesh, cubes_draw.material, transform.get_world_smooth(&tree, cube.trans, alpha))
    }
    fps := fmt.tprintf("fps: %f", 1.0/delta)
    graphics.ui_draw_text(fps, font, {-Width/2, +Height/2}, {1, 1, 1, 1})
}

quit :: proc() {
    transform.delete_tree(&tree)
    resources.unload_all(&cubes_draw)
    graphics.delete_font(font)
}

import "core:mem"
main :: proc() {
    when ODIN_OS != .JS {
        track: mem.Tracking_Allocator
        mem.tracking_allocator_init(&track, context.allocator)
        context.allocator = mem.tracking_allocator(&track)
    }

    engine.boot(init, tick, draw, quit)

    when ODIN_OS != .JS {
        if len(track.allocation_map) > 0 {
            fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
            for _, entry in track.allocation_map {
                fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
            }
        }
        if len(track.bad_free_array) > 0 {
            fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
            for entry in track.bad_free_array {
                fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
            }
        }
        mem.tracking_allocator_destroy(&track)
    }
}
