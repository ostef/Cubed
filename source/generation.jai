// Resources:
// Minecraft terrain generation in a nutshell, by Henrik Kniberg: https://www.youtube.com/watch?v=CSa5O6knuwI
// Cubiomes, a C library that mimics the Minecraft biome generation: https://github.com/Cubitect/cubiomes
// https://minecraft.fandom.com/wiki/Biome

Max_Spline_Points :: 20;

SplinePoint :: struct
{
    location : float;
    value : float;
    derivative : float;
    nested_spline : *Spline;
}

Spline :: struct
{
    t_value_index : int;
    point_count : s64;
    points : [Max_Spline_Points]SplinePoint;
}

SplineFree :: (spline : *Spline, allocator := context.allocator)
{
    for i : 0..spline.point_count - 1
    {
        if spline.points[i].nested_spline
            SplineFree (spline.points[i].nested_spline, allocator);
    }

    Free (spline, allocator);
}

SplinePushPoint :: inline (using spline : *Spline, derivative : float, location : float, value : float)
{
    Assert (point_count < Max_Spline_Points, "Exceeded max spline points");
    point := *points[point_count];
    point_count += 1;

    point.location = location;
    point.value = value;
    point.derivative = derivative;
}

SplinePushPoint :: inline (using spline : *Spline, derivative : float, location : float, nested_spline : *Spline)
{
    Assert (point_count < Max_Spline_Points, "Exceeded max spline points");
    point := *points[point_count];
    point_count += 1;

    point.location = location;
    point.nested_spline = nested_spline;
    point.derivative = derivative;
}

HermiteCubicCalculate :: inline (x0 : float, y0 : float, der0 : float, x1 : float, y1 : float, der1 : float, t : float) -> float #must
{
    f8 := der0 * (x1 - x0) - (y1 - y0);
    f9 := -der1 * (x1 - x0) + (y1 - y0);

    return Lerp (y0, y1, t) + t * (1 - t) * Lerp (f8, f9, t);
}

HermiteCubicCalculate :: inline (point : SplinePoint, t_values : []float) -> float #must
{
    if point.nested_spline
        return HermiteCubicCalculate (point.nested_spline, t_values);

    return point.value;
}

HermiteCubicCalculate :: (using spline : Spline, t_values : []float) -> float #must
{
    t := t_values[t_value_index];

    if point_count == 0
        return 0;

    index : int;
    while index < point_count
    {
        if points[index].location >= t
            break;

        index += 1;
    }

    if index == 0 || index == point_count
    {
        if index != 0
            index -= 1;

        point := points[index];
        y := HermiteCubicCalculate (point, t_values);

        return y + point.derivative * (t - point.location);
    }

    p0 := points[index - 1];
    p1 := points[index];

    return HermiteCubicCalculate (
        p0.location, HermiteCubicCalculate (p0, t_values), p0.derivative,
        p1.location, HermiteCubicCalculate (p1, t_values), p1.derivative,
        InverseLerp (p0.location, p1.location, t)
    );
}

TerrainNoise :: enum
{
    Temperature;
    Humidity;
    Continentalness;
    Erosion;
    Weirdness;

    Count;
}

TerrainParam :: enum
{
    Temperature;
    Humidity;
    Continentalness;
    Erosion;
    Weirdness;
    Ridges;
    Depth;
    Surface_Height;

    Count;
}

SurfaceParams :: struct
{
    spline : *Spline;
    spline_y_range : Vec2f;
    water_level : s32 = 128;
    noise_amplitudes := float.[
        2.31,   // Temperature
        1.76,   // Humidity
        2.13,   // Continentalness
        2.52,   // Erosion
        2.97    // Weirdness
    ];
    noise_params : [TerrainNoise.Count]NoiseParams = .[
        .{scale=0.00041, octaves=3, persistance=0.023, lacunarity=2.379},
        .{scale=0.00145, octaves=4, persistance=0.139, lacunarity=3.476},
        .{scale=0.00013, octaves=6, persistance=0.250, lacunarity=4.085},
        .{scale=0.00161, octaves=5, persistance=0.168, lacunarity=3.897},
        .{scale=0.00106, octaves=4, persistance=0.267, lacunarity=4.824},
    ];
}

