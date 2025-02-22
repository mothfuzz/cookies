package graphics

import "core:fmt"

init :: proc() {

}

resize :: proc(width: uint, height: uint) {

}

//draw_mesh, draw_sprite, draw_ui, draw_lines, draw_line_strip, draw_line_loop
//all graphics commands take a transform and will interpolate between the transform's old values and new values.
//we can do this by passing transform via a pointer, and keeping track of how many ticks have passed
//in the render loop we can check if it passes a threshold and say "the value we have is the old value now"
//and store it in the transform itself
//texture subdivides will not interpolate (obviously)
draw_mesh :: proc() {
    fmt.println("hahehe")
}
