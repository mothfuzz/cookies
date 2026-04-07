#+build js
package window

import "vendor:wgpu"

get_wgpu_surface :: proc(instance: wgpu.Instance) -> wgpu.Surface {
    return wgpu.InstanceCreateSurface(instance, &wgpu.SurfaceDescriptor{
        nextInChain = &wgpu.SurfaceSourceCanvasHTMLSelector{
            sType = .SurfaceSourceCanvasHTMLSelector,
            selector = "#canvas",
        },
    })
}
