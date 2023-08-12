#import "Common";

StringBuilder :: struct (Buffer_Size := 1000)
{
    Page :: struct
    {
        count : s64;
        next : *Page;
        data : [Buffer_Size]u8 = ---;
    }

    write_byte :: (builder : *StringBuilder (Buffer_Size), byte : u8)
    {
        if builder && byte
            StringBuilderAppendByte (builder, byte);
    }

    page : *Page;
    count : s64;
    allocator : Allocator;
    base_page : Page;
}

#scope_module

EnsureInit :: inline (using builder : *StringBuilder)
{
    if !page
    {
        allocator = context.allocator;
        page = *base_page;
    }
}

#scope_export

StringBuilderFree :: (using builder : *StringBuilder)
{
    curr := base_page.next;
    while curr
    {
        next := curr.next;
        Free (curr, allocator);
        curr = next;
    }

    page = *base_page;
    base_page.next = null;
    base_page.count = 0;
    count = 0;
}

StringBuilderClear :: (using builder : *StringBuilder)
{
    base_page.count = 0;
    curr := base_page.next;
    while curr
    {
        curr.count = 0;
        curr = curr.next;
    }

    count = 0;
    page = *base_page;
}

StringBuilderBuild :: (builder : *StringBuilder, reset_builder := true, allocator := context.allocator) -> string #must
{
    EnsureInit (builder);

    defer if reset_builder then StringBuilderFree (builder);

    result : string = ---;
    result.data = Alloc (builder.count, allocator);
    result.count = builder.count;

    i := 0;
    page := *builder.base_page;
    while page && page.count > 0
    {
        memcpy (result.data + i, page.data.data, page.count);
        i += page.count;
        page = page.next;
    }

    return result;
}

StringBuilderBuildCstr :: (builder : *StringBuilder, reset_builder := true, allocator := context.allocator) -> *u8 #must, len : s64
{
    EnsureInit (builder);

    defer if reset_builder then StringBuilderFree (builder);

    result := cast (*u8) Alloc (builder.count + 1, allocator);

    i := 0;
    page := *builder.base_page;
    while page && page.count > 0
    {
        memcpy (result + i, page.data.data, page.count);
        i += page.count;
        page = page.next;
    }

    result[i] = 0;

    return result;
}

StringBuilderAppend :: (using builder : *StringBuilder, buff : *void, size : s64) -> s64
{
    EnsureInit (builder);

    written := 0;
    while written != size
    {
        if page.count == Buffer_Size
        {
            if !page.next
            {
                next := Alloc (Page, allocator);
                page.next = next;
            }

            page = page.next;
        }

        to_write := Min (Buffer_Size - page.count, size - written);

        memcpy (page.data.data + page.count, buff + written, to_write);

        page.count += to_write;
        written += to_write;
    }

    count += written;

    return written;
}

StringBuilderAppend :: inline (using builder : *StringBuilder, str : string) -> s64
{
    return StringBuilderAppend (builder, str.data, str.count);
}

StringBuilderAppendByte :: inline (using builder : *StringBuilder, byte : u8) -> s64
{
    return StringBuilderAppend (builder, *byte, 1);
}

StringBuilderAppendBool :: inline (using builder : *StringBuilder, val : bool) -> s64
{
    #import "String_Convert";

    buff : [6]u8 = ---;
    str := AppendBool (buff, val);

    return StringBuilderAppend (builder, str);
}

StringBuilderAppendU64 :: inline (using builder : *StringBuilder, val : u64, $$base := "0123456789") -> s64
{
    #import "String_Convert";

    buff : [65]u8 = ---;
    str := AppendU64 (buff, val, base);

    return StringBuilderAppend (builder, str);
}

StringBuilderAppendS64 :: inline (using builder : *StringBuilder, val : s64, $$base := "0123456789") -> s64
{
    #import "String_Convert";

    buff : [65]u8 = ---;
    str := AppendS64 (buff, val, base);

    return StringBuilderAppend (builder, str);
}

StringBuilderAppendFloat :: inline (using builder : *StringBuilder, val : float64, precision : u32 = 6) -> s64
{
    ryu :: #import "Ryu";

    if precision > 16
        precision = 16;

    ryu_fmt : ryu.Format;
    ryu_fmt.precision = precision;
    ryu_fmt.flags |= .REMOVE_TRAILING_ZEROES;
    temp_buffer : [500]u8 = ---;

    len := ryu.f64_to_fixed_buffered (val, ryu_fmt, temp_buffer.data);
    str := MakeString (len, temp_buffer.data);

    return StringBuilderAppend (builder, str);
}

StringBuilderAppend :: inline (using builder : *StringBuilder, fmt_str : string, args : ..Any) -> s64
{
    fmt :: #import "Fmt";

    return fmt.format (builder, fmt_str, ..args);
}

StringBuilderAppendLine :: inline (using builder : *StringBuilder, fmt_str : string, args : ..Any) -> s64
{
    fmt :: #import "Fmt";

    n := fmt.format (builder, fmt_str, ..args);
    n += StringBuilderAppend (builder, "\n");

    return n;
}

StringBuilderIsContiguous :: inline (using builder : *StringBuilder) -> bool #must
{
    return count < Buffer_Size;
}
