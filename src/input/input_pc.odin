#+build !js

package input

import "vendor:sdl3"
import "core:fmt"

sdl2key :: proc(e: sdl3.Event) -> Scancode {
    #partial switch e.key.scancode {
    case ._0: return .Key_0
    case ._1: return .Key_1
    case ._2: return .Key_2
    case ._3: return .Key_3
    case ._4: return .Key_4
    case ._5: return .Key_5
    case ._6: return .Key_6
    case ._7: return .Key_7
    case ._8: return .Key_8
    case ._9: return .Key_9
    case .A: return .Key_A
    case .B: return .Key_B
    case .C: return .Key_C
    case .D: return .Key_D
    case .E: return .Key_E
    case .F: return .Key_F
    case .G: return .Key_G
    case .H: return .Key_H
    case .I: return .Key_I
    case .J: return .Key_J
    case .K: return .Key_K
    case .L: return .Key_L
    case .M: return .Key_M
    case .N: return .Key_N
    case .O: return .Key_O
    case .P: return .Key_P
    case .Q: return .Key_Q
    case .R: return .Key_R
    case .S: return .Key_S
    case .T: return .Key_T
    case .U: return .Key_U
    case .V: return .Key_V
    case .W: return .Key_W
    case .X: return .Key_X
    case .Y: return .Key_Y
    case .Z: return .Key_Z
    case .RETURN: return .Key_Return
    case .ESCAPE: return .Key_Escape
    case .BACKSPACE: return .Key_Backspace
    case .TAB: return .Key_Tab
    case .SPACE: return .Key_Space
    case .LSHIFT: return .Key_LeftShift
    case .LCTRL: return .Key_LeftCtrl
    case .LALT: return .Key_LeftAlt
    case .RSHIFT: return .Key_RightShift
    case .RCTRL: return .Key_RightCtrl
    case .RALT: return .Key_RightAlt
    case .F1: return .Key_F1
    case .F2: return .Key_F2
    case .F3: return .Key_F3
    case .F4: return .Key_F4
    case .F5: return .Key_F5
    case .F6: return .Key_F6
    case .F7: return .Key_F7
    case .F8: return .Key_F8
    case .F9: return .Key_F9
    case .F10: return .Key_F10
    case .F11: return .Key_F11
    case .F12: return .Key_F12
    case .LEFT: return .Key_Left
    case .RIGHT: return .Key_Right
    case .UP: return .Key_Up
    case .DOWN: return .Key_Down
    }
    return .Key_None
}
