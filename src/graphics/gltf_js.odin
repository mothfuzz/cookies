#+build js

package graphics

import "core:fmt"

read_from_disk :: proc(path: cstring) -> []u8 {
    fmt.eprintln("loading from disk not supported on web")
    return nil
}
