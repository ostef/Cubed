NoiseParams :: struct
{
    scale : float;
    octaves : s32;
    persistance : float;
    lacunarity : float;
    max_amplitude := 1.0;
}

Perlin_Fractal_Max_Octaves :: 10;
Perlin_Fractal_Min_Amplitude :: 0.00001;

Perlin_Permutation_Table : [512]s32 : .[
    151,160,137,91,90,15,
    131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,142,8,99,37,240,21,10,23,
    190, 6,148,247,120,234,75,0,26,197,62,94,252,219,203,117,35,11,32,57,177,33,
    88,237,149,56,87,174,20,125,136,171,168, 68,175,74,165,71,134,139,48,27,166,
    77,146,158,231,83,111,229,122,60,211,133,230,220,105,92,41,55,46,245,40,244,
    102,143,54, 65,25,63,161, 1,216,80,73,209,76,132,187,208, 89,18,169,200,196,
    135,130,116,188,159,86,164,100,109,198,173,186, 3,64,52,217,226,250,124,123,
    5,202,38,147,118,126,255,82,85,212,207,206,59,227,47,16,58,17,182,189,28,42,
    223,183,170,213,119,248,152, 2,44,154,163, 70,221,153,101,155,167, 43,172,9,
    129,22,39,253, 19,98,108,110,79,113,224,232,178,185, 112,104,218,246,97,228,
    251,34,242,193,238,210,144,12,191,179,162,241, 81,51,145,235,249,14,239,107,
    49,192,214, 31,181,199,106,157,184, 84,204,176,115,121,50,45,127, 4,150,254,
    138,236,205,93,222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180,
    // We repeat the numbers to avoid buffer overflows
    151,160,137,91,90,15,
    131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,142,8,99,37,240,21,10,23,
    190, 6,148,247,120,234,75,0,26,197,62,94,252,219,203,117,35,11,32,57,177,33,
    88,237,149,56,87,174,20,125,136,171,168, 68,175,74,165,71,134,139,48,27,166,
    77,146,158,231,83,111,229,122,60,211,133,230,220,105,92,41,55,46,245,40,244,
    102,143,54, 65,25,63,161, 1,216,80,73,209,76,132,187,208, 89,18,169,200,196,
    135,130,116,188,159,86,164,100,109,198,173,186, 3,64,52,217,226,250,124,123,
    5,202,38,147,118,126,255,82,85,212,207,206,59,227,47,16,58,17,182,189,28,42,
    223,183,170,213,119,248,152, 2,44,154,163, 70,221,153,101,155,167, 43,172,9,
    129,22,39,253, 19,98,108,110,79,113,224,232,178,185, 112,104,218,246,97,228,
    251,34,242,193,238,210,144,12,191,179,162,241, 81,51,145,235,249,14,239,107,
    49,192,214, 31,181,199,106,157,184, 84,204,176,115,121,50,45,127, 4,150,254,
    138,236,205,93,222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180
];

PerlinFade :: inline (t : float) -> float #must
{
    return t * t * t * (t * (t * 6 - 15) + 10);
}

PerlinGradient :: inline (hash : s32, x : float, y : float) -> float #must
{
    ifx hash & 0x3 ==
    {
    case 0x0; return  x + y;
    case 0x1; return -x + y;
    case 0x2; return -x - y;
    case 0x3; return  x - y;
    case;     return 0;
    }
}

PerlinNoise :: (x : float, y : float) -> float #must
#no_abc
{
    x_floor := Floor (x);
    y_floor := Floor (y);
    xi := (cast (int) x_floor) & 255;
    yi := (cast (int) y_floor) & 255;
    xf := x - x_floor;
    yf := y - y_floor;

    u := PerlinFade (xf);
    v := PerlinFade (yf);

    P :: Perlin_Permutation_Table;
    aa := P[P[xi    ] + yi    ];
    ab := P[P[xi    ] + yi + 1];
    ba := P[P[xi + 1] + yi    ];
    bb := P[P[xi + 1] + yi + 1];

    x1, x2 : float = ---;

    x1 = Lerp (
        PerlinGradient (aa, xf    , yf),
        PerlinGradient (ba, xf - 1, yf),
        u
    );

    x2 = Lerp (
        PerlinGradient (ab, xf    , yf - 1),
        PerlinGradient (bb, xf - 1, yf - 1),
        u
    );

    return Lerp (x1, x2, v);
}

PerlinGradient :: inline (hash : s32, x : float, y : float, z : float) -> float #must
{
    ifx hash & 0xf ==
    {
    case 0x0; return  x + y;
    case 0x1; return -x + y;
    case 0x2; return  x - y;
    case 0x3; return -x - y;
    case 0x4; return  x + z;
    case 0x5; return -x + z;
    case 0x6; return  x - z;
    case 0x7; return -x - z;
    case 0x8; return  y + z;
    case 0x9; return -y + z;
    case 0xa; return  y - z;
    case 0xb; return -y - z;
    case 0xc; return  y + x;
    case 0xd; return -y + z;
    case 0xe; return  y - x;
    case 0xf; return -y - z;
    case;     return 0;
    }
}