CalculateTerrainNoise :: inline (using generator : Generator, noise : TerrainNoise, x : float, y : float) -> float #must
{
    max_val := cast (float) PerlinFractalMax (noise_params[noise].octaves, noise_params[noise].persistance);
    val := cast (float) PerlinFractalNoise (noise_params[noise], noise_offsets[noise], x, y);

    return val / max_val;
}

CalculateTerrainParam :: (using generator : Generator, param : TerrainParam, x : float, y : float) -> float #must
{
    if param < xx TerrainNoise.Count
    {
        val := CalculateTerrainNoise (generator, cast (TerrainNoise) param, x, y);
        val *= surface_params.noise_amplitudes[xx param];

        return val;
    }
    else if param == .Ridges
    {
        weirdness := CalculateTerrainParam (generator, .Weirdness, x, y);
        // weirdness = Abs (3 * Abs (weirdness) - 2);
        weirdness = 1 - Abs (3 * Abs (weirdness) - 2);
        // weirdness = -3 * Abs (Abs (weirdness) - 2.0 / 3.0) - 1.0 / 3.0;

        return weirdness;
    }
    else if param == .Depth
    {
        First_Value :: cast (s64) TerrainParam.Continentalness;
        Last_Value  :: cast (s64) TerrainParam.Ridges;

        t_values : [Last_Value - First_Value + 1]float = ---;
        for i : First_Value..Last_Value
        {
            if i == xx TerrainParam.Weirdness
                continue;
            t_values[i - First_Value] = CalculateTerrainParam (generator, cast (TerrainParam) i, x, y);
        }

        Assert (surface_params.spline != null, "Surface spline is null (did you forget to call InitDefaultSurfaceSpline?)");
        depth := HermiteCubicCalculate (surface_params.spline, t_values) - 0.015;
        return depth;
    }
    else if param == .Surface_Height
    {
        depth := CalculateTerrainParam (generator, .Depth, x, y);
        return 128 + depth * 128;
        // return (1 - (83.0 / 160.0) + depth) * (10000.0 / 76.0);
    }

    return 0;
}

Generator :: struct
{
    seed : u64;
    noise_offsets : [TerrainNoise.Count][Perlin_Fractal_Max_Octaves]Vec2f;
    using surface_params : SurfaceParams;
}

SplineCreate :: inline (t_value_index : s64, allocator := context.allocator) -> *Spline #must
{
    spline := Alloc (Spline, allocator);
    spline.t_value_index = t_value_index;

    return spline;
}

SplineClone :: (spline : *Spline, allocator := context.allocator) -> *Spline #must
{
    result := Alloc (Spline, allocator);
    for i : 0..spline.point_count - 1
    {
        pt := spline.points[i];
        if pt.nested_spline
            result.points[i].nested_spline = SplineClone (pt.nested_spline, allocator);

        result.points[i].derivative = pt.derivative;
        result.points[i].location = pt.location;
        result.points[i].value = pt.value;
    }

    result.t_value_index = spline.t_value_index;
    result.point_count = spline.point_count;

    return result;
}

