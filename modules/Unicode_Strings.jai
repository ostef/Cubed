Utf8String :: struct
{
    count : s64;
    data : *u8;

    #place count;
    as_string : string;
}

MakeUtf8String :: inline (str : string) -> Utf8String #must
{
    return .{str.count, str.data};
}

for_expansion :: (str : Utf8String, body : Code, flags : For_Flags) #expand
{
    Unicode :: #import "Unicode";

    `it_index := 0;
    byte_index := 0;
    while byte_index < str.count
    {
        `it, len := Unicode.character_utf8_to_utf32 (str.data + byte_index, str.count - byte_index);

        defer {
            it_index += 1;
            byte_index += len;
        }

        #insert body;
    }
}
