package graphics


white_tex: Texture
black_tex: Texture
trans_tex: Texture
normal_tex: Texture
pbr_tex: Texture
quad_mesh: Mesh
cube_mesh: Mesh

init_defaults :: proc() {
    white_tex = make_texture_2D({0xffffffff}, {1, 1})
    black_tex = make_texture_2D({0xff000000}, {1, 1})
    trans_tex = make_texture_2D({0x00000000}, {1, 1})
    normal_tex = make_texture_2D({0xffff8080}, {1, 1}, true)
    pbr_tex = make_texture_2D({0xff00ffff}, {1, 1}, true)
    quad_mesh = make_mesh([]Vertex{
        {position={-0.5, +0.5, 0.0}, texcoord={0.0, 0.0}, color={1, 1, 1, 1}},
        {position={+0.5, +0.5, 0.0}, texcoord={1.0, 0.0}, color={1, 1, 1, 1}},
        {position={+0.5, -0.5, 0.0}, texcoord={1.0, 1.0}, color={1, 1, 1, 1}},
        {position={-0.5, -0.5, 0.0}, texcoord={0.0, 1.0}, color={1, 1, 1, 1}},
    }, {2, 1, 0, 3, 2, 0})

    //need all 24 vertices because we want individual UVs per face... ugh
    cube_mesh = make_mesh([]Vertex{
        //+z
        {position={-0.5, +0.5, +0.5}, texcoord={0, 0}, color={1, 1, 1, 1}},
        {position={+0.5, +0.5, +0.5}, texcoord={1, 0}, color={1, 1, 1, 1}},
        {position={+0.5, -0.5, +0.5}, texcoord={1, 1}, color={1, 1, 1, 1}},
        {position={-0.5, -0.5, +0.5}, texcoord={0, 1}, color={1, 1, 1, 1}},
        //-z
        {position={+0.5, +0.5, -0.5}, texcoord={0, 0}, color={1, 1, 1, 1}},
        {position={-0.5, +0.5, -0.5}, texcoord={1, 0}, color={1, 1, 1, 1}},
        {position={-0.5, -0.5, -0.5}, texcoord={1, 1}, color={1, 1, 1, 1}},
        {position={+0.5, -0.5, -0.5}, texcoord={0, 1}, color={1, 1, 1, 1}},
        //+x
        {position={+0.5, +0.5, +0.5}, texcoord={0, 0}, color={1, 1, 1, 1}},
        {position={+0.5, +0.5, -0.5}, texcoord={1, 0}, color={1, 1, 1, 1}},
        {position={+0.5, -0.5, -0.5}, texcoord={1, 1}, color={1, 1, 1, 1}},
        {position={+0.5, -0.5, +0.5}, texcoord={0, 1}, color={1, 1, 1, 1}},
        //-x
        {position={-0.5, +0.5, -0.5}, texcoord={0, 0}, color={1, 1, 1, 1}},
        {position={-0.5, +0.5, +0.5}, texcoord={1, 0}, color={1, 1, 1, 1}},
        {position={-0.5, -0.5, +0.5}, texcoord={1, 1}, color={1, 1, 1, 1}},
        {position={-0.5, -0.5, -0.5}, texcoord={0, 1}, color={1, 1, 1, 1}},
        //+y
        {position={-0.5, +0.5, -0.5}, texcoord={0, 0}, color={1, 1, 1, 1}},
        {position={+0.5, +0.5, -0.5}, texcoord={1, 0}, color={1, 1, 1, 1}},
        {position={+0.5, +0.5, +0.5}, texcoord={1, 1}, color={1, 1, 1, 1}},
        {position={-0.5, +0.5, +0.5}, texcoord={0, 1}, color={1, 1, 1, 1}},
        //-y
        {position={-0.5, -0.5, +0.5}, texcoord={0, 0}, color={1, 1, 1, 1}},
        {position={+0.5, -0.5, +0.5}, texcoord={1, 0}, color={1, 1, 1, 1}},
        {position={+0.5, -0.5, -0.5}, texcoord={1, 1}, color={1, 1, 1, 1}},
        {position={-0.5, -0.5, -0.5}, texcoord={0, 1}, color={1, 1, 1, 1}},
    }, {
        2, 1, 0,  3, 2, 0,
        6, 5, 4,  7, 6, 4,
        10, 9, 8,  11, 10, 8,
        14, 13, 12,  15, 14, 12,
        18, 17, 16,  19, 18, 16,
        22, 21, 20,  23, 22, 20,
    })
}

delete_defaults :: proc() {
    delete_texture(white_tex)
    delete_texture(black_tex)
    delete_texture(trans_tex)
    delete_texture(normal_tex)
    delete_texture(pbr_tex)
    delete_mesh(quad_mesh)
    delete_mesh(cube_mesh)
}
