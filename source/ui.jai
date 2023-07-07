GenerateNoiseTexture :: (tex : *GLuint,
    width : s32, height : s32,
    seed : u64, params : NoiseParams
) -> min_val : float, max_val : float
{
    static_offsets : [Perlin_Fractal_Max_Octaves]Vec2f;
    min_non_normalized := Math.FLOAT32_MAX;
    max_non_normalized := -Math.FLOAT32_MAX;

    octaves := Clamp (params.octaves, 1, Perlin_Fractal_Max_Octaves);
    offsets := MakeArray (octaves, static_offsets.data);

    rng : RNG;
    RandomSeed (*rng, seed);
    PerlinGenerateOffsets (*rng, offsets);

    buffer := Alloc (u32, width * height, Temp);

    max_val := cast (float) PerlinFractalMax (params.octaves, params.persistance);
    for y : 0..height - 1
    {
        for x : 0..width - 1
        {
            val := cast (float) PerlinFractalNoise (params, offsets, xx x, xx y);
            if val < min_non_normalized
                min_non_normalized = val;
            if val > max_non_normalized
                max_non_normalized = val;
            val = InverseLerp (-max_val, max_val, val);

            buffer[y * height + x] = ImGui.GetColorU32 (.{val, val, val, 1});
        }
    }

    if !tex.*
        glGenTextures (1, tex);

    GL_Utils.StateBlock (GL_TEXTURE_BINDING_2D, (prev : GLuint) {glBindTexture (GL_TEXTURE_2D, prev);});

    glBindTexture (GL_TEXTURE_2D, tex.*);
    glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexImage2D (GL_TEXTURE_2D, 0, GL_RGBA, xx width, xx height, 0, GL_RGBA, GL_UNSIGNED_BYTE, buffer);

    return min_non_normalized, max_non_normalized;
}

#scope_file

g_ui_perlin : struct
{
    texture_handle : GLuint;
    texture_size : s32 = 256;
    seed : u64;
    params := NoiseParams.{
        scale = 0.05,
        octaves = 3,
        persistance = 0.5,
        lacunarity = 1.5
    };
    min_value := Math.FLOAT32_MAX;
    max_value := -Math.FLOAT32_MAX;
};

#scope_export

UIShowNoiseParams :: (id : ImGui.ID, params : *NoiseParams) -> bool
{
    ImGui.PushID (cast (s32) id);
    defer ImGui.PopID ();

    result := false;
    result |= ImGui.SliderFloat ("Scale", *params.scale, 0.001, 0.2, "%.6f");
    result |= ImGui.SliderInt ("Octaves", *params.octaves, 1, Perlin_Fractal_Max_Octaves);
    result |= ImGui.SliderFloat ("Persistance", *params.persistance, 0.001, 1);
    result |= ImGui.SliderFloat ("Lacunarity", *params.lacunarity, 1, 10);

    return result;
}

UIShowPerlinTestWindow :: (opened : *bool)
{
    using g_ui_perlin;

    defer ImGui.End ();
    if !ImGui.Begin ("Perlin Test", opened)
        return;

    lines := 8;
    child_height := cast (float) ImGui.GetContentRegionAvail ().y - lines * ImGui.GetFrameHeightWithSpacing ();
    if child_height > 0
    {
        if ImGui.BeginChild ("Image", .{0, child_height}, true, .HorizontalScrollbar)
        {
            if texture_handle
                ImGui.Image (cast (ImGui.ImTextureID) texture_handle, .{xx texture_size, xx texture_size});
        }
        ImGui.EndChild ();
    }

    should_generate := false;

    if !texture_handle
        should_generate = true;

    ImGui.LabelText ("Min Value", "%.3f", min_value);
    ImGui.LabelText ("Max Value", "%.3f", max_value);

    if ImGui.SliderInt ("Size", *texture_size, 128, 4096)
        should_generate = true;

    if UIShowNoiseParams (0, *params)
        should_generate = true;

    if ImGui.Button ("Generate")
        should_generate = true;

    ImGui.SameLine ();

    if ImGui.Button ("Randomize") || !texture_handle
    {
        seed = RandomGetU64 (*context.random_number_generator);
        should_generate = true;
    }

    if should_generate
        min_value, max_value = GenerateNoiseTexture (*texture_handle, texture_size, texture_size, seed, params);
}

#scope_file

SurfaceColor :: struct
{
    min : s32;
    max : s32;
    color : Vec3f;
}

Deep_Ocean_Color :: Vec4f.{0.102, 0.136, 0.388, 1};
Water_Color :: Vec4f.{0.154, 0.273, 0.878, 1};
Beach_Color :: Vec4f.{0.947, 0.880, 0.149, 1};
Grass_Color :: Vec4f.{0.387, 0.700, 0.250, 1};
High_Grass_Color :: Vec4f.{0.387, 0.900, 0.350, 1};
Mountain_Color :: Vec4f.{0.593, 0.689, 0.551, 1};
Snow_Color :: Vec4f.{0.914, 0.958, 1.000, 1};

#scope_export

