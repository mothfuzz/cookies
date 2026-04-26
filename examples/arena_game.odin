package main

import "cookies:engine"
import "cookies:window"
import "cookies:input"
import "cookies:graphics"
import "cookies:transform"
import "core:fmt"
import "core:math/linalg"
import "core:math/rand"
import hm "core:container/handle_map"

/*
BOX VS SPHERES (title displayed in window)
- simple arena shooter
- score displayed as text in the upper left
- health displayed as text below
- enemies spawn off-screen in a random ring around you and simply walk towards your current location
- can move with WASD and aim with mouse
- stacked sprites
- player's stack will move offset (i.e. bottom layer first, all layers on top 1 pixel behind per layer) for a trailing effect
- player is a cube
- enemies are spheres
- reticle will be shown as a sprite where the mouse is (or maybe just the mouse itself?)
- bullets are point v sphere
- player/enemy collision is sphere vs transformed boxoid: find closest point and then do point v sphere
- only calculate transforms when player moves
- don't transform enemies they're fuckin spherees
- player can shoot on a (small) timer - test this so it feels good
- cool metal/orchestral/electronic track that loops
- firing and hitting sounds abstract, not really a gunshot or splat or whatever
- CLICK TO START
*/

Player :: struct {
    hp: uint,
    score: uint,
    trans: transform.Transform,
}
Bullet :: struct {
    handle: hm.Handle16,
    trans: transform.Transform,
    trajectory: f32,
}

Enemy :: struct {
    handle: hm.Handle16,
    trans: transform.Transform,
    trajectory: f32,
}

player: Player
enemies: hm.Dynamic_Handle_Map(Enemy, hm.Handle16)
bullets: hm.Dynamic_Handle_Map(Bullet, hm.Handle16)

//graphics
player_sprite: graphics.Texture
player_mat: graphics.Material
enemy_sprite: graphics.Texture
enemy_mat: graphics.Material
bullet_sprite: graphics.Texture
bullet_mat: graphics.Material

//global stuff

cam: graphics.Camera

big_font: graphics.Font
regular_font: graphics.Font

debug_enabled: bool = false

Game_State :: enum {
    Title,
    Playing,
    Paused,
    Died,
    Won,
}
gamestate: Game_State

//consts
Screen_Width :: 800
Screen_Height :: 800
Big_Font_Size :: 32
Regular_Font_Size :: 16

Player_Speed: f32 : 4
Bullet_Speed: f32 : 8
Enemy_Speed: f32 : 1

