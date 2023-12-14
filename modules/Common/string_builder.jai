StringBuilder :: Basic.String_Builder;

StringBuilderFree :: inline (builder : *StringBuilder)
{
    Basic.reset (builder);
}

StringBuilderLength :: inline (builder : *StringBuilder) -> s64 #must
{
    return Basic.builder_string_length (builder);
}

StringBuilderBuild :: inline (builder : *StringBuilder, allocator := context.allocator, reset_builder := true) -> string #must
{
    return Basic.builder_to_string (builder, allocator = allocator, do_reset = reset_builder);
}

StringBuilderBuildCstr :: (builder : *StringBuilder, allocator := context.allocator, reset_builder := true) -> *u8 #must
{
    if !builder.initialized
        Basic.init_string_builder (builder);

    count := StringBuilderLength (builder);
    result := Alloc (u8, count + 1, allocator);
    data := result;

    buffer := Basic.get_base_buffer (builder);
    while buffer
    {
        memcpy (data, Basic.get_buffer_data (buffer), buffer.count);
        data += buffer.count;

        next := buffer.next;

        if reset_builder && buffer != Basic.get_base_buffer (builder)
            Free (buffer, builder.allocator);

        buffer = next;
    }

    data.* = 0;

    return result;
}

StringBuilderWrite :: inline (builder : *StringBuilder, do_reset := true, to_standard_error := false) -> s64
{
    return Basic.write_builder (builder, do_reset, to_standard_error);
}

StringBuilderAppend :: inline (builder : *StringBuilder, format_string : string, args : ..Any)
{
    Basic.print_to_builder (builder, format_string, ..args);
}
@PrintLike

StringBuilderAppendLine :: inline (builder : *StringBuilder, format_string : string, args : ..Any)
{
    Basic.print_to_builder (builder, format_string, ..args);
    Basic.append (builder, "\n");
}
@PrintLike

StringBuilderAppendString :: inline (builder : *StringBuilder, str : string)
{
    Basic.append (builder, str);
}

StringBuilderAppendByte :: inline (builder : *StringBuilder, byte : u8)
{
    Basic.append (builder, byte);
}

StringBuilderAppendBuilder :: (builder : *StringBuilder, other : *StringBuilder)
{
    buffer := Basic.get_base_buffer (other);
    while buffer
    {
        str := MakeString (buffer.count, Basic.get_buffer_data (buffer));
        StringBuilderAppendString (builder, str);

        buffer = buffer.next;
    }
}
