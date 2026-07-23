package graphics

/* TODO:

probe := make_environment_probe(position, extents)
draw_environment_probe(probe, transform, layer_mask)

have global environment fallback to avoid doing any nearest-search
what will be used in order of priority:
set_global_environment_probe(probe)
set_skybox(skybox)
set_Background_color(...)

for mips:
base texture (6x or just 1 scratch) is multisampled, but *resolve* is the actual cubemap faces.
mipmaps are already allocated when creating the texture, so resolution will be correct in all the downscaling subpasses.

for rendering:
we should use the existing render_target stuff.
We want full OIT composite & multisampling & everything - the *resolve* will again just be the cubemap faces.
Cubemap itself isn't multisampled.
if a naive walk is proving not performant, we can use spatial.grid, but is there another way?


NOTE:
point lights will have to use separate machinery from environment probes. Shadow pass has different rendering requirements than environment probe pass (no fill/OIT/composite/etc)
Same pipeline as spot shadows, just render to 6 faces instead of 1...
directional lights will be the same thing, render to num_cascades*num_cameras textures.

*/
