#+build !js
package window

import "vendor:wgpu"
import "vendor:wgpu/sdl2glue"

get_wgpu_surface :: proc(instance: wgpu.Instance) -> wgpu.Surface {
    return sdl2glue.GetSurface(instance, window)
}
