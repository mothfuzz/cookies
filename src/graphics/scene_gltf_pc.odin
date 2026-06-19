#+build !js

package graphics

import "core:path/filepath"
import "core:strings"

resolve_image_path :: proc(gltf_path: cstring, uri: cstring) -> (path: cstring){
    base_dir := filepath.dir(string(gltf_path))
    path = uri
    if base_dir != "" {
        full_path := strings.concatenate({base_dir, "/", string(uri)}, context.temp_allocator)
        path = strings.clone_to_cstring(full_path, context.temp_allocator)
    }
    return
}
