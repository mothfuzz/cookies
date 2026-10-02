package spatial2

import "cookies:transform"

insert_transform :: proc(s: ^Spatial($Entity, $Accel), e: Entity, shape: Shape, trans: transform.Transform) {
    trans := transform.world(trans)
    insert_matrix(s, e, shape, trans)
}

update_transform :: proc(s: ^Spatial($Entity, $Accel), e: Entity, trans: transform.Transform) {
    trans := transform.world(trans)
    update_matrix(s, e, trans) 
}
