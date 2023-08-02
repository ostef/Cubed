reg :: __reg;

// SIMD resources:
// Tables that show the different instructions, nicely categorized:
// https://www.officedaytime.com/simd512e/

PerlinFadeLinear :: inline (t : *[8]float)
{
    for i : 0..7
       t.*[i] = t.*[i] * t.*[i] * t.*[i] * (t.*[i] * (t.*[i] * 6 - 15) + 10);
}

PerlinFadeSIMD :: inline (t : *[8]float)
{
    Sixes :: float.[6,6,6,6,6,6,6,6];
    Fifteens :: float.[15,15,15,15,15,15,15,15];
    Tens :: float.[10,10,10,10,10,10,10,10];

    sixes_ptr := Sixes.data;
    fifteens_ptr := Fifteens.data;
    tens_ptr := Tens.data;
    t_ptr := t.data;
    #asm AVX
    {
        // res is our result
        movups.y res:, [t_ptr];

        // Multiply by 6
        mulps.y res, res, [sixes_ptr]; // t * 6

        // Subtract 15
        subps.y res, res, [fifteens_ptr]; // t * 6 - 15

        // Multiply by t
        mulps.y res, res, [t_ptr]; // t * (t * 6 - 15)
        // Add 10
        addps.y res, res, [tens_ptr]; // t * (t * 6 - 15) + 10

        // Multiply by t three times
        mulps.y res, res, [t_ptr]; // t * (t * (t * 6 - 15) + 10)
        mulps.y res, res, [t_ptr]; // t * t * (t * (t * 6 - 15) + 10)
        mulps.y res, res, [t_ptr]; // t * t * t * (t * (t * 6 - 15) + 10)

        // Move the result back to t
        movups.y [t_ptr], res;
    }
}