init :: proc() {

    window.set_size(Screen_Width, Screen_Height) //TODO: recenter window upon resizing

    cam = graphics.make_camera({0, 0, Screen_Width, Screen_Height})
    graphics.look_at(&cam, {0, 0, graphics.z_2d(cam)}, {0, 0, 0})
    graphics.set_viewport(&cam, {0, 0, Screen_Width, Screen_Height})

    unifont := #load("../resources/unifont.otf")
    big_font = graphics.make_font_from_file(unifont, Big_Font_Size*2)
    regular_font = graphics.make_font_from_file(unifont, Regular_Font_Size*2)

    //player resources
    player_sprite = graphics.make_texture_from_image(#load("arena_game_player.png"))
    player_mat = graphics.make_material(base_color=player_sprite, filtering=false)
    player.trans = transform.ORIGIN
    transform.set_scale(&player.trans, {2, 2, 1})
    player.hp = 10
    player.score = 0

    //bullet resources
    bullet_sprite = graphics.make_texture_from_image(#load("arena_game_bullet.png"))
    bullet_mat = graphics.make_material(base_color=bullet_sprite, filtering=false)

    //enemy resources
    enemy_sprite = graphics.make_texture_from_image(#load("arena_game_enemy.png"))
    enemy_mat = graphics.make_material(base_color=enemy_sprite, filtering=false)

    //maps
    hm.dynamic_init(&enemies, context.allocator)
    hm.dynamic_init(&bullets, context.allocator)
}

update_player :: proc() {

    mouse_pos := [2]f32{f32(input.mouse_position().x), f32(input.mouse_position().y)}
    player_pos := transform.get_position(&player.trans)
    mouse_vec := mouse_pos - player_pos.xy
    angle := linalg.atan2(mouse_vec.y, mouse_vec.x)

    transform.set_orientation(&player.trans, {0, 0, angle-linalg.PI/2}, true)

    //relative movement, works for 3D but not really for 2D
    /*x := linalg.cos(angle)*Player_Speed
    y := linalg.sin(angle)*Player_Speed
    if input.key_down(.Key_W) {
        transform.translate(&player.trans, {x, y, 0})
    }
    if input.key_down(.Key_S) {
        transform.translate(&player.trans, {-x, -y, 0})
    }
    if input.key_down(.Key_A) {
        transform.translate(&player.trans, {-y, x, 0})
    }
    if input.key_down(.Key_D) {
        transform.translate(&player.trans, {y, -x, 0})
    }*/
    if input.key_down(.Key_W) {
        transform.translate(&player.trans, {0, +Player_Speed, 0})
    }
    if input.key_down(.Key_S) {
        transform.translate(&player.trans, {0, -Player_Speed, 0})
    }
    if input.key_down(.Key_A) {
        transform.translate(&player.trans, {-Player_Speed, 0, 0})
    }
    if input.key_down(.Key_D) {
        transform.translate(&player.trans, {+Player_Speed, 0, 0})
    }

    if input.mouse_pressed(.Left) {
        new_trans := transform.ORIGIN
        transform.set_position(&new_trans, player_pos)
        _ = hm.add(&bullets, Bullet{trans=new_trans, trajectory=angle})
    }

}

counter := 0
spawn_enemy :: proc() {
    //spawn them in at a random position off screen
    angle := (0.1 + rand.float32()) * linalg.PI * 2
    x := linalg.cos(angle)*(Screen_Width/2+Screen_Width/4)
    y := linalg.sin(angle)*(Screen_Height/2+Screen_Height/4)
    new_trans := transform.ORIGIN
    transform.set_position(&new_trans, {x, y, 0})
    transform.set_scale(&new_trans, {4, 4, 0})

    _ = hm.add(&enemies, Enemy{trans=new_trans})
}

update_enemies :: proc() {
    counter += 1
    if counter > 80 {
        counter = 0
        spawn_enemy()
    }

    it := hm.iterator_make(&enemies)
    for enemy, handle in hm.iterate(&it) {
        player_pos := transform.get_position(&player.trans)
        enemy_pos := transform.get_position(&enemy.trans)
        player_vec := player_pos.xy - enemy_pos.xy
        angle := linalg.atan2(player_vec.y, player_vec.x)
        transform.set_orientation(&enemy.trans, {0, 0, angle-linalg.PI/2}, true)
        x := linalg.cos(angle)*Enemy_Speed
        y := linalg.sin(angle)*Enemy_Speed
        transform.translate(&enemy.trans, {x, y, 0})

        e := enemy_pos.xy
        r: f32 = 32

        //for the player, check each corner
        player_points := [4][2]f32 {
            player_pos.xy + {-16, +16}, //top-left
            player_pos.xy + {+16, +16}, //top-right
            player_pos.xy + {-16, -16}, //bottom-left
            player_pos.xy + {+16, -16}, //bottom-right
        }
        for p in player_points {
            if (p.x - e.x)*(p.x - e.x) + (p.y - e.y)*(p.y - e.y) < r*r {
                hm.remove(&enemies, handle)
                player.hp -= 1
                break
            }
        }

        //for each bullet, just check the bullet's center point
        bit := hm.iterator_make(&bullets)
        for bullet, bhandle in hm.iterate(&bit) {
            b := transform.get_position(&bullet.trans).xy
            if (b.x - e.x)*(b.x - e.x) + (b.y - e.y)*(b.y - e.y) < r*r {
                hm.remove(&enemies, handle)
                hm.remove(&bullets, bhandle)
                player.score += 1
                break
            }
        }
    }
}

update_bullets :: proc() {
    it := hm.iterator_make(&bullets)
    for bullet, handle in hm.iterate(&it) {
        x := linalg.cos(bullet.trajectory)*Bullet_Speed
        y := linalg.sin(bullet.trajectory)*Bullet_Speed
        transform.translate(&bullet.trans, {x, y, 0})
        bullet_pos := transform.get_position(&bullet.trans)
        if bullet_pos.x > Screen_Width/2 ||
            bullet_pos.x < -Screen_Width/2 ||
            bullet_pos.y > Screen_Height/2 ||
            bullet_pos.y < -Screen_Height/2 {
                hm.remove(&bullets, handle)
            }
    }
}

tick :: proc() {
    if input.key_pressed(.Key_Escape) {
        window.close()
    }

    if input.key_pressed(.Key_F1) {
        debug_enabled = !debug_enabled
    }

    switch gamestate {
    case .Title:
        if input.mouse_pressed(.Left) {
            gamestate = .Playing
        }
    case .Paused:
        if input.key_pressed(.Key_P) {
            gamestate = .Playing
        }
    case .Playing:
        if input.key_pressed(.Key_P) {
            gamestate = .Paused
        }

        update_player()
        update_bullets()
        update_enemies()

        if player.score >= 100 {
            gamestate = .Won
        }
        if player.hp <= 0 {
            gamestate = .Died
        }
    case .Died:
    case .Won:
    }

}


draw_player :: proc(f: ^graphics.Frame, t: f64) {
    transform.smooth(&player.trans, t)
    pos := transform.get_position(&player.trans)
    for i in 0..<16 {
        trans := player.trans
        transform.set_position(&trans, {pos.x, pos.y + f32(i), f32(i)})
        model := transform.compute(&trans)
        graphics.draw_sprite(f, player_mat, model, clip_rect={f32(i)*16, 0, 16, 16})
    }
    if debug_enabled {
        graphics.ui_draw_rect({pos.x, pos.y, 32, 32}, {1, 0, 0, 0.25})
    }
}

draw_bullets :: proc(f: ^graphics.Frame, t: f64) {
    it := hm.iterator_make(&bullets)
    for bullet, handle in hm.iterate(&it) {
        graphics.draw_sprite(f, bullet_mat, transform.smooth(&bullet.trans, t))
    }
}

draw_enemies :: proc(f: ^graphics.Frame, t: f64) {
    it := hm.iterator_make(&enemies)
    for enemy, handle in hm.iterate(&it) {
        transform.smooth(&enemy.trans, t)
        pos := transform.get_position(&enemy.trans)
        for i in 0..<16 {
            trans := enemy.trans
            transform.set_position(&trans, {pos.x, pos.y + 2*f32(i), 2*f32(i)})
            model := transform.compute(&trans)
            graphics.draw_sprite(f, enemy_mat, model, clip_rect={f32(i)*16, 0, 16, 16})
        }
        if debug_enabled {
            graphics.ui_draw_rect({pos.x, pos.y, 64, 64}, {1, 0, 0, 0.25})
        }
    }
}


draw :: proc(t: f64, dt: f64) {

    f := graphics.Frame{}
    graphics.draw_camera(&f, &cam, t)

    bs := f32(Big_Font_Size)
    rs := f32(Regular_Font_Size)

    switch gamestate {
    case .Title:
        graphics.set_background_color({0.2, 0.4, 0.8})
        str1 := "BOX VS SPHERES"
        str2 := "click to start"
        graphics.ui_draw_text(str1, big_font, {0-f32(len(str1))*bs/2, 0+2*bs}, {1, 1, 1, 1})
        graphics.ui_draw_text(str2, regular_font, {0-f32(len(str2))*rs/2, 0-2*rs}, {1, 1, 1, 1})
    case .Playing:
        graphics.set_background_color({0.2, 0.3, 0.1})

        score_str := fmt.tprintf("score:  %v", player.score)
        graphics.ui_draw_text(score_str, regular_font, {-Screen_Width/2, Screen_Height/2}, {1, 1, 1, 1})
        hp_str := fmt.tprintf("health: %v", player.hp)
        graphics.ui_draw_text(hp_str, regular_font, {-Screen_Width/2, Screen_Height/2 - rs*2}, {1, 1, 1, 1})

        if debug_enabled {
            live_bullets_str := fmt.tprintf("live bullets: %d", hm.len(bullets))
            graphics.ui_draw_text(live_bullets_str, regular_font, {-Screen_Width/2, -Screen_Height/2 + rs*3}, {1, 1, 1, 1})

            live_enemies_str := fmt.tprintf("live enemies: %d", hm.len(enemies))
            graphics.ui_draw_text(live_enemies_str, regular_font, {-Screen_Width/2, -Screen_Height/2 + rs*5}, {1, 1, 1, 1})
        }

        draw_player(&f, t)
        draw_bullets(&f, t)
        draw_enemies(&f, t)
    case .Paused:
        pause_str := "(Paused)"
        graphics.ui_draw_text(pause_str, big_font, {0 - f32(len(pause_str))*bs/2, 0+2*bs}, {1, 1, 1, 1})
    case .Won:
        graphics.set_background_color({0.7, 0.6, 0.2})
        win_str := "You Won!"
        score_str := fmt.tprint("final score: ", player.score)
        graphics.ui_draw_text(win_str, big_font, {0 - f32(len(win_str))*bs/2, 0+2*bs}, {1, 1, 1, 1})
        graphics.ui_draw_text(score_str, regular_font, {0 - f32(len(score_str))*rs/2, 0-2*rs}, {1, 1, 1, 1})
    case .Died:
        die_str := "You Fucking Died!"
        graphics.set_background_color({0.2, 0.2, 0.2})
        graphics.ui_draw_text(die_str, big_font, {0 - f32(len(die_str))*bs/2, 0+2*bs}, {1.0, 0.0, 0.0, 1})
        score_str := fmt.tprint("final score: ", player.score)
        graphics.ui_draw_text(score_str, regular_font, {0 - f32(len(score_str))*rs/2, 0-2*rs}, {1, 1, 1, 1})
    }

    graphics.render_frame(f)

}

kill :: proc() {
    hm.dynamic_destroy(&enemies)
    hm.dynamic_destroy(&bullets)
    graphics.delete_font(big_font)
    graphics.delete_font(regular_font)
    graphics.delete_camera(cam)
}

main :: proc() {
    engine.boot(init, tick, draw, kill)
}
