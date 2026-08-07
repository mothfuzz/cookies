package main

import "cookies:engine"
import "cookies:graphics"
import "cookies:window"
import "cookies:input"

import "cookies:transform"
import "cookies:spatial"

Screen_Width :: 640
Screen_Height :: 400

cam: graphics.Camera
cam_trans: transform.Transform
testmap: graphics.Scene
ball: graphics.Scene
ball_trans: transform.Transform
ball_velocity := [3]f32{0, 0, 0}
Radius :: 1.0/16.0
Ball_Max_Speed :: Radius * 0.9
Ball_Accel :: 0.01

dir_light: graphics.Directional_Light
spot_light: graphics.Spot_Light
environment_probe: graphics.Environment_Probe

font: graphics.Font

init :: proc() {
    window.set_size(Screen_Width, Screen_Height)
    engine.set_tick_rate(30)

    cam = graphics.make_camera()
    cam_trans = transform.make({translation={0, 1, 1}})
    transform.look_at(cam_trans, {0, 0, -1})
    //graphics.look_at(&cam, {0, 1, 1}, {0, 0, -1})
    graphics.set_background_color(&cam, {0.5, 0.25, 0.5})
    graphics.set_draw_distance(&cam, 10.0)
    graphics.set_fog_onset(&cam, 5.0)

    font = graphics.make_font_from_file(#load("../resources/unifont.otf"), 16)

    testmap = graphics.make_scene_from_file("testmap.gltf", #load("testmap.gltf"), make_tri_mesh=true)
    ball = graphics.make_scene_from_file("ball.gltf", #load("ball.gltf"))
    ball_trans = transform.make({translation={0, 0.75, 0}, scale=Radius*2.0})

    dir_light = graphics.make_directional_light({-0.1, -0.7, -0.2}, {1, 1, 1, 5})
    spot_light = graphics.make_spot_light({0, 2, 0}, {0, -1, 0}, 0.1, 0.15, {1, 1, 1, 5})
    environment_probe = graphics.make_environment_probe({0, 0.75, 0}, faces_per_frame=0)
    graphics.set_background_color(&environment_probe.camera, cam.color.rgb)

}

quit :: proc() {
    transform.delete(ball_trans)
    graphics.delete_scene(testmap)
    graphics.delete_scene(ball)
    graphics.delete_font(font)
    graphics.delete_environment_probe(environment_probe)
}

import "core:math"
camera_height: f32 = 0
camera_angle: f32 = math.PI / 2.0
Camera_Speed :: 0.1

tick :: proc() {

    if input.key_pressed(.Key_Escape) {
        window.close()
    }

    c := math.cos(camera_angle)
    s := math.sin(camera_angle)

    if input.key_pressed(.Key_Space) {
        ball_velocity.y += 1
    }
    if input.key_down(.Key_W) {
        ball_velocity.x -= c * Ball_Accel
        ball_velocity.z -= s * Ball_Accel
    }
    if input.key_down(.Key_S) {
        ball_velocity.x += c * Ball_Accel
        ball_velocity.z += s * Ball_Accel
    }
    if input.key_down(.Key_A) {
        ball_velocity.x -= s * Ball_Accel
        ball_velocity.z += c * Ball_Accel
    }
    if input.key_down(.Key_D) {
        ball_velocity.x += s * Ball_Accel
        ball_velocity.z -= c * Ball_Accel
    }
    if input.key_down(.Key_Up) {
        camera_height += Camera_Speed
    }
    if input.key_down(.Key_Down) {
        camera_height -= Camera_Speed
    }
    if input.key_down(.Key_Left) {
        camera_angle += Camera_Speed
    }
    if input.key_down(.Key_Right) {
        camera_angle -= Camera_Speed
    }
    ball_velocity.x *= 0.9 //friction
    ball_velocity.z *= 0.9
    ball_velocity.y -= 0.01 //gravity
    ball_velocity.x = clamp(ball_velocity.x, -Ball_Max_Speed, +Ball_Max_Speed)
    ball_velocity.y = clamp(ball_velocity.y, -Ball_Max_Speed, +Ball_Max_Speed)
    ball_velocity.z = clamp(ball_velocity.z, -Ball_Max_Speed, +Ball_Max_Speed)
    
    ball_trans := transform.write(ball_trans)

    ball_velocity = spatial.move(ball_trans.translation, Radius, ball_velocity, testmap.colliders)
    transform.translate(ball_trans, ball_velocity)
    //a ball rolls at linear velocity / radius
    //but that doesn't look right so we have a 0.7 in there...
    transform.rotatex(ball_trans, ball_velocity.z*(0.7/Radius))
    transform.rotatez(ball_trans, -ball_velocity.x*(0.7/Radius))

    if ball_trans.translation.y < -1.5 {
        ball_trans.translation = {0, 0.75, 0}
    }

    cam_trans := transform.write(cam_trans)
    cam_trans.translation = ball_trans.translation + {c, camera_height, s}
    transform.look_at(cam_trans, ball_trans.translation)
}

draw :: proc(alpha, delta: f64) {
    graphics.draw_camera(cam, transform.world(cam_trans, alpha))
    graphics.draw_directional_light(dir_light)
    graphics.draw_spot_light(spot_light)
    graphics.draw_environment_probe(environment_probe)
    //graphics.draw_model(ball.models[0], transform.world(ball_trans, alpha))
    graphics.draw_mesh(ball.meshes[0], ball.materials[0], transform.world(ball_trans, alpha))
    graphics.draw_scene(testmap, alpha)
    graphics.ui_draw_text("WASD to move ball", font, {-Screen_Width/2+2, Screen_Height/2}, 1)
    graphics.ui_draw_text("Arrow keys to move camera", font, {-Screen_Width/2+2, Screen_Height/2-18}, 1)
}

main :: proc() {
    engine.boot(init, tick, draw, quit)
}
