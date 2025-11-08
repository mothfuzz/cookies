package spatial

import "core:math/linalg"

Ray_Hit :: struct {
    point: [3]f32,
    normal: [3]f32,
    distance: f32,
    //some type of reference to the object maybe?
}

