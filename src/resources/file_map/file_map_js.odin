#+build js

package file_map

import "core:log"

read_from_disk :: proc(path: cstring) -> []u8 {
    log.error("loading from disk not supported on web")
    return nil
}
