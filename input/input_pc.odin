#+build !js

package input

import "../window"
import "vendor:sdl2"
import "core:fmt"

init :: proc() {
    //...
}

update :: proc() {
    for pressed, key in keys_current_frame {
        keys_previous_frame[key] = pressed
    }
    numkeys: i32 = 0
    keys := sdl2.GetKeyboardState(&numkeys)
    keys_current_frame[.Key_0] = keys[sdl2.SCANCODE_0] == 1
    keys_current_frame[.Key_1] = keys[sdl2.SCANCODE_1] == 1
    keys_current_frame[.Key_2] = keys[sdl2.SCANCODE_2] == 1
    keys_current_frame[.Key_3] = keys[sdl2.SCANCODE_3] == 1
    keys_current_frame[.Key_4] = keys[sdl2.SCANCODE_4] == 1
    keys_current_frame[.Key_5] = keys[sdl2.SCANCODE_5] == 1
    keys_current_frame[.Key_6] = keys[sdl2.SCANCODE_6] == 1
    keys_current_frame[.Key_7] = keys[sdl2.SCANCODE_7] == 1
    keys_current_frame[.Key_8] = keys[sdl2.SCANCODE_8] == 1
    keys_current_frame[.Key_9] = keys[sdl2.SCANCODE_9] == 1
    keys_current_frame[.Key_A] = keys[sdl2.SCANCODE_A] == 1
    keys_current_frame[.Key_B] = keys[sdl2.SCANCODE_B] == 1
    keys_current_frame[.Key_C] = keys[sdl2.SCANCODE_C] == 1
    keys_current_frame[.Key_D] = keys[sdl2.SCANCODE_D] == 1
    keys_current_frame[.Key_E] = keys[sdl2.SCANCODE_E] == 1
    keys_current_frame[.Key_F] = keys[sdl2.SCANCODE_F] == 1
    keys_current_frame[.Key_G] = keys[sdl2.SCANCODE_G] == 1
    keys_current_frame[.Key_H] = keys[sdl2.SCANCODE_H] == 1
    keys_current_frame[.Key_I] = keys[sdl2.SCANCODE_I] == 1
    keys_current_frame[.Key_J] = keys[sdl2.SCANCODE_J] == 1
    keys_current_frame[.Key_K] = keys[sdl2.SCANCODE_K] == 1
    keys_current_frame[.Key_L] = keys[sdl2.SCANCODE_L] == 1
    keys_current_frame[.Key_M] = keys[sdl2.SCANCODE_M] == 1
    keys_current_frame[.Key_N] = keys[sdl2.SCANCODE_N] == 1
    keys_current_frame[.Key_O] = keys[sdl2.SCANCODE_O] == 1
    keys_current_frame[.Key_P] = keys[sdl2.SCANCODE_P] == 1
    keys_current_frame[.Key_Q] = keys[sdl2.SCANCODE_Q] == 1
    keys_current_frame[.Key_R] = keys[sdl2.SCANCODE_R] == 1
    keys_current_frame[.Key_S] = keys[sdl2.SCANCODE_S] == 1
    keys_current_frame[.Key_T] = keys[sdl2.SCANCODE_T] == 1
    keys_current_frame[.Key_U] = keys[sdl2.SCANCODE_U] == 1
    keys_current_frame[.Key_V] = keys[sdl2.SCANCODE_V] == 1
    keys_current_frame[.Key_W] = keys[sdl2.SCANCODE_W] == 1
    keys_current_frame[.Key_X] = keys[sdl2.SCANCODE_X] == 1
    keys_current_frame[.Key_Y] = keys[sdl2.SCANCODE_Y] == 1
    keys_current_frame[.Key_Z] = keys[sdl2.SCANCODE_Z] == 1
    keys_current_frame[.Key_Return] = keys[sdl2.SCANCODE_RETURN] == 1
    keys_current_frame[.Key_Escape] = keys[sdl2.SCANCODE_ESCAPE] == 1
    keys_current_frame[.Key_Backspace] = keys[sdl2.SCANCODE_BACKSPACE] == 1
    keys_current_frame[.Key_Tab] = keys[sdl2.SCANCODE_TAB] == 1
    keys_current_frame[.Key_Space] = keys[sdl2.SCANCODE_SPACE] == 1
    keys_current_frame[.Key_LeftShift] = keys[sdl2.SCANCODE_LSHIFT] == 1
    keys_current_frame[.Key_LeftCtrl] = keys[sdl2.SCANCODE_LCTRL] == 1
    keys_current_frame[.Key_LeftAlt] = keys[sdl2.SCANCODE_LALT] == 1
    keys_current_frame[.Key_RightShift] = keys[sdl2.SCANCODE_RSHIFT] == 1
    keys_current_frame[.Key_RightCtrl] = keys[sdl2.SCANCODE_RCTRL] == 1
    keys_current_frame[.Key_RightAlt] = keys[sdl2.SCANCODE_RALT] == 1
    keys_current_frame[.Key_F1] = keys[sdl2.SCANCODE_F1] == 1
    keys_current_frame[.Key_F2] = keys[sdl2.SCANCODE_F2] == 1
    keys_current_frame[.Key_F3] = keys[sdl2.SCANCODE_F3] == 1
    keys_current_frame[.Key_F4] = keys[sdl2.SCANCODE_F4] == 1
    keys_current_frame[.Key_F5] = keys[sdl2.SCANCODE_F5] == 1
    keys_current_frame[.Key_F6] = keys[sdl2.SCANCODE_F6] == 1
    keys_current_frame[.Key_F7] = keys[sdl2.SCANCODE_F7] == 1
    keys_current_frame[.Key_F8] = keys[sdl2.SCANCODE_F8] == 1
    keys_current_frame[.Key_F9] = keys[sdl2.SCANCODE_F9] == 1
    keys_current_frame[.Key_F10] = keys[sdl2.SCANCODE_F10] == 1
    keys_current_frame[.Key_F11] = keys[sdl2.SCANCODE_F11] == 1
    keys_current_frame[.Key_F12] = keys[sdl2.SCANCODE_F12] == 1

    for pressed, button in mouse_buttons_current_frame {
        mouse_buttons_previous_frame[button] = pressed
    }
    pos: [2]i32
    mouse := sdl2.GetMouseState(&pos.x, &pos.y)
    mouse_buttons_current_frame[.Left] = mouse & sdl2.BUTTON_LMASK != 0
    mouse_buttons_current_frame[.Middle] = mouse & sdl2.BUTTON_MMASK != 0
    mouse_buttons_current_frame[.Right] = mouse & sdl2.BUTTON_RMASK != 0
    rect := window.get_size()
    mouse_position.x = pos.x - i32(rect.x)/2
    mouse_position.y = pos.y - i32(rect.y)/2
    //fmt.println(mouse_position)
}
