package main

import "../engine"
import "../engine/graphics"
import "../engine/window"
import "../engine/input"

import "../engine/transform"
import "../engine/spatial"

Screen_Width :: 640
Screen_Height :: 400

cam: graphics.Camera
testmap: engine.Scene
ball: engine.Scene
ball_trans := transform.ORIGIN
ball_velocity := [3]f32{0, 0, 0}
Radius :: 1.0/16.0
Ball_Max_Speed :: Radius * 0.9
Ball_Accel :: 0.01

font: graphics.Font

init :: proc() {
    window.set_size(Screen_Width, Screen_Height)
    engine.set_tick_rate(30)

    cam = graphics.make_camera({0, 0, Screen_Width, Screen_Height})
    graphics.look_at(&cam, {0, 1, 1}, {0, 0, -1})
    graphics.set_camera(&cam)

    font = graphics.make_font_from_file(#load("../unifont.otf"), 16)

    testmap = engine.make_scene_from_file("testmap.gltf", #load("testmap.gltf"), make_tri_mesh=true)
    ball = engine.make_scene_from_file("ball.gltf", #load("ball.gltf"))
    transform.set_position(&ball_trans, {0, 0.75, 0})
    transform.set_scale(&ball_trans, Radius*2.0)

}

quit :: proc() {
    graphics.delete_camera(cam)
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
    ball_velocity = spatial.move(ball_trans.position, Radius, ball_velocity, testmap.colliders)
    transform.translate(&ball_trans, ball_velocity)

    graphics.look_to(&cam, ball_trans.position + {c, camera_height, s}, ball_trans.position)
}

draw :: proc(t: f64) {
    graphics.draw_mesh(ball.meshes[0], ball.materials[0], transform.smooth(&ball_trans, t))
    engine.draw_scene(&testmap, t)
    graphics.ui_draw_text("WASD to move ball", font, {-Screen_Width/2+2, Screen_Height/2}, 1)
    graphics.ui_draw_text("Arrow keys to move camera", font, {-Screen_Width/2+2, Screen_Height/2-18}, 1)
}

main :: proc() {
    engine.boot(init, tick, draw, quit)
}
