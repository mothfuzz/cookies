package main
import "cookies:engine"
import "cookies:window"
import "cookies:graphics"
import "cookies:transform"

cube_trans: transform.Transform
cube_rtt_trans: transform.Transform

main_cam: graphics.Camera

rtt: graphics.Render_Target
rtt_cam: graphics.Camera
rtt_cam2: graphics.Camera

cube_tex: graphics.Texture
cube_mat: graphics.Material
cube_rtt_mat: graphics.Material

Layers :: enum {
    Main,
    RTT,
}

init :: proc() {
    window.set_size(500, 500)

    cube_trans = transform.ORIGIN
    cube_rtt_trans = transform.ORIGIN

    main_cam = graphics.make_camera()
    graphics.look_at(&main_cam, {0, 0, 3}, {0, 0, 0})
    graphics.set_background_color(&main_cam, {1, 0, 1})
    graphics.set_layer_mask(&main_cam, graphics.layers(Layers.Main))

    rtt = graphics.make_render_target({500, 500})

    rtt_cam = graphics.make_camera_relative({0, 0, 0.5, 1})
    graphics.look_at(&rtt_cam, {0, 0, 3}, {0, 0, 0})
    graphics.set_background_color(&rtt_cam, {0, 1, 1})
    graphics.set_layer_mask(&rtt_cam, graphics.layers(Layers.RTT))

    rtt_cam2 = graphics.make_camera_relative({0.5, 0, 0.5, 1})
    graphics.set_background_color(&rtt_cam2, {1, 1, 0})
    graphics.look_at(&rtt_cam2, {0, 0, 3}, {0, 0, 0})
    graphics.set_layer_mask(&rtt_cam2, graphics.layers(Layers.RTT))

    cube_tex = graphics.make_texture_from_image(#load("../resources/rgbtex.png"))
    cube_mat = graphics.make_material(base_color=cube_tex, filtering=false)
    cube_rtt_mat = graphics.make_material(base_color=rtt.output)

}

tick :: proc() {
    transform.rotatex(&cube_trans, 0.01)
    transform.rotatey(&cube_rtt_trans, 0.01)
}

draw :: proc(alpha, delta: f64) {
    //draw one cube to the RTT buffer, use its output to draw a second cube to the screen
    graphics.draw_mesh(graphics.cube_mesh, cube_mat, cube_trans, layers=graphics.layers(Layers.RTT))
    graphics.draw_mesh(graphics.cube_mesh, cube_rtt_mat, cube_rtt_trans, layers=graphics.layers(Layers.Main))

    graphics.draw_render_target(rtt_cam, rtt)
    graphics.draw_camera(main_cam)
    graphics.draw_render_target(rtt_cam2, rtt)
}

quit :: proc() {
    graphics.delete_render_target(rtt)
}

main :: proc() {
    engine.boot(init, tick, draw, quit)
}
