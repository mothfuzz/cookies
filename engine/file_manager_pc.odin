#+build !js

package engine

import "core:fmt"
import "core:os"

read_from_disk :: proc(path: cstring) -> []u8 {
    data, err := os.read_entire_file(string(path), context.allocator)
    if err != nil {
        fmt.eprintln(err)
        fmt.eprintln("failed to read file:", path)
        return nil
    }
    return data
}
