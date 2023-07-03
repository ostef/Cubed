#module_parameters () (Enable_Asserts := true);

#scope_module

fmt :: #import "Fmt";

#scope_export

FormatString :: fmt.format;
Print :: fmt.print;
Println :: fmt.println;

#load "memory.jai";
#load "array.jai";
#load "string.jai";
#load "logging.jai";

Assert :: (assertion : bool, fmt_str := "", args : ..Any, location := #caller_location) #expand
{
    #if Enable_Asserts
    {
        if !assertion
        {
            if context.handling_assertion_failure
                return;

            context.handling_assertion_failure = true;
            message := FormatString (fmt_str, ..args);
            context.assertion_failed (location, message);
            context.handling_assertion_failure = false;
        }
    }
}

Panic :: (fmt_str := "", args : ..Any, location := #caller_location) #expand
{
    if context.handling_assertion_failure
        return;

    context.handling_assertion_failure = true;
    message := FormatString (fmt_str, ..args);
    context.assertion_failed (location, message);
    context.handling_assertion_failure = false;
}

Initialize :: inline (item : *$T)
{
    initializer :: initializer_of (T);
    #if initializer
        initializer (item);
    else
        memset (item, 0, size_of (T));
}

Initialize :: inline (item : *$T, count : s64)
{
    initializer :: initializer_of (T);
    #if initializer
    {
        for i : 0..count - 1
            initializer (item + i);
    }
    else
    {
        memset (item, 0, size_of (T) * count);
    }
}

DefaultValue :: ($T : Type) #expand
{
    val : T;

    return val;
}

#scope_file

IsNumeric :: inline (type : Type) -> bool
{
    info := cast (*Type_Info) type;

    return info.type == .INTEGER || info.type == .FLOAT;
}

#scope_export

Min :: (a : $T, b : T) -> T #must #expand
#modify { return IsNumeric (T); }
{
    return ifx a < b then a else b;
}

Max :: (a : $T, b : T) -> T #must #expand
#modify { return IsNumeric (T); }
{
    return ifx a > b then a else b;
}

Clamp :: (x : $T, min : T, max : T) -> T #must #expand
#modify { return IsNumeric (T); }
{
    return Min (Max (x, min), max);
}

Saturate :: (x : $T) -> T #must #expand
#modify { return IsNumeric (T); }
{
    return Clamp (x, 0, 1);
}
