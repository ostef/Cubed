#import "Common";

#scope_module

ryu :: #import "Ryu";

#scope_export

StringConvertResult :: enum
{
    Ok;

    Buffer_Too_Small;
    Malformed_Input;
    Overflow;
    Underflow;
}

#scope_module

Result :: StringConvertResult;

#scope_export

Base_Binary            :: "01";
Base_Octal             :: "01234567";
Base_Decimal           :: "0123456789";
Base_Hexadecimal       :: "0123456789abcdef";
Base_Hexadecimal_Upper :: "0123456789ABCDEF";

AppendBool :: inline (buff : []u8, val : bool) -> string, written : s64, Result
{
    if buff.count <= 0
        return "", 0, .Buffer_Too_Small;

    str := ifx val then "true" else "false";
    n := Min (buff.count, str.count);
    memcpy (buff.data, str.data, n);
    res := ifx n < str.count then .Buffer_Too_Small else .Ok;

    return StringFromArray (ArraySlice (buff, n)), n, res;
}

AppendU64 :: (buff : []u8, val : u64, $$base := Base_Decimal) -> string, written : s64, Result
#no_abc
{
    if buff.count <= 0
        return "", 0, .Buffer_Too_Small;

    res : Result;
    n := 0;
    tmp := val;

    while tmp > 0 || n == 0
    {
        tmp /= cast (u64) base.count;
        n += 1;
    }

    if buff.count < n
        res = .Buffer_Too_Small;

    for < i : n - 1..0
    {
        if i < buff.count
            buff[i] = base[val % cast (u64) base.count];

        val /= cast (u64) base.count;
    }

    return StringFromArray (ArraySlice (buff, n)), n, res);
}

AppendS64 :: (buff : []u8, val : s64, $$base := Base_Decimal) -> string, written : s64, Result
#no_abc
{
    if buff.count == 0
        return "", 0, .Buffer_Too_Small;

    uval : u64 = ---;
    n := 0;

    if val < 0
    {
        buff[n] = #char "-";
        uval = cast, no_check (u64) -val;
        n += 1;
    }
    else
    {
        uval = cast, no_check (u64) val;
    }

    _, un, res := AppendU64 (ArrayAdvance (buff, n), uval, base);

    return StringFromArray (ArraySlice (buff, n + un)), n + un, res;
}

AppendFloat :: inline (buff : []u8, val : float64, precision : u32 = 6) -> string, written : s64, Result
#no_abc
{
    if buff.count <= 0
        return "", 0, .Buffer_Too_Small;

    if precision > 16
        precision = 16;

    ryu_fmt : ryu.Format;
    ryu_fmt.precision = precision;
    ryu_fmt.flags |= .REMOVE_TRAILING_ZEROES;
    temp_buffer : [500]u8 = ---;

    len := ryu.f64_to_fixed_buffered (val, ryu_fmt, temp_buffer.data);
    n := Min (buff.count, len);
    memcpy (buff.data, temp_buffer.data, n);

    res := ifx n < len then .Buffer_Too_Small else .Ok;

    return StringFromArray (ArraySlice (buff, n)), n, res;
}

ParseBool :: inline
