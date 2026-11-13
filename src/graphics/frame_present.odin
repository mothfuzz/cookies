package graphics

import "vendor:wgpu"

CAPTURE_BOUNCES :: 1

render_shadow_pass :: proc(command_encoder: wgpu.CommandEncoder, f: Render_Frame, p: Shadow_Pass) {
    // TODO
}

render_main_pass :: proc(command_encoder: wgpu.CommandEncoder, f: Render_Frame, p: Main_Pass) {
    /* TODO
    need to execute a clear pass first
    then for view in views:
        fill if bg_bind_group present and first pass
        resolve pipeline based on keys we have now, rebind if changed, skip if nil
        bind mesh/material if changed
        submit draw calls on CPU, drawIndirect once we move to GPU
        probably check if p.view_count == 0 or something
    lastly oit_composite if oit_composite_bind_group present
    */
}

render_view :: proc(command_encoder: wgpu.CommandEncoder) {
    // helper proc once the above two procs actually have a body
}

resolve_capture :: proc(command_encoder: wgpu.CommandEncoder, p: Capture_Pass) {
    if p.copy_info != {} {
        src, dst, ext := **p.copy_info
        wgpu.CommandEncoderCopyTextureToTexture(command_encoder, &src, &dst, &ext)
    }
    if p.mips != nil {
        render_mips(command_encoder, p.mips)
    }
}
