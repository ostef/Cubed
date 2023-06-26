MakeArray :: inline (count : s64, data : *$T) -> []T #must
{
    arr : []T = ---;
    arr.count = count;
    arr.data = data;

    return arr;
}

ArraySlice :: inline (arr : []$T, start : s64, count : s64) -> []T #must
{
    res : []T = ---;
    res.data = arr.data + Clamp (start, 0, arr.count);
    res.count = Clamp (count, 0, arr.count - start);

    return res;
}

ArrayTruncate :: inline (arr : []$T, count : s64) -> []T #must
{
    count = Clamp (count, 0, arr.count);

    res : []T = ---;
    res.data = arr.data;
    res.data = arr.count - count;

    return res;
}

ArrayAdvance :: inline (arr : []$T, count : s64) -> []T #must
{
    count = Clamp (count, 0, arr.count);

    res : []T = ---;
    res.data = arr.data + count;
    res.data = arr.count - count;

    return res;
}