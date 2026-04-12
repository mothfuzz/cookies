package input

Scancode :: enum {
    Key_None,
    Key_0, Key_1, Key_2, Key_3, Key_4, Key_5, Key_6, Key_7, Key_8, Key_9,
    Key_A, Key_B, Key_C, Key_D, Key_E, Key_F, Key_G, Key_H, Key_I, Key_J,
    Key_K, Key_L, Key_M, Key_N, Key_O, Key_P, Key_Q, Key_R, Key_S, Key_T,
    Key_U, Key_V, Key_W, Key_X, Key_Y, Key_Z, Key_Return, Key_Escape, Key_Backspace, Key_Tab, Key_Space,
    Key_LeftShift, Key_LeftCtrl, Key_LeftAlt, Key_RightShift, Key_RightCtrl, Key_RightAlt,
    Key_F1, Key_F2, Key_F3, Key_F4, Key_F5, Key_F6, Key_F7, Key_F8,
    Key_F9, Key_F10, Key_F11, Key_F12,
    Key_Left, Key_Right, Key_Up, Key_Down,
}
keys_current: [Scancode]b8 = {}
keys_pressed: [Scancode]b8 = {}
keys_released: [Scancode]b8 = {}

Mouse_Button :: enum {
    Left, Middle, Right,
}

mouse_buttons_current: [Mouse_Button]b8 = {}
mouse_buttons_pressed: [Mouse_Button]b8 = {}
mouse_buttons_released: [Mouse_Button]b8 = {}
current_mouse_position: [2]i32 = {} //relative to center of window, y-negative.

update :: proc() {
    for &key in keys_pressed {
        key = false
    }
    for &key in keys_released {
        key = false
    }
    for &button in mouse_buttons_pressed {
        button = false
    }
    for &button in mouse_buttons_released {
        button = false
    }
}

@(export)
key_down :: proc(key: Scancode) -> bool {
    return bool(keys_current[key])
}
@(export)
key_up :: proc(key: Scancode) -> bool {
    return bool(!keys_current[key])
}
@(export)
key_pressed :: proc(key: Scancode) -> bool {
    //return bool(keys_current_frame[key] && !keys_previous_frame[key])
    return bool(keys_pressed[key])
}
@(export)
key_released :: proc(key: Scancode) -> bool {
    return bool(keys_released[key])
}

@(export)
mouse_down :: proc(button: Mouse_Button) -> bool {
    return bool(mouse_buttons_current[button])
}
@(export)
mouse_up :: proc(button: Mouse_Button) -> bool {
    return bool(!mouse_buttons_current[button])
}
@(export)
mouse_pressed :: proc(button: Mouse_Button) -> bool {
    return bool(mouse_buttons_pressed[button])
}
@(export)
mouse_released :: proc(button: Mouse_Button) -> bool {
    return bool(mouse_buttons_released[button])
}
@(export)
mouse_position :: proc() -> [2]i32 {
    return current_mouse_position
}