InitDefaultSurfaceSpline :: (params : *SurfaceParams)
{
    spline_8856 := SplineCreate (0);
    params.spline = spline_8856;

    SplinePushPoint (spline_8856, 0.000000, -1.100000, 0.044000);
    SplinePushPoint (spline_8856, 0.000000, -1.020000, -0.222200);
    SplinePushPoint (spline_8856, 0.000000, -0.510000, -0.222200);
    SplinePushPoint (spline_8856, 0.000000, -0.440000, -0.120000);
    SplinePushPoint (spline_8856, 0.000000, -0.180000, -0.120000);
    spline_9512 := SplineCreate (1);
    spline_10168 := SplineCreate (3);
    SplinePushPoint (spline_10168, 0.389401, -1.000000, -0.088802);
    SplinePushPoint (spline_10168, 0.389401, 1.000000, 0.690000);
    SplinePushPoint (spline_9512, 0.000000, -0.850000, spline_10168);
    spline_10824 := SplineCreate (3);
    SplinePushPoint (spline_10824, 0.377880, -1.000000, -0.115760);
    SplinePushPoint (spline_10824, 0.377880, 1.000000, 0.640000);
    SplinePushPoint (spline_9512, 0.000000, -0.700000, spline_10824);
    spline_11480 := SplineCreate (3);
    SplinePushPoint (spline_11480, 0.000000, -1.000000, -0.222200);
    SplinePushPoint (spline_11480, 0.000000, -0.750000, -0.222200);
    SplinePushPoint (spline_11480, 0.000000, -0.650000, 0.000000);
    SplinePushPoint (spline_11480, 0.000000, 0.595455, 0.000000);
    SplinePushPoint (spline_11480, 0.253456, 0.605455, 0.000000);
    SplinePushPoint (spline_11480, 0.253456, 1.000000, 0.100000);
    SplinePushPoint (spline_9512, 0.000000, -0.400000, spline_11480);
    spline_12136 := SplineCreate (3);
    SplinePushPoint (spline_12136, 0.500000, -1.000000, -0.300000);
    SplinePushPoint (spline_12136, 0.000000, -0.400000, 0.050000);
    SplinePushPoint (spline_12136, 0.000000, 0.000000, 0.050000);
    SplinePushPoint (spline_12136, 0.000000, 0.400000, 0.050000);
    SplinePushPoint (spline_12136, 0.007000, 1.000000, 0.060000);
    SplinePushPoint (spline_9512, 0.000000, -0.350000, spline_12136);
    spline_12792 := SplineCreate (3);
    SplinePushPoint (spline_12792, 0.500000, -1.000000, -0.150000);
    SplinePushPoint (spline_12792, 0.000000, -0.400000, 0.000000);
    SplinePushPoint (spline_12792, 0.000000, 0.000000, 0.000000);
    SplinePushPoint (spline_12792, 0.100000, 0.400000, 0.050000);
    SplinePushPoint (spline_12792, 0.007000, 1.000000, 0.060000);
    SplinePushPoint (spline_9512, 0.000000, -0.100000, spline_12792);
    spline_13448 := SplineCreate (3);
    SplinePushPoint (spline_13448, 0.500000, -1.000000, -0.150000);
    SplinePushPoint (spline_13448, 0.000000, -0.400000, 0.000000);
    SplinePushPoint (spline_13448, 0.000000, 0.000000, 0.000000);
    SplinePushPoint (spline_13448, 0.000000, 0.400000, 0.000000);
    SplinePushPoint (spline_13448, 0.000000, 1.000000, 0.000000);
    SplinePushPoint (spline_9512, 0.000000, 0.200000, spline_13448);
    spline_14104 := SplineCreate (3);
    SplinePushPoint (spline_14104, 0.000000, -1.000000, -0.020000);
    SplinePushPoint (spline_14104, 0.000000, -0.400000, -0.030000);
    SplinePushPoint (spline_14104, 0.000000, 0.000000, -0.030000);
    SplinePushPoint (spline_14104, 0.060000, 0.400000, 0.000000);
    SplinePushPoint (spline_14104, 0.000000, 1.000000, 0.000000);
    SplinePushPoint (spline_9512, 0.000000, 0.700000, spline_14104);
    SplinePushPoint (spline_8856, 0.000000, -0.160000, spline_9512);
    spline_14760 := SplineCreate (1);
    spline_15416 := SplineCreate (3);
    SplinePushPoint (spline_15416, 0.389401, -1.000000, -0.088802);
    SplinePushPoint (spline_15416, 0.389401, 1.000000, 0.690000);
    SplinePushPoint (spline_14760, 0.000000, -0.850000, spline_15416);
    spline_16072 := SplineCreate (3);
    SplinePushPoint (spline_16072, 0.377880, -1.000000, -0.115760);
    SplinePushPoint (spline_16072, 0.377880, 1.000000, 0.640000);
    SplinePushPoint (spline_14760, 0.000000, -0.700000, spline_16072);
    spline_16728 := SplineCreate (3);
    SplinePushPoint (spline_16728, 0.000000, -1.000000, -0.222200);
    SplinePushPoint (spline_16728, 0.000000, -0.750000, -0.222200);
    SplinePushPoint (spline_16728, 0.000000, -0.650000, 0.000000);
    SplinePushPoint (spline_16728, 0.000000, 0.595455, 0.000000);
    SplinePushPoint (spline_16728, 0.253456, 0.605455, 0.000000);
    SplinePushPoint (spline_16728, 0.253456, 1.000000, 0.100000);
    SplinePushPoint (spline_14760, 0.000000, -0.400000, spline_16728);
    spline_17384 := SplineCreate (3);
    SplinePushPoint (spline_17384, 0.500000, -1.000000, -0.300000);
    SplinePushPoint (spline_17384, 0.000000, -0.400000, 0.050000);
    SplinePushPoint (spline_17384, 0.000000, 0.000000, 0.050000);
    SplinePushPoint (spline_17384, 0.000000, 0.400000, 0.050000);
    SplinePushPoint (spline_17384, 0.007000, 1.000000, 0.060000);
    SplinePushPoint (spline_14760, 0.000000, -0.350000, spline_17384);
    spline_18040 := SplineCreate (3);
    SplinePushPoint (spline_18040, 0.500000, -1.000000, -0.150000);
    SplinePushPoint (spline_18040, 0.000000, -0.400000, 0.000000);
    SplinePushPoint (spline_18040, 0.000000, 0.000000, 0.000000);
    SplinePushPoint (spline_18040, 0.100000, 0.400000, 0.050000);
    SplinePushPoint (spline_18040, 0.007000, 1.000000, 0.060000);
    SplinePushPoint (spline_14760, 0.000000, -0.100000, spline_18040);
    spline_18696 := SplineCreate (3);
    SplinePushPoint (spline_18696, 0.500000, -1.000000, -0.150000);
    SplinePushPoint (spline_18696, 0.000000, -0.400000, 0.000000);
    SplinePushPoint (spline_18696, 0.000000, 0.000000, 0.000000);
    SplinePushPoint (spline_18696, 0.000000, 0.400000, 0.000000);
    SplinePushPoint (spline_18696, 0.000000, 1.000000, 0.000000);
    SplinePushPoint (spline_14760, 0.000000, 0.200000, spline_18696);
    spline_19352 := SplineCreate (3);
    SplinePushPoint (spline_19352, 0.000000, -1.000000, -0.020000);
    SplinePushPoint (spline_19352, 0.000000, -0.400000, -0.030000);
    SplinePushPoint (spline_19352, 0.000000, 0.000000, -0.030000);
    SplinePushPoint (spline_19352, 0.060000, 0.400000, 0.000000);
    SplinePushPoint (spline_19352, 0.000000, 1.000000, 0.000000);
    SplinePushPoint (spline_14760, 0.000000, 0.700000, spline_19352);
    SplinePushPoint (spline_8856, 0.000000, -0.150000, spline_14760);
    spline_20008 := SplineCreate (1);
    spline_20664 := SplineCreate (3);
    SplinePushPoint (spline_20664, 0.389401, -1.000000, -0.088802);
    SplinePushPoint (spline_20664, 0.389401, 1.000000, 0.690000);
    SplinePushPoint (spline_20008, 0.000000, -0.850000, spline_20664);
    spline_21320 := SplineCreate (3);
    SplinePushPoint (spline_21320, 0.377880, -1.000000, -0.115760);
    SplinePushPoint (spline_21320, 0.377880, 1.000000, 0.640000);
    SplinePushPoint (spline_20008, 0.000000, -0.700000, spline_21320);
    spline_21976 := SplineCreate (3);
    SplinePushPoint (spline_21976, 0.000000, -1.000000, -0.222200);
    SplinePushPoint (spline_21976, 0.000000, -0.750000, -0.222200);
    SplinePushPoint (spline_21976, 0.000000, -0.650000, 0.000000);
    SplinePushPoint (spline_21976, 0.000000, 0.595455, 0.000000);
    SplinePushPoint (spline_21976, 0.253456, 0.605455, 0.000000);
    SplinePushPoint (spline_21976, 0.253456, 1.000000, 0.100000);
    SplinePushPoint (spline_20008, 0.000000, -0.400000, spline_21976);
    spline_22632 := SplineCreate (3);
    SplinePushPoint (spline_22632, 0.500000, -1.000000, -0.250000);
    SplinePushPoint (spline_22632, 0.000000, -0.400000, 0.050000);
    SplinePushPoint (spline_22632, 0.000000, 0.000000, 0.050000);
    SplinePushPoint (spline_22632, 0.000000, 0.400000, 0.050000);
    SplinePushPoint (spline_22632, 0.007000, 1.000000, 0.060000);
    SplinePushPoint (spline_20008, 0.000000, -0.350000, spline_22632);
    spline_23288 := SplineCreate (3);
    SplinePushPoint (spline_23288, 0.500000, -1.000000, -0.100000);
    SplinePushPoint (spline_23288, 0.010000, -0.400000, 0.001000);
    SplinePushPoint (spline_23288, 0.010000, 0.000000, 0.003000);
    SplinePushPoint (spline_23288, 0.094000, 0.400000, 0.050000);
    SplinePushPoint (spline_23288, 0.007000, 1.000000, 0.060000);
    SplinePushPoint (spline_20008, 0.000000, -0.100000, spline_23288);
    spline_23944 := SplineCreate (3);
    SplinePushPoint (spline_23944, 0.500000, -1.000000, -0.100000);
    SplinePushPoint (spline_23944, 0.000000, -0.400000, 0.010000);
    SplinePushPoint (spline_23944, 0.000000, 0.000000, 0.010000);
    SplinePushPoint (spline_23944, 0.040000, 0.400000, 0.030000);
    SplinePushPoint (spline_23944, 0.049000, 1.000000, 0.100000);
    SplinePushPoint (spline_20008, 0.000000, 0.200000, spline_23944);
    spline_24600 := SplineCreate (3);
    SplinePushPoint (spline_24600, 0.000000, -1.000000, -0.020000);
    SplinePushPoint (spline_24600, 0.000000, -0.400000, -0.030000);
    SplinePushPoint (spline_24600, 0.000000, 0.000000, -0.030000);
    SplinePushPoint (spline_24600, 0.120000, 0.400000, 0.030000);
    SplinePushPoint (spline_24600, 0.049000, 1.000000, 0.100000);
    SplinePushPoint (spline_20008, 0.000000, 0.700000, spline_24600);
    SplinePushPoint (spline_8856, 0.000000, -0.100000, spline_20008);
    spline_25256 := SplineCreate (1);
    spline_25912 := SplineCreate (3);
    SplinePushPoint (spline_25912, 0.000000, -1.000000, 0.202350);
    SplinePushPoint (spline_25912, 0.513825, 0.000000, 0.716175);
    SplinePushPoint (spline_25912, 0.513825, 1.000000, 1.230000);
    SplinePushPoint (spline_25256, 0.000000, -0.850000, spline_25912);
    spline_26568 := SplineCreate (3);
    SplinePushPoint (spline_26568, 0.000000, -1.000000, 0.200000);
    SplinePushPoint (spline_26568, 0.433180, 0.000000, 0.446820);
    SplinePushPoint (spline_26568, 0.433180, 1.000000, 0.880000);
    SplinePushPoint (spline_25256, 0.000000, -0.700000, spline_26568);
    spline_27224 := SplineCreate (3);
    SplinePushPoint (spline_27224, 0.000000, -1.000000, 0.200000);
    SplinePushPoint (spline_27224, 0.391705, 0.000000, 0.308295);
    SplinePushPoint (spline_27224, 0.391705, 1.000000, 0.700000);
    SplinePushPoint (spline_25256, 0.000000, -0.400000, spline_27224);
    spline_27880 := SplineCreate (3);
    SplinePushPoint (spline_27880, 0.500000, -1.000000, -0.250000);
    SplinePushPoint (spline_27880, 0.000000, -0.400000, 0.350000);
    SplinePushPoint (spline_27880, 0.000000, 0.000000, 0.350000);
    SplinePushPoint (spline_27880, 0.000000, 0.400000, 0.350000);
    SplinePushPoint (spline_27880, 0.049000, 1.000000, 0.420000);
    SplinePushPoint (spline_25256, 0.000000, -0.350000, spline_27880);
    spline_28536 := SplineCreate (3);
    SplinePushPoint (spline_28536, 0.500000, -1.000000, -0.100000);
    SplinePushPoint (spline_28536, 0.070000, -0.400000, 0.007000);
    SplinePushPoint (spline_28536, 0.070000, 0.000000, 0.021000);
    SplinePushPoint (spline_28536, 0.658000, 0.400000, 0.350000);
    SplinePushPoint (spline_28536, 0.049000, 1.000000, 0.420000);
    SplinePushPoint (spline_25256, 0.000000, -0.100000, spline_28536);
    spline_29192 := SplineCreate (3);
    SplinePushPoint (spline_29192, 0.500000, -1.000000, -0.100000);
    SplinePushPoint (spline_29192, 0.000000, -0.400000, 0.010000);
    SplinePushPoint (spline_29192, 0.000000, 0.000000, 0.010000);
    SplinePushPoint (spline_29192, 0.040000, 0.400000, 0.030000);
    SplinePushPoint (spline_29192, 0.049000, 1.000000, 0.100000);
    SplinePushPoint (spline_25256, 0.000000, 0.200000, spline_29192);
    spline_29848 := SplineCreate (3);
    SplinePushPoint (spline_29848, 0.500000, -1.000000, -0.100000);
    SplinePushPoint (spline_29848, 0.000000, -0.400000, 0.010000);
    SplinePushPoint (spline_29848, 0.000000, 0.000000, 0.010000);
    SplinePushPoint (spline_29848, 0.040000, 0.400000, 0.030000);
    SplinePushPoint (spline_29848, 0.049000, 1.000000, 0.100000);
    SplinePushPoint (spline_25256, 0.000000, 0.400000, spline_29848);
    spline_30504 := SplineCreate (3);
    SplinePushPoint (spline_30504, 0.000000, -1.000000, -0.100000);
    spline_31160 := SplineCreate (3);
    SplinePushPoint (spline_31160, 0.500000, -1.000000, -0.100000);
    SplinePushPoint (spline_31160, 0.000000, -0.400000, 0.010000);
    SplinePushPoint (spline_31160, 0.000000, 0.000000, 0.010000);
    SplinePushPoint (spline_31160, 0.040000, 0.400000, 0.030000);
    SplinePushPoint (spline_31160, 0.049000, 1.000000, 0.100000);
    SplinePushPoint (spline_30504, 0.000000, -0.400000, spline_31160);
    SplinePushPoint (spline_30504, 0.000000, 0.000000, 0.170000);
    SplinePushPoint (spline_25256, 0.000000, 0.450000, spline_30504);
    spline_31816 := SplineCreate (3);
    SplinePushPoint (spline_31816, 0.000000, -1.000000, -0.100000);
    spline_32472 := SplineCreate (3);
    SplinePushPoint (spline_32472, 0.500000, -1.000000, -0.100000);
    SplinePushPoint (spline_32472, 0.000000, -0.400000, 0.010000);
    SplinePushPoint (spline_32472, 0.000000, 0.000000, 0.010000);
    SplinePushPoint (spline_32472, 0.040000, 0.400000, 0.030000);
    SplinePushPoint (spline_32472, 0.049000, 1.000000, 0.100000);
    SplinePushPoint (spline_31816, 0.000000, -0.400000, spline_32472);
    SplinePushPoint (spline_31816, 0.000000, 0.000000, 0.170000);
    SplinePushPoint (spline_25256, 0.000000, 0.550000, spline_31816);
    spline_33128 := SplineCreate (3);
    SplinePushPoint (spline_33128, 0.500000, -1.000000, -0.100000);
    SplinePushPoint (spline_33128, 0.000000, -0.400000, 0.010000);
    SplinePushPoint (spline_33128, 0.000000, 0.000000, 0.010000);
    SplinePushPoint (spline_33128, 0.040000, 0.400000, 0.030000);
    SplinePushPoint (spline_33128, 0.049000, 1.000000, 0.100000);
    SplinePushPoint (spline_25256, 0.000000, 0.580000, spline_33128);
    spline_33784 := SplineCreate (3);
    SplinePushPoint (spline_33784, 0.000000, -1.000000, -0.020000);
    SplinePushPoint (spline_33784, 0.000000, -0.400000, -0.030000);
    SplinePushPoint (spline_33784, 0.000000, 0.000000, -0.030000);
    SplinePushPoint (spline_33784, 0.120000, 0.400000, 0.030000);
    SplinePushPoint (spline_33784, 0.049000, 1.000000, 0.100000);
    SplinePushPoint (spline_25256, 0.000000, 0.700000, spline_33784);
    SplinePushPoint (spline_8856, 0.000000, 0.250000, spline_25256);
    spline_34440 := SplineCreate (1);
    spline_35096 := SplineCreate (3);
    SplinePushPoint (spline_35096, 0.000000, -1.000000, 0.347926);
    SplinePushPoint (spline_35096, 0.576037, 0.000000, 0.923963);
    SplinePushPoint (spline_35096, 0.576037, 1.000000, 1.500000);
    SplinePushPoint (spline_34440, 0.000000, -0.850000, spline_35096);
    spline_35752 := SplineCreate (3);
    SplinePushPoint (spline_35752, 0.000000, -1.000000, 0.200000);
    SplinePushPoint (spline_35752, 0.460829, 0.000000, 0.539171);
    SplinePushPoint (spline_35752, 0.460829, 1.000000, 1.000000);
    SplinePushPoint (spline_34440, 0.000000, -0.700000, spline_35752);
    spline_36408 := SplineCreate (3);
    SplinePushPoint (spline_36408, 0.000000, -1.000000, 0.200000);
    SplinePushPoint (spline_36408, 0.460829, 0.000000, 0.539171);
    SplinePushPoint (spline_36408, 0.460829, 1.000000, 1.000000);
    SplinePushPoint (spline_34440, 0.000000, -0.400000, spline_36408);
    spline_37064 := SplineCreate (3);
    SplinePushPoint (spline_37064, 0.500000, -1.000000, -0.200000);
    SplinePushPoint (spline_37064, 0.000000, -0.400000, 0.500000);
    SplinePushPoint (spline_37064, 0.000000, 0.000000, 0.500000);
    SplinePushPoint (spline_37064, 0.000000, 0.400000, 0.500000);
    SplinePushPoint (spline_37064, 0.070000, 1.000000, 0.600000);
    SplinePushPoint (spline_34440, 0.000000, -0.350000, spline_37064);
    spline_37720 := SplineCreate (3);
    SplinePushPoint (spline_37720, 0.500000, -1.000000, -0.050000);
    SplinePushPoint (spline_37720, 0.100000, -0.400000, 0.010000);
    SplinePushPoint (spline_37720, 0.100000, 0.000000, 0.030000);
    SplinePushPoint (spline_37720, 0.940000, 0.400000, 0.500000);
    SplinePushPoint (spline_37720, 0.070000, 1.000000, 0.600000);
    SplinePushPoint (spline_34440, 0.000000, -0.100000, spline_37720);
    spline_38376 := SplineCreate (3);
    SplinePushPoint (spline_38376, 0.500000, -1.000000, -0.050000);
    SplinePushPoint (spline_38376, 0.000000, -0.400000, 0.010000);
    SplinePushPoint (spline_38376, 0.000000, 0.000000, 0.010000);
    SplinePushPoint (spline_38376, 0.040000, 0.400000, 0.030000);
    SplinePushPoint (spline_38376, 0.049000, 1.000000, 0.100000);
    SplinePushPoint (spline_34440, 0.000000, 0.200000, spline_38376);
    spline_39032 := SplineCreate (3);
    SplinePushPoint (spline_39032, 0.500000, -1.000000, -0.050000);
    SplinePushPoint (spline_39032, 0.000000, -0.400000, 0.010000);
    SplinePushPoint (spline_39032, 0.000000, 0.000000, 0.010000);
    SplinePushPoint (spline_39032, 0.040000, 0.400000, 0.030000);
    SplinePushPoint (spline_39032, 0.049000, 1.000000, 0.100000);
    SplinePushPoint (spline_34440, 0.000000, 0.400000, spline_39032);
    spline_39688 := SplineCreate (3);
    SplinePushPoint (spline_39688, 0.000000, -1.000000, -0.050000);
    spline_40344 := SplineCreate (3);
    SplinePushPoint (spline_40344, 0.500000, -1.000000, -0.050000);
    SplinePushPoint (spline_40344, 0.000000, -0.400000, 0.010000);
    SplinePushPoint (spline_40344, 0.000000, 0.000000, 0.010000);
    SplinePushPoint (spline_40344, 0.040000, 0.400000, 0.030000);
    SplinePushPoint (spline_40344, 0.049000, 1.000000, 0.100000);
    SplinePushPoint (spline_39688, 0.000000, -0.400000, spline_40344);
    SplinePushPoint (spline_39688, 0.000000, 0.000000, 0.170000);
    SplinePushPoint (spline_34440, 0.000000, 0.450000, spline_39688);
    spline_41000 := SplineCreate (3);
    SplinePushPoint (spline_41000, 0.000000, -1.000000, -0.050000);
    spline_41656 := SplineCreate (3);
    SplinePushPoint (spline_41656, 0.500000, -1.000000, -0.050000);
    SplinePushPoint (spline_41656, 0.000000, -0.400000, 0.010000);
    SplinePushPoint (spline_41656, 0.000000, 0.000000, 0.010000);
    SplinePushPoint (spline_41656, 0.040000, 0.400000, 0.030000);
    SplinePushPoint (spline_41656, 0.049000, 1.000000, 0.100000);
    SplinePushPoint (spline_41000, 0.000000, -0.400000, spline_41656);
    SplinePushPoint (spline_41000, 0.000000, 0.000000, 0.170000);
    SplinePushPoint (spline_34440, 0.000000, 0.550000, spline_41000);
    spline_42312 := SplineCreate (3);
    SplinePushPoint (spline_42312, 0.500000, -1.000000, -0.050000);
    SplinePushPoint (spline_42312, 0.000000, -0.400000, 0.010000);
    SplinePushPoint (spline_42312, 0.000000, 0.000000, 0.010000);
    SplinePushPoint (spline_42312, 0.040000, 0.400000, 0.030000);
    SplinePushPoint (spline_42312, 0.049000, 1.000000, 0.100000);
    SplinePushPoint (spline_34440, 0.000000, 0.580000, spline_42312);
    spline_42968 := SplineCreate (3);
    SplinePushPoint (spline_42968, 0.015000, -1.000000, -0.020000);
    SplinePushPoint (spline_42968, 0.000000, -0.400000, 0.010000);
    SplinePushPoint (spline_42968, 0.000000, 0.000000, 0.010000);
    SplinePushPoint (spline_42968, 0.040000, 0.400000, 0.030000);
    SplinePushPoint (spline_42968, 0.049000, 1.000000, 0.100000);
    SplinePushPoint (spline_34440, 0.000000, 0.700000, spline_42968);
    SplinePushPoint (spline_8856, 0.000000, 1.000000, spline_34440);

    params.spline_y_range = CalculateSplineRange (params.spline);
}

