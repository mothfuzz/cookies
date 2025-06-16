package graphics


white_tex: Texture
black_tex: Texture
trans_tex: Texture
normal_tex: Texture
quad_mesh: Mesh

init_defaults :: proc() {
    white_tex = make_texture_2D({0xffffffff}, {1, 1})
    black_tex = make_texture_2D({0xff000000}, {1, 1})
    trans_tex = make_texture_2D({0x00000000}, {1, 1})
    normal_tex = make_texture_2D({0xffff8080}, {1, 1})
    quad_mesh = make_mesh([]Vertex{
        {position={-0.5, +0.5, 0.0}, texcoord={0.0, 0.0}, color={1, 1, 1, 1}},
        {position={+0.5, +0.5, 0.0}, texcoord={1.0, 0.0}, color={1, 1, 1, 1}},
        {position={+0.5, -0.5, 0.0}, texcoord={1.0, 1.0}, color={1, 1, 1, 1}},
        {position={-0.5, -0.5, 0.0}, texcoord={0.0, 1.0}, color={1, 1, 1, 1}},
    }, {0, 1, 2, 0, 2, 3})
}

delete_defaults :: proc() {
    delete_texture(white_tex)
    delete_texture(black_tex)
    delete_texture(trans_tex)
    delete_texture(normal_tex)
    delete_mesh(quad_mesh)
}