GenerateTerrainTexture :: (tex : *GLuint, width : s32, height : s32, using generator : Generator, param : TerrainParam, show_surface_colors : bool)
{
    rng : RNG;
    RandomSeed (*rng, seed);

    buffer := Alloc (u32, width * height, Temp);

    for y : 0..height - 1
    {
        for x : 0..width - 1
        {
            val := cast (float) CalculateTerrainParam (generator, param, xx x, xx y);

            if param == .Surface_Height && show_surface_colors
            {
                surface_level := Lerp (cast (float) surface_params.surface_range.x, cast (float) surface_params.surface_range.y, val);
                color : u32;
                if surface_level < surface_params.surface_range.x + (surface_params.water_level - surface_params.surface_range.x) * 0.57
                    color = ImGui.GetColorU32 (Deep_Ocean_Color);
                else if surface_level < cast (float) surface_params.water_level
                    color = ImGui.GetColorU32 (Water_Color);
                else if surface_level < surface_params.water_level + (surface_params.surface_range.y - surface_params.water_level) * 0.03
                    color = ImGui.GetColorU32 (Beach_Color);
                else if surface_level < surface_params.water_level + (surface_params.surface_range.y - surface_params.water_level) * 0.4
                    color = ImGui.GetColorU32 (Grass_Color);
                else if surface_level < surface_params.water_level + (surface_params.surface_range.y - surface_params.water_level) * 0.47
                    color = ImGui.GetColorU32 (High_Grass_Color);
                else if surface_level < surface_params.water_level + (surface_params.surface_range.y - surface_params.water_level) * 0.65
                    color = ImGui.GetColorU32 (Mountain_Color);
                else
                    color = ImGui.GetColorU32 (Snow_Color);

                buffer[y * height + x] = color;
            }
            else
            {
                buffer[y * height + x] = ImGui.GetColorU32 (.{val, val, val, 1});
            }
        }
    }

    if !tex.*
        glGenTextures (1, tex);

    GL_Utils.StateBlock (GL_TEXTURE_BINDING_2D, (prev : GLuint) {glBindTexture (GL_TEXTURE_2D, prev);});

    glBindTexture (GL_TEXTURE_2D, tex.*);
    glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri (GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexImage2D (GL_TEXTURE_2D, 0, GL_RGBA, xx width, xx height, 0, GL_RGBA, GL_UNSIGNED_BYTE, buffer);
}

#scope_file

g_ui_terrain_generator : struct
{
    generator : Generator;
    texture_handle : GLuint;
    size : s32 = 1024;
    texture_size : s32 = 256;
    selected_param := TerrainParam.Surface_Height;
    show_surface_colors := true;
};

#scope_export

UIShowTerrainGeneratorWindow :: (opened : *bool)
{
    using g_ui_terrain_generator;

    if !generator.surface_params.spline
        InitDefaultSurfaceSpline (*generator.surface_params);

    defer ImGui.End ();
    if !ImGui.Begin ("Terrain Generator", opened)
        return;

    lines := 9;
    child_height := cast (float) ImGui.GetContentRegionAvail ().y - lines * ImGui.GetFrameHeightWithSpacing ();
    if child_height > 0
    {
        if ImGui.BeginChild ("Image", .{0, child_height}, true, .HorizontalScrollbar)
        {
            if texture_handle
                ImGui.Image (cast (ImGui.ImTextureID) texture_handle, .{xx texture_size, xx texture_size});
        }
        ImGui.EndChild ();
    }

    should_generate := false;

    if !texture_handle
        should_generate = true;

    ImGui.LabelText ("Seed", "%lld", generator.seed);
    ImGui.SliderInt ("Texture Size", *texture_size, 128, 4096);
    if ImGui.SliderInt ("Size", *size, 16, 4096)
        should_generate = true;

    if ImGui.SliderInt ("Water Level", *generator.surface_params.water_level, 0, 320)
        should_generate = true;

    terrain_param_names := Alloc (*u8, cast (s64) TerrainParam.Count, Temp);
    for i : 0..xx TerrainParam.Count - 1
        terrain_param_names[i] = StringCloneToCString (type_info (TerrainParam).names[i], Temp);

    selected_param_s32 := cast (s32) selected_param;

    if ImGui.Combo ("Param", *selected_param_s32, terrain_param_names, xx TerrainParam.Count)
        should_generate = true;

    selected_param = xx selected_param_s32;

    if selected_param < xx TerrainNoise.Count
    {
        if UIShowNoiseParams (0, *generator.surface_params.noise_params[xx selected_param])
            should_generate = true;
    }

    if selected_param == .Surface_Height
    {
        if ImGui.Checkbox ("Show Surface Colors", *show_surface_colors)
            should_generate = true;
    }

    if ImGui.Button ("Generate")
        should_generate = true;

    ImGui.SameLine ();

    if ImGui.Button ("Randomize") || !texture_handle
    {
        generator.seed = RandomGetU64 (*context.random_number_generator);
        should_generate = true;
    }

    if should_generate
    {
        GenerateNoiseOffsets (*generator);
        GenerateTerrainTexture (*texture_handle, size, size, generator, selected_param, show_surface_colors);
    }
}

g_ui_show_demo_window := false;
g_ui_show_perlin_test_window := false;
g_ui_show_terrain_generator_window := true;

UIUpdate :: ()
{
    if ImGui.BeginMainMenuBar ()
    {
        if ImGui.MenuItem ("Demo Window")
            g_ui_show_demo_window = true;
        if ImGui.MenuItem ("Perlin Test")
            g_ui_show_perlin_test_window = true;
        if ImGui.MenuItem ("Terrain Generator")
            g_ui_show_terrain_generator_window = true;

        ImGui.EndMainMenuBar ();
    }

    if g_ui_show_demo_window
        ImGui.ShowDemoWindow (*g_ui_show_demo_window);

    if g_ui_show_perlin_test_window
        UIShowPerlinTestWindow (*g_ui_show_perlin_test_window);

    if g_ui_show_terrain_generator_window
        UIShowTerrainGeneratorWindow (*g_ui_show_terrain_generator_window);
}
