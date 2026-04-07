#+build !js
package window

import "vendor:wgpu"
import "vendor:wgpu/sdl3glue"

get_wgpu_surface :: proc(instance: wgpu.Instance) -> wgpu.Surface {
    return sdl3glue.GetSurface(instance, window)
}
