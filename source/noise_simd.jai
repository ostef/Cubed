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
        // xi := (cast (s32) Floor (x))
        cvtps2dq.y xi:, floor_x;
        cvtps2dq.y yi:, floor_y;

        // We're using bitwise AND for packed floats,
        // but the bits represent 8 packed 32-bit ints
        // This seems to work fine, but there may be edge cases
        // xi := (cast  (s32) Floor (x)) & 255
        andps.y xi, xi, [two_fifty_five];
        andps.y yi, yi, [two_fifty_five];

    }

    Fade :: (dest : reg, src : reg) #expand
    {
        sixes := float.[6,6,6,6,6,6,6,6].data;
        fifteens := float.[15,15,15,15,15,15,15,15].data;
        tens := float.[10,10,10,10,10,10,10,10].data;
        #asm AVX
        {
            // Setup the values
            movups.y dest, src;

            // Multiply by 6
            mulps.y dest, dest, [sixes]; // t * 6

            // Subtract 15
            subps.y dest, dest, [fifteens]; // t * 6 - 15

            // Multiply by t
            mulps.y dest, dest, src; // t * (t * 6 - 15)
            // Add 10
            addps.y dest, dest, [tens]; // t * (t * 6 - 15) + 10

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

    IndexIntoPermutationTable :: (x : reg, y : reg, dest : reg, $x_disp := 0) #expand
    {
        #asm AVX, AVX2
        {
            // P[xi]
            // For all the bits in gather_mask that is set,
            // gatherdps will gather for the bit index at the given address
            // For all the bits that are unset, nothing is done
            // The mask is reset to 0 after gathering
            pcmpeqd.y gather_mask:, gather_mask, gather_mask;
            gatherdps.y index:, [`table + x * 4 + x_disp], gather_mask;

            // P[xi] + yi
            paddd.y index, index, y;

            // P[ P[xi] + yi ]
            pcmpeqd.y gather_mask, gather_mask, gather_mask;
            gatherdps.y dest, [`table + index * 4], gather_mask;
        }
    }

    // aa := P[P[xi    ] + yi    ];
    // ba := P[P[xi + 1] + yi    ];
    // ab := P[P[xi    ] + yi + 1];
    // bb := P[P[xi + 1] + yi + 1];

    #asm
    {
        aa : vec;
        ba : vec;
        ab : vec;
        bb : vec;
    }

    table := Perlin_Permutation_Table.data;
    IndexIntoPermutationTable (xi, yi, aa);
    IndexIntoPermutationTable (xi, yi, ba, x_disp = 4);

    ones := s32.[1,1,1,1,1,1,1,1].data;
    #asm AVX, AVX2
    {
        paddd.y yi, yi, [ones];
    }

    IndexIntoPermutationTable (xi, yi, ab);
    IndexIntoPermutationTable (xi, yi, bb, x_disp = 4);

    // Modifies hash and dest
    Gradient :: (dest : reg, hash : reg, x : reg, y : reg) #expand
    {
        ones := s32.[1,1,1,1,1,1,1,1].data;
        threes := s32.[3,3,3,3,3,3,3,3].data;
        #asm AVX, AVX2
        {
            xorps.y zeros:, zeros, zeros;

            // hash = hash & 3
            andps.y hash, hash, [threes];

            // Y is negative if hash is greater than 1,
            // that is if the second bit is set. To check
            // that, we bitshift Y by 1
            psrld.y y_negative_cond:, hash, 1; // y_negative_cond >>= 1

            // X is negative if hash is 0 or hash is 3
            // that is if the lsb of hash is set and y_negative is 0
            // or if lsb of hash is not set and y_negative is 1
            // Which is just (hash AND 1) XOR y_negative
            andps.y x_negative_cond:, hash, [ones];
            xorps.y x_negative_cond, x_negative_cond, y_negative_cond;

            // Both y_negative_cond and x_negative_cond only have the LSB
            // set, but blendvps checks only the MSB of each dword.
            // pcmpeqd will set all bits to one or zero based on the equality
            // so our registers will be setup correctly for the blend
            pcmpeqd.y y_negative_cond, y_negative_cond, [ones];
            pcmpeqd.y x_negative_cond, x_negative_cond, [ones];

            subps.y v:, zeros, y;   // v = -y
            blendvps.y v, y, v, y_negative_cond;

            subps.y u:, zeros, x;   // u = -x
            blendvps.y u, x, u, x_negative_cond;

            addps.y dest, u, v;
        }
    }

    // https://fgiesen.wordpress.com/2012/08/15/linear-interpolation-past-present-and-future/
    LerpAndStoreInA :: (a : reg, b : reg, t : reg) #expand
    {
        #asm AVX, FMA
        {
            fnmadd231ps.y a, t, a; // -t * a + a = -a * (t - 1)
            fmadd231ps.y a, t, b; // t * b - t * a + a
        }
    }

    #asm AVX
    {
        x1 : vec;
        x2 : vec;
        x3 : vec;
    }

    fones := float.[1,1,1,1,1,1,1,1].data;

    Gradient (x1, aa, xf, yf);

    #asm AVX { subps.y xf, xf, [fones]; }

    Gradient (x3, ba, xf, yf);

    LerpAndStoreInA (x1, x3, u);

    #asm AVX { subps.y yf, yf, [fones]; }

    Gradient (x3, bb, xf, yf);

    #asm AVX { addps.y xf, xf, [fones]; }

    Gradient (x2, ab, xf, yf);
    LerpAndStoreInA (x2, x3, u);

    LerpAndStoreInA (x1, x2, t = v);

    #asm AVX { movups.y [result_ptr], x1; }

    return result;
}

PerlinSIMDTests :: ()
{
    Machine_X64 :: #import "Machine_X64";

    cpu_info := Machine_X64.get_cpu_info ();
    if !Machine_X64.check_feature (cpu_info.feature_leaves, .AVX)
    {
        LogError ("AVX is not supported");
        return;
    }
    if !Machine_X64.check_feature (cpu_info.feature_leaves, .AVX2)
    {
        LogError ("AVX2 is not supported");
        return;
    }
    if !Machine_X64.check_feature (cpu_info.feature_leaves, .FMA)
    {
        LogError ("FMA is not supported");
        return;
    }

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

        // res_as_ints := (cast (*[8]s32) *res).*;
        // Print ("Result is ");
        // for i : 0..7
        //     Print ("{:b} ", res_as_ints[i]);
        // Print ("\n");
    }
}
