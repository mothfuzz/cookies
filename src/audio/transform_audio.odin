package audio

import "cookies:transform"

set_sound_transform :: proc(playing_sound: ^Playing_Sound, trans: transform.Transform) {
    set_sound_position(playing_sound, transform.world_position(trans))
}

set_listener_transform :: proc(trans: transform.Transform) {
    p := transform.world_position(trans)
    set_listener_position(p)
    f, r, u := transform.world_orientation(trans)
    set_listener_orientation(f, u)
}
