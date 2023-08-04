Enable_Profiling :: true;

Hash :: #import "Hash";

ProfilingEntriesMap :: HashMap (
    ProfilingKey, ProfilingData,
    hash_func = (key) => Hash.sdbm_hash (*key, size_of (ProfilingKey)),
    comp_func = (a, b) => a == b
);

#scope_file

g_global_profiling_data : ProfilingEntriesMap;
g_global_profiling_mutex : Threads.Mutex;

#scope_export

ProfilingKey :: struct
{
    location : Source_Code_Location;
    name : string;
}

operator== :: inline (a : ProfilingKey, b : ProfilingKey) -> bool #must
{
    return a.location.fully_pathed_filename == b.location.fully_pathed_filename
        && a.location.line_number == b.location.line_number
        && a.location.character_number == b.location.character_number
        && a.name == b.name;
}

ProfilingData :: struct
{
    using key : ProfilingKey;
    number_of_times_profiled : int;
    total_time : Basic.Apollo_Time;
}

ProfilingInit :: ()
{
    Threads.init (*g_global_profiling_mutex, "Global Profiling Data");
    HashMapInit (*g_global_profiling_data, 100);
}

LockGlobalProfilingData :: inline () -> *ProfilingEntriesMap #must
{
    Threads.lock (*g_global_profiling_mutex);

    return *g_global_profiling_data;
}

UnlockGlobalProfilingData :: inline ()
{
    Threads.unlock (*g_global_profiling_mutex);
}

AddGlobalProfilingData :: (entries : ProfilingEntriesMap)
{
    global_entries := LockGlobalProfilingData ();
    defer UnlockGlobalProfilingData ();

    for entries
    {
        ptr, is_new := HashMapInsert (global_entries, it_index);
        ptr.key = it_index;
        ptr.total_time += it.total_time;
        ptr.number_of_times_profiled += it.number_of_times_profiled;
    }
}

#add_context profiling_entries : ProfilingEntriesMap;

GetProfilingData :: inline (name : string, location : Source_Code_Location) -> *ProfilingData #must
{
    ptr, new := HashMapInsert (*context.profiling_entries, .{location, name});
    ptr.key = .{location, name};

    return ptr;
}

ProfileBlock :: (name := "", divide_by := 0, location := #caller_location) #expand
{
    #if Enable_Profiling
    {
        data := GetProfilingData (name, location);
        start_time := Basic.current_time_monotonic ();

        `defer {
            end_time := Basic.current_time_monotonic ();
            if divide_by > 0
                data.total_time += (end_time - start_time) / divide_by;
            else
                data.total_time += end_time - start_time;
            data.number_of_times_profiled += 1;
        };
    }
}

PrintProfilingData :: (builder : *StringBuilder, using data : ProfilingData)
{
    StringBuilderAppendLine (builder, "%\t%:%:%",
        name, location.fully_pathed_filename, location.line_number, location.character_number);

    avg_time_secs := Basic.to_float64_seconds (total_time / number_of_times_profiled);

    if avg_time_secs < 1 / (1000.0 * 1000.0)
        StringBuilderAppendLine (builder, "{:.3f} ns, profiled % times",
            avg_time_secs * 1000.0 * 1000.0 * 1000.0, number_of_times_profiled);
    else if avg_time_secs < 1 / 1000.0
        StringBuilderAppendLine (builder, "{:.3f} us, profiled % times",
            avg_time_secs * 1000.0 * 1000.0, number_of_times_profiled);
    else if avg_time_secs < 1
        StringBuilderAppendLine (builder, "{:.3f} ms, profiled % times",
            avg_time_secs * 1000.0, number_of_times_profiled);
    else
        StringBuilderAppendLine (builder, "{:.3f} s, profiled % times",
            avg_time_secs, number_of_times_profiled);
}

PrintProfilingData :: (builder : *StringBuilder, entries : ProfilingEntriesMap)
{
    Sort :: #import "Sort";

    sorted_entries : [..]ProfilingData;
    for entries
        ArrayPush (*sorted_entries, it);

    for Sort.quick_sort (sorted_entries, (a, b) => StringCompare (a.name, b.name))
    {
        PrintProfilingData (builder, it);
        StringBuilderAppend (builder, "\n");
    }
}
