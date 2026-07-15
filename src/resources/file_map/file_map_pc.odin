#+build !js

package file_map

import "core:log"
import "core:os"

read_from_disk :: proc(path: cstring) -> []u8 {
    data, err := os.read_entire_file(string(path), context.allocator)
    if err != nil {
        log.error("failed to read file:", path)
        log.error(err)
        return nil
    }
    return data
}