PerlinNoise :: (x : float, y : float, z : float) -> float #must
#no_abc
{
    x_floor := Floor (x);
    y_floor := Floor (y);
    z_floor := Floor (z);
    xi := (cast (int) x_floor) & 255;
    yi := (cast (int) y_floor) & 255;
    zi := (cast (int) z_floor) & 255;
    xf := x - x_floor;
    yf := y - y_floor;
    zf := z - z_floor;

    u := PerlinFade (xf);
    v := PerlinFade (yf);
    w := PerlinFade (zf);

    P :: Perlin_Permutation_Table;
    aaa := P[P[P[xi    ] + yi    ] + zi    ];
    aba := P[P[P[xi    ] + yi + 1] + zi    ];
    aab := P[P[P[xi    ] + yi    ] + zi + 1];
    abb := P[P[P[xi    ] + yi + 1] + zi + 1];
    baa := P[P[P[xi + 1] + yi    ] + zi    ];
    bba := P[P[P[xi + 1] + yi + 1] + zi    ];
    bab := P[P[P[xi + 1] + yi    ] + zi + 1];
    bbb := P[P[P[xi + 1] + yi + 1] + zi + 1];

    x1, x2, y1, y2 : float = ---;

    x1 = Lerp (
        PerlinGradient (aaa, xf    , yf, zf),
        PerlinGradient (baa, xf - 1, yf, zf),
        u
    );

    x2 = Lerp (
        PerlinGradient (aba, xf    , yf - 1, zf),
        PerlinGradient (bba, xf - 1, yf - 1, zf),
        u
    );

    y1 = Lerp (x1, x2, v);

    x1 = Lerp (
        PerlinGradient (aab, xf    , yf, zf - 1),
        PerlinGradient (bab, xf - 1, yf, zf - 1),
        u
    );

    x2 = Lerp (
        PerlinGradient (abb, xf    , yf - 1, zf - 1),
        PerlinGradient (bbb, xf - 1, yf - 1, zf - 1),
        u
    );

    y2 = Lerp (x1, x2, v);

    return Lerp (y1, y2, w);
}

PerlinFractalMax :: inline (octaves : int, persistance : float) -> float #must
{
    result : float;
    amplitude := 1.0;

    for i : 0..octaves - 1
    {
        if amplitude < Perlin_Fractal_Min_Amplitude
            break;

        result += amplitude;
        amplitude *= persistance;
    }

    return result;
}

PerlinFractalNoise :: (using params : NoiseParams, offsets : []Vec2f, x : float, y : float) -> float #must
{
    oct := Min (octaves, Perlin_Fractal_Max_Octaves);
    Assert (offsets.count >= oct);

    result : float;
    amplitude := 1.0;
    frequency := scale;
    for i : 0..oct - 1
    #no_abc
    {
        if amplitude < Perlin_Fractal_Min_Amplitude
            break;

        result += PerlinNoise (
            x * frequency + offsets[i].x,
            y * frequency + offsets[i].y
        ) * amplitude;

        amplitude *= persistance;
        frequency *= lacunarity;
    }

    return result / max_amplitude;
}

PerlinFractalNoise :: (using params : NoiseParams, offsets : []Vec3f, x : float, y : float, z : float) -> float #must
{
    oct := Min (octaves, Perlin_Fractal_Max_Octaves);
    Assert (offsets.count >= oct);

    result : float;
    amplitude := 1.0;
    frequency := scale;
    for i : 0..oct - 1
    #no_abc
    {
        if amplitude < Perlin_Fractal_Min_Amplitude
            break;

        result += PerlinNoise (
            x * frequency + offsets[i].x,
            y * frequency + offsets[i].y,
            z * frequency + offsets[i].z
        ) * amplitude;

        amplitude *= persistance;
        frequency *= lacunarity;
    }

    return result / max_amplitude;
}

PerlinGenerateOffsets :: inline (rng : *RNG, offsets : []Vec2f)
{
    for * offsets
    {
        it.x = RandomRangeFloat (rng, -10000, 10000);
        it.y = RandomRangeFloat (rng, -10000, 10000);
    }
}

PerlinGenerateOffsets :: inline (rng : *RNG, offsets : []Vec3f)
{
    for * offsets
    {
        it.x = RandomRangeFloat (rng, -10000, 10000);
        it.y = RandomRangeFloat (rng, -10000, 10000);
        it.z = RandomRangeFloat (rng, -10000, 10000);
    }
}
