package graphics

import "base:intrinsics"

Layer_Mask :: distinct u64

layers_from_bit_set :: proc(set: bit_set[$E; $U]) -> Layer_Mask {
    U :: intrinsics.type_bit_set_underlying_type(type_of(set))
    return Layer_Mask(transmute(U)(set))
}

layer_from_enum :: proc(value: $E) -> Layer_Mask {
    s: bit_set[type_of(value)] = {value}
    return layers_from_bit_set(s)
}

layers_from_enum :: proc(values: ..$E) -> Layer_Mask {
    s: bit_set[type_of(values[0])]
    for value in values {
        s += value
    }
    return layers_from_bit_set(s)
}

layers :: proc{layers_from_bit_set, layer_from_enum, layers_from_enum}

All_Layers :: Layer_Mask(~u64(0))

//this is way less code than I thought it would be.