_PerlinNoise :: (x : float64, y : float64) -> float64 #must
#no_abc
{
    xi := (cast (int) Floor (x)) & 255;
    yi := (cast (int) Floor (y)) & 255;
    xf := x - Floor (x);
    yf := y - Floor (y);

    u := PerlinFade (xf);
    v := PerlinFade (yf);

    P :: Perlin_Permutation_Table;
    aa := P[P[xi    ] + yi    ];
    ba := P[P[xi + 1] + yi    ];
    ab := P[P[xi    ] + yi + 1];
    bb := P[P[xi + 1] + yi + 1];

    x1, x2 : float64 = ---;

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

PerlinNoiseSIMD :: (x : [8]float, y : [8]float) -> [8]float #must
#no_abc
{
    result : [8]float = ---;
    x_ptr := x.data;
    y_ptr := y.data;
    result_ptr := result.data;

    #asm AVX
    {
        // roundps takes an imm8 as third argument
        // 0x09 for this value means floor, 0x0A means ceil
        roundps.y floor_x:, [x_ptr], 0x09;
        roundps.y floor_y:, [y_ptr], 0x09;

        // xf := x - Floor (x)
        movups.y xf:, [x_ptr];
        movups.y yf:, [y_ptr];
        subps.y xf, xf, floor_x;
        subps.y yf, yf, floor_y;

    }

    two_fifty_five := s32.[255,255,255,255,255,255,255,255].data;
    #asm AVX
    {
        // xi := (cast (s32) Floor (x)) & 255
        cvtps2dq.y xi:, floor_x;
        cvtps2dq.y yi:, floor_y;

        // We're using bitwise AND for packed floats,
        // but the bits represent 8 packed 32-bit ints
        // This seems to work fine, but there may be edge cases
        andps.y xi, xi, [two_fifty_five];
        andps.y yi, yi, [two_fifty_five];

    }

    Fade :: (dest : reg, src : reg) #expand
    {
        Sixes :: float.[6,6,6,6,6,6,6,6];
        Fifteens :: float.[15,15,15,15,15,15,15,15];
        Tens :: float.[10,10,10,10,10,10,10,10];

        sixes_ptr := Sixes.data;
        fifteens_ptr := Fifteens.data;
        tens_ptr := Tens.data;
        #asm AVX
        {
            // Setup the values
            movups.y dest, src;

            // Multiply by 6
            mulps.y dest, dest, [sixes_ptr]; // t * 6

            // Subtract 15
            subps.y dest, dest, [fifteens_ptr]; // t * 6 - 15

            // Multiply by t
            mulps.y dest, dest, src; // t * (t * 6 - 15)
            // Add 10
            addps.y dest, dest, [tens_ptr]; // t * (t * 6 - 15) + 10

            // Multiply by t three times
            mulps.y dest, dest, src; // t * (t * (t * 6 - 15) + 10)
            mulps.y dest, dest, src; // t * t * (t * (t * 6 - 15) + 10)
            mulps.y dest, dest, src; // t * t * t * (t * (t * 6 - 15) + 10)
        }
    }

    #asm AVX
    {
        u : vec;
        v : vec;
    }

    Fade (u, xf);
    Fade (v, yf);

    IndexIntoPermutationTable :: (table : *void, x : reg, y : reg, dest : reg, $x_disp := 0) #expand
    {
        #asm AVX, AVX2
        {
            // P[xi]
            // For all the bits in gather_mask that is set,
            // gatherdps will gather for the bit index at the given address
            // For all the bits that are unset, nothing is done
            // The mask is reset to 0 after gathering
            pcmpeqd.y gather_mask:, gather_mask, gather_mask;
            gatherdps.y index:, [table + x * 4 + x_disp], gather_mask;

            // P[xi] + yi
            paddd.y index, index, y;

            // P[ P[xi] + yi ]
            pcmpeqd.y gather_mask, gather_mask, gather_mask;
            gatherdps.y dest, [table + index * 4], gather_mask;
        }
    }

    #asm
    {
        aa : vec;
        ba : vec;
        ab : vec;
        bb : vec;
    }

    IndexIntoPermutationTable (Perlin_Permutation_Table.data, xi, yi, aa);
    IndexIntoPermutationTable (Perlin_Permutation_Table.data, xi, yi, ba, x_disp = 4);

    Ones := s32.[1,1,1,1,1,1,1,1];
    ones := Ones.data;
    #asm AVX, AVX2
    {
        paddd.y yi, yi, [ones];
    }

    IndexIntoPermutationTable (Perlin_Permutation_Table.data, xi, yi, ab);
    IndexIntoPermutationTable (Perlin_Permutation_Table.data, xi, yi, bb, x_disp = 4);

    // _aa : [8]s32;
    // _ba : [8]s32;
    // _ab : [8]s32;
    // _bb : [8]s32;
    // aa_ptr := _aa.data;
    // ba_ptr := _ba.data;
    // ab_ptr := _ab.data;
    // bb_ptr := _bb.data;
    // #asm AVX
    // {
    //     movdqu.y [aa_ptr], aa;
    //     movdqu.y [ba_ptr], ba;
    //     movdqu.y [ab_ptr], ab;
    //     movdqu.y [bb_ptr], bb;
    // }
    // Println (_aa);
    // Println (_ba);
    // Println (_ab);
    // Println (_bb);

    u_result : [8]float = ---;
    u_ptr := u_result.data;
    #asm AVX
    {
        movups [u_ptr], u;

        cvtdq2ps.y floor_x, xi;
        movups [result_ptr], floor_x;
    }

    return u_result;
}

PerlinSIMDTests :: ()
{
    Println ("Perlin SIMD Tests");

    Println ("PerlinFadeLinear:");
    {
        t : [8]float = .[0.0108, 0.1354, 0.2485, 0.4897, 0.6485, 0.7684, 0.82983, 0.9849];
        PerlinFadeLinear (*t);
        Println ("Result is %", t);
    }

    Print ("\n");

    Println ("PerlinFadeSIMD:");
    {
        t : [8]float = .[0.0108, 0.1354, 0.2485, 0.4897, 0.6485, 0.7684, 0.82983, 0.9849];
        PerlinFadeSIMD (*t);
        Println ("Result is %", t);
    }

    Print ("\n");

    Println ("PerlinNoise:");
    {
        x : [8]float = .[12.239, 23.0234, 2304,201, 392.923, 583.81, 908.162, 674.1897];
        y : [8]float = .[12.239, 23.0234, 2304,201, 392.923, 583.81, 908.162, 674.1897];
        Println ("X is %\nY is %", x, y);

        res : [8]float = ---;

        for i : 0..7
            res[i] = xx _PerlinNoise (x[i], y[i]);

        Println ("Result is %", res);
    }

    Print ("\n");

    Println ("PerlinNoiseSIMD:");
    {
        x : [8]float = .[12.239, 23.0234, 2304,201, 392.923, 583.81, 908.162, 674.1897];
        y : [8]float = .[12.239, 23.0234, 2304,201, 392.923, 583.81, 908.162, 674.1897];
        res := PerlinNoiseSIMD (x, y);

        Println ("Result is %", res);
    }
}
