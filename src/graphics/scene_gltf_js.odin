#+build js

package graphics

resolve_image_path :: proc(gltf_path: cstring, uri: cstring) -> cstring {
    return uri //:C
    //get used to using 'preload' if you want your game to work on web
}
