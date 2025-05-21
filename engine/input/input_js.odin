#+build js

package input

import "../window"
import "core:sys/wasm/js"
import "core:fmt"

js2key :: proc(e: js.Event) -> Scancode {
    //will need to find some way to get the actual key from this. e.g. for UI purposes.
    //we'll cross that bridge when we even *have* UI
    switch e.key.code {
    case "Digit0": return .Key_0
    case "Digit1": return .Key_1
    case "Digit2": return .Key_2
    case "Digit3": return .Key_3
    case "Digit4": return .Key_4
    case "Digit5": return .Key_5
    case "Digit6": return .Key_6
    case "Digit7": return .Key_7
    case "Digit8": return .Key_8
    case "Digit9": return .Key_9
    case "KeyA": return .Key_A
    case "KeyB": return .Key_B
    case "KeyC": return .Key_C
    case "KeyD": return .Key_D
    case "KeyE": return .Key_E
    case "KeyF": return .Key_F
    case "KeyG": return .Key_G
    case "KeyH": return .Key_H
    case "KeyI": return .Key_I
    case "KeyJ": return .Key_J
    case "KeyK": return .Key_K
    case "KeyL": return .Key_L
    case "KeyM": return .Key_M
    case "KeyN": return .Key_N
    case "KeyO": return .Key_O
    case "KeyP": return .Key_P
    case "KeyQ": return .Key_Q
    case "KeyR": return .Key_R
    case "KeyS": return .Key_S
    case "KeyT": return .Key_T
    case "KeyU": return .Key_U
    case "KeyV": return .Key_V
    case "KeyW": return .Key_W
    case "KeyX": return .Key_X
    case "KeyY": return .Key_Y
    case "KeyZ": return .Key_Z
    case "Enter": return .Key_Return
    case "Escape": return .Key_Escape
    case "Backspace": return .Key_Backspace
    case "Tab": return .Key_Tab
    case "Space": return .Key_Space
    case "ShiftLeft": return .Key_LeftShift
    case "ControlLeft": return .Key_LeftCtrl
    case "AltLeft": return .Key_LeftAlt
    case "ShiftRight": return .Key_RightShift
    case "ControlRight": return .Key_RightCtrl
    case "AltRight": return .Key_RightAlt
    case "F1": return .Key_F1
    case "F2": return .Key_F2
    case "F3": return .Key_F3
    case "F4": return .Key_F4
    case "F5": return .Key_F5
    case "F6": return .Key_F6
    case "F7": return .Key_F7
    case "F8": return .Key_F8
    case "F9": return .Key_F9
    case "F10": return .Key_F10
    case "F11": return .Key_F11
    case "F12": return .Key_F12
    }
    return .Key_None
}

init :: proc() {
}
