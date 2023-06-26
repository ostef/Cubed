ArrayFree :: inline (arr : *[..]$T)
{
    Free (arr.data, arr.allocator);
    arr.data = null;
    arr.count = 0;
    arr.allocated = 0;
}

ArrayClear :: inline (arr : *[..]$T)
{
    arr.count = 0;
}

ArrayReserve :: (arr : *[..]$T, new_capacity : s64)
{
    if !arr.allocator.proc
        arr.allocator = context.allocator;

    if new_capacity <= arr.allocated
        return;

    new_data := cast (*T) Realloc (arr.data, new_capacity * size_of (T));
    arr.data = new_data;
    arr.allocated = new_capacity;
}

ArrayPush :: (arr : *[..]$T, $initialize := true) -> *T #must
{
    if arr.count >= arr.allocated
        ArrayReserve (arr, arr.allocated * 2 + 8);

    ptr := arr.data[arr.count];
    arr.count += 1;
    #if initialize
        Initialize (ptr);

    return ptr;
}

ArrayPush :: inline (arr : *[..]$T, elem : T) -> *T
{
    ptr := ArrayPush (arr, initialize = false);
    ptr.* = elem;

    return ptr;
}

ArrayPop :: inline (arr : *[..]$T)
{
    Assert (arr.count > 0, "Popping empty array");

    arr.count -= 1;
}

ArrayInsert :: (arr : *[..]$T, index : s64, $initialize := true) -> *T #must
{
    Assert (index >= 0 && index <= arr.count, "Index out of bounds (index is %, bounds are [0, %])", index, arr.count);

    if arr.count >= arr.allocated
        ArrayReserve (arr, arr.allocated * 2 + 8);

    arr.data[arr.count] = arr.data[index];
    arr.count += 1;

    ptr := *arr.data[index];
    #if initialize
        Initialize (ptr);

    return ptr;
}

ArrayInsert :: inline (arr : *[..]$T, index : s64, elem : T) -> *T
{
    ptr := ArrayInsert (arr, index, initialize = false);
    ptr.* = elem;

    return ptr;
}

ArrayRemove :: inline (arr : *[..]$T, index : s64)
{
    Assert (index >= 0 && index < arr.count, "Index out of bounds (index is %, bounds are [0, %])", index, arr.count - 1);

    arr.count -= 1;
    arr.data[index] = arr.data[arr.count];
}

ArrayOrderedInsert :: (arr : *[..]$T, index : s64, $initialize := true) -> *T #must
{
    Assert (index >= 0 && index <= arr.count, "Index out of bounds (index is %, bounds are [0, %])", index, arr.count);

    if arr.count >= arr.allocated
        ArrayReserve (arr, arr.allocated * 2 + 8);

    memcpy (arr.data + index + 1, arr.data + index, arr.count - index);
    arr.count += 1;

    ptr := *arr.data[index];
    #if initialize
        Initialize (ptr);

    return ptr;
}

ArrayOrderedInsert :: inline (arr : *[..]$T, index : s64, elem : T) -> *T
{
    ptr := ArrayOrderedInsert (arr, index, initialize = false);
    ptr.* = elem;

    return ptr;
}

ArrayOrderedRemove :: inline (arr : *[..]$T, index : s64)
{
    Assert (index >= 0 && index < arr.count, "Index out of bounds (index is %, bounds are [0, %])", index, arr.count - 1);

    memcpy (arr.data + index, arr.data + index + 1, arr.count - index - 1);
    arr.count -= 1;
}
