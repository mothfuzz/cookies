#+build !js

package input

import "vendor:sdl2"
import "core:fmt"

sdl2key :: proc(e: sdl2.Event) -> Scancode {
    #partial switch e.key.keysym.scancode {
    case sdl2.SCANCODE_0: return .Key_0
    case sdl2.SCANCODE_1: return .Key_1
    case sdl2.SCANCODE_2: return .Key_2
    case sdl2.SCANCODE_3: return .Key_3
    case sdl2.SCANCODE_4: return .Key_4
    case sdl2.SCANCODE_5: return .Key_5
    case sdl2.SCANCODE_6: return .Key_6
    case sdl2.SCANCODE_7: return .Key_7
    case sdl2.SCANCODE_8: return .Key_8
    case sdl2.SCANCODE_9: return .Key_9
    case sdl2.SCANCODE_A: return .Key_A
    case sdl2.SCANCODE_B: return .Key_B
    case sdl2.SCANCODE_C: return .Key_C
    case sdl2.SCANCODE_D: return .Key_D
    case sdl2.SCANCODE_E: return .Key_E
    case sdl2.SCANCODE_F: return .Key_F
    case sdl2.SCANCODE_G: return .Key_G
    case sdl2.SCANCODE_H: return .Key_H
    case sdl2.SCANCODE_I: return .Key_I
    case sdl2.SCANCODE_J: return .Key_J
    case sdl2.SCANCODE_K: return .Key_K
    case sdl2.SCANCODE_L: return .Key_L
    case sdl2.SCANCODE_M: return .Key_M
    case sdl2.SCANCODE_N: return .Key_N
    case sdl2.SCANCODE_O: return .Key_O
    case sdl2.SCANCODE_P: return .Key_P
    case sdl2.SCANCODE_Q: return .Key_Q
    case sdl2.SCANCODE_R: return .Key_R
    case sdl2.SCANCODE_S: return .Key_S
    case sdl2.SCANCODE_T: return .Key_T
    case sdl2.SCANCODE_U: return .Key_U
    case sdl2.SCANCODE_V: return .Key_V
    case sdl2.SCANCODE_W: return .Key_W
    case sdl2.SCANCODE_X: return .Key_X
    case sdl2.SCANCODE_Y: return .Key_Y
    case sdl2.SCANCODE_Z: return .Key_Z
    case sdl2.SCANCODE_RETURN: return .Key_Return
    case sdl2.SCANCODE_ESCAPE: return .Key_Escape
    case sdl2.SCANCODE_BACKSPACE: return .Key_Backspace
    case sdl2.SCANCODE_TAB: return .Key_Tab
    case sdl2.SCANCODE_SPACE: return .Key_Space
    case sdl2.SCANCODE_LSHIFT: return .Key_LeftShift
    case sdl2.SCANCODE_LCTRL: return .Key_LeftCtrl
    case sdl2.SCANCODE_LALT: return .Key_LeftAlt
    case sdl2.SCANCODE_RSHIFT: return .Key_RightShift
    case sdl2.SCANCODE_RCTRL: return .Key_RightCtrl
    case sdl2.SCANCODE_RALT: return .Key_RightAlt
    case sdl2.SCANCODE_F1: return .Key_F1
    case sdl2.SCANCODE_F2: return .Key_F2
    case sdl2.SCANCODE_F3: return .Key_F3
    case sdl2.SCANCODE_F4: return .Key_F4
    case sdl2.SCANCODE_F5: return .Key_F5
    case sdl2.SCANCODE_F6: return .Key_F6
    case sdl2.SCANCODE_F7: return .Key_F7
    case sdl2.SCANCODE_F8: return .Key_F8
    case sdl2.SCANCODE_F9: return .Key_F9
    case sdl2.SCANCODE_F10: return .Key_F10
    case sdl2.SCANCODE_F11: return .Key_F11
    case sdl2.SCANCODE_F12: return .Key_F12
    }
    return .Key_None
}
