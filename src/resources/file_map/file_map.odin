package file_map

import "core:fmt"

Loaded_File :: struct {
    data: []u8,
    preloaded: bool,
}

loaded_files: map[cstring]Loaded_File
loaded_paths: map[rawptr]cstring

unload_files :: proc() {
    for path, file in loaded_files {
        delete(file.data)
    }
    delete(loaded_files)
    delete(loaded_paths)
}

read :: proc(path: cstring) -> []u8 {
    if path in loaded_files {
        return loaded_files[path].data
    }
    data := read_from_disk(path)
    if data == nil {
        fmt.eprintln("failed to read file:", path)
        return nil
    }
    loaded_files[path] = {data, false}
    loaded_paths[raw_data(data)] = path
    return data
}

preload :: proc(path: cstring, data: []u8) {
    loaded_files[path] = {data, true}
    loaded_paths[raw_data(data)] = path
}

release_by_path :: proc(path: cstring) {
    file := loaded_files[path]
    if !file.preloaded {
        data := raw_data(file.data)
        delete_key(&loaded_files, loaded_paths[data])
        delete_key(&loaded_paths, data)
        delete(file.data)
    }
}
release_by_data :: proc(data: rawptr) {
    release_by_path(loaded_paths[data])
}
release :: proc{release_by_path, release_by_data}
