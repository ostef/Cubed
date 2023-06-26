MakeString :: inline (count : s64, data : *u8) -> string #must
{
    str : string = ---;
    str.count = count;
    str.data = data;

    return str;
}

MakeString :: inline (cstr : *u8) -> string #must
{
    return MakeString (StringLength (cstr), cstr);
}

StringFromArray :: inline (arr : []u8) -> string #must
{
    return MakeString (arr.count, arr.data);
}

StringToArray :: inline (str : string) -> []u8 #must
{
    return MakeArray (str.count, str.data);
}

StringLength :: inline (str : *u8) -> s64 #must
{
    i := 0;
    while str[i]
        i += 1;

    return i;
}

StringCompare :: inline (a : string, b : string) -> int #must
#no_abc
{
    if a.count < b.count
        return -cast (int) b[a.count - 1];

    if a.count > b.count
        return cast (int) a[b.count - 1];

    for i : 0..a.count - 1
    {
        cmp := cast (int) a[i] - cast (int) b[i];
        if cmp != 0
            return cmp;
    }

    return 0;
}

StringClone :: inline (str : string, allocator := context.allocator) -> string #must
{
    data := cast (*u8) Alloc (str.count, allocator);
    memcpy (data, str.data, str.count);

    return MakeString (str.count, data);
}

StringCloneToCString :: inline (str : string, allocator := context.allocator) -> *u8 #must
{
    data := cast (*u8) Alloc (str.count + 1, allocator);
    memcpy (data, str.data, str.count);
    data[str.count] = 0;

    return data;
}

StringStartsWith :: inline (str : string, with : string) -> bool #must
#no_abc
{
    if str.count < with.count
        return false;

    for i : 0..with.count - 1
    {
        if s[i] != with[i]
            return false;
    }

    return true;
}

StringEndsWith :: inline (str : string, with : string) -> bool #must
#no_abc
{
    if str.count < with.count
        return false;

    for i : 0..with.count - 1
    {
        if s[s.count - 1 - i] != with[with.count - 1 - i]
            return false;
    }

    return true;
}

StringFindFirst :: inline (s : string, needle : string) -> s64 #must
#no_abc
{
    for i : 0..s.count - 1
    {
        for j : 0..needle.count - 1
        {
            if s[i] == needle[j]
                return i;
        }
    }

    return -1;
}

StringFindLast :: inline (s : string, needle : string) -> s64 #must
#no_abc
{
    for < i : s.count - 1..0
    {
        for j : 0..needle.count - 1
        {
            if s[i] == needle[j]
                return i;
        }
    }

    return -1;
}

StringJoin :: (allocator : Allocator, args : ..string) -> string #must
#no_abc
{
    total_size := 0;
    for args
        total_size += it.count;

    if total_size == 0
        return "";

    data := cast (*u8) Alloc (total_size, allocator);

    i := 0;
    for args
    {
        memcpy (data + i, it.data, it.count);
        it += it.count;
    }

    return MakeString (total_size, data);
}

StringJoin :: inline (args : ..string) -> string #must
{
    return StringJoin (context.allocator, ..args);
}
