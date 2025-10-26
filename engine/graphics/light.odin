package graphics

Point_Light :: struct {}
Directional_Light :: struct {}
Spot_Light :: struct {}

Light :: union {
    Point_Light,
    Directional_Light,
    Spot_Light,
}
