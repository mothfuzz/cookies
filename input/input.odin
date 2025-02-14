package input

import "core:fmt"


Scancode :: enum {
    Key_None,
    Key_0, Key_1, Key_2, Key_3, Key_4, Key_5, Key_6, Key_7, Key_8, Key_9,
    Key_A, Key_B, Key_C, Key_D, Key_E, Key_F, Key_G, Key_H, Key_I, Key_J,
    Key_K, Key_L, Key_M, Key_N, Key_O, Key_P, Key_Q, Key_R, Key_S, Key_T,
    Key_U, Key_V, Key_W, Key_X, Key_Y, Key_Z, Key_Return, Key_Escape, Key_Backspace, Key_Tab, Key_Space,
    Key_LeftShift, Key_LeftCtrl, Key_LeftAlt, Key_RightShift, Key_RightCtrl, Key_RightAlt,
    Key_F1, Key_F2, Key_F3, Key_F4, Key_F5, Key_F6, Key_F7, Key_F8,
    Key_F9, Key_F10, Key_F11, Key_F12,
}
keys_current_frame: [Scancode]b8 = {}
keys_previous_frame: [Scancode]b8 = {}

MouseButton :: enum {
    Left, Middle, Right
}

mouse_buttons_current_frame: [MouseButton]b8 = {}
mouse_buttons_previous_frame: [MouseButton]b8 = {}
mouse_position: [2]i32 = {} //relative to center of window, y-negative.

key_down :: proc(key: Scancode) -> bool {
    return bool(keys_current_frame[key])
}
key_up :: proc(key: Scancode) -> bool {
    return bool(!keys_current_frame[key])
}
key_pressed :: proc(key: Scancode) -> bool {
    return bool(keys_current_frame[key] && !keys_previous_frame[key])
}
key_released :: proc(key: Scancode) -> bool {
    return bool(keys_previous_frame[key] && !keys_current_frame[key])
}

mouse_down :: proc(button: MouseButton) -> bool {
    return bool(mouse_buttons_current_frame[button])
}
mouse_up :: proc(button: MouseButton) -> bool {
    return bool(!mouse_buttons_current_frame[button])
}
mouse_pressed :: proc(button: MouseButton) -> bool {
    return bool(mouse_buttons_current_frame[button] && !mouse_buttons_previous_frame[button])
}
mouse_released :: proc(button: MouseButton) -> bool {
    return bool(mouse_buttons_previous_frame[button] && !mouse_buttons_current_frame[button])
}