CalculateSplineRange :: (using spline : Spline) -> Vec2f
{
    y_range := Vec2f.{Math.FLOAT32_MAX, -Math.FLOAT32_MAX};

    pts := MakeArray (point_count, points.data);
    for pts
    {
        if it.nested_spline
        {
            nested_range := CalculateSplineRange (it.nested_spline);
            y_range.x = Min (y_range.x, nested_range.x);
            y_range.y = Max (y_range.y, nested_range.y);
        }
        else
        {
            y_range.x = Min (y_range.x, it.value);
            y_range.y = Max (y_range.y, it.value);
        }
    }

    return y_range;
}

GenerateNoiseOffsets :: (using generator : *Generator)
{
    rng : RNG;
    RandomSeed (*rng, seed);

    for noise_offsets
    {
        offsets := MakeArray (surface_params.noise_params[it_index].octaves, it.data);
        PerlinGenerateOffsets (*rng, offsets);
    }
}

GeneratorInit :: inline (generator : *Generator, seed : u64)
{
    Initialize (generator);

    generator.seed = seed;
    GenerateNoiseOffsets (generator);

    InitDefaultSurfaceSpline (*generator.surface_params);
}

GeneratorInit :: inline (generator : *Generator, seed : u64, surface_params : SurfaceParams)
{
    Initialize (generator);

    generator.seed = seed;
    GenerateNoiseOffsets (generator);

    generator.surface_params = surface_params;
    generator.spline = SplineClone (surface_params.spline);
}
