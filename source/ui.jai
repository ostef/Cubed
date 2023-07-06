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
        min_value, max_value = GenerateNoiseTexture (
            *texture_handle,
            texture_size,
            texture_size,
            seed,
            params
        );
}

g_ui_show_demo_window := false;
g_ui_show_perlin_test_window := false;

UIUpdate :: ()
{
    if ImGui.BeginMainMenuBar ()
    {
        if ImGui.MenuItem ("Demo Window")
            g_ui_show_demo_window = true;
        if ImGui.MenuItem ("Perlin Test")
            g_ui_show_perlin_test_window = true;

        ImGui.EndMainMenuBar ();
    }

    if g_ui_show_demo_window
        ImGui.ShowDemoWindow (*g_ui_show_demo_window);

    if g_ui_show_perlin_test_window
        UIShowPerlinTestWindow (*g_ui_show_perlin_test_window);
}
