#import "Lexer";
String :: #import "String";

ShaderType :: enum
{
    Vertex;
    Geometry;
    Fragment;
}

ShaderProgramExport :: struct
{
    name : string;
    code : string;
}

ShaderPreprocessor :: struct
{
    original_filename : string;

    allocator : Allocator;
    file_stack : [..]Lexer;
    #as using, except (has_errors) current_lexer : *Lexer;
    has_errors : bool;
    program_exports : []ShaderProgramExport;

    found_type_vertex : bool;
    found_type_geometry : bool;
    found_type_fragment : bool;
    current_shader : ShaderType;

    header_builder : StringBuilder;
    vertex_builder : StringBuilder;
    geometry_builder : StringBuilder;
    fragment_builder : StringBuilder;
    current_builder : *StringBuilder;
}

InitShaderPreprocessor :: (pp : *ShaderPreprocessor, filename : string, program_exports : []ShaderProgramExport, allocator := context.allocator) -> bool
{
    AllocatorScope (allocator);

    pp.original_filename = get_absolute_path (filename);
    pp.program_exports = program_exports;
    pp.allocator = allocator;
    pp.file_stack.allocator = allocator;
    pp.header_builder.allocator = allocator;
    pp.vertex_builder.allocator = allocator;
    pp.geometry_builder.allocator = allocator;
    pp.fragment_builder.allocator = allocator;
    pp.current_builder = *pp.header_builder;

    file_contents, ok := read_entire_file (pp.original_filename, log_errors = false);
    if !ok
    {
        LogError ("Could not open file '%'", filename);
        return false;
    }

    return AddFile (pp, pp.original_filename, file_contents);
}

FreeShaderPreprocessor :: (using pp : *ShaderPreprocessor)
{
    AllocatorScope (allocator);

    for * pp.file_stack
    {
        Free (it.text.data);
        Free (it.filename.data);
    }

    ArrayFree (*pp.file_stack);
    StringBuilderFree (*pp.header_builder);
    StringBuilderFree (*pp.vertex_builder);
    StringBuilderFree (*pp.geometry_builder);
    StringBuilderFree (*pp.fragment_builder);
}

AddFile :: inline (pp : *ShaderPreprocessor, filename : string, file_contents : string) -> bool #must
{
    for pp.file_stack
    {
        if filename == it.name
            return false;
    }

    pp.current_lexer = ArrayPush (*pp.file_stack);
    pp.current_lexer.name = filename;
    pp.current_lexer.text = file_contents;

    return true;
}

ShaderPreprocessorIsAtEnd :: (using pp : *ShaderPreprocessor) -> bool #must
{
    return !current_lexer && file_stack.count == 0;
}

PreprocessShaderSource :: (using pp : *ShaderPreprocessor, source_allocator := context.allocator) -> bool, vertex : string, geometry : string, fragment : string
{
    Error :: (pp : ShaderPreprocessor, fmt_str : string, args : ..Any) #expand
    {
        msg := FormatString (Temp, fmt_str, ..args);
        LogError ("%:%:%, Error: %", name, line, column, msg);

        `return false, "", "", "";
    }

    AllocatorScope (allocator);

    while !ShaderPreprocessorIsAtEnd (pp)
    {
        if LexerIsAtEnd (pp)
        {
            Free (filename.data);
            Free (text.data);
            ArrayPop (*file_stack);

            if file_stack.count == 0
            {
                has_errors |= current_lexer.has_errors;
                current_lexer = null;

                break;
            }

            current_lexer = *file_stack[file_stack.count - 1];
            continue;
        }

        if LexerEqualsAlphaNumeric (pp, "#type_vertex")
        {
            if found_type_vertex
                Error (pp, "Duplicate #type_vertex directive");

            found_type_vertex = true;

            if file_stack.count > 1
                Error (pp, "#type directives are only allowed in top-level shaders");

            LexerAdvance (pp, "#type_vertex".count);

            current_builder = *vertex_builder;
            StringBuilderAppend (current_builder, header_builder);
            StringBuilderAppend (current_builder, "#line %", current_lexer.line + 1);
        }
        else if LexerEqualsAlphaNumeric (pp, "#type_geometry")
        {
            if found_type_geometry
                Error (pp, "Duplicate #type_geometry directive");

            found_type_geometry = true;

            if file_stack.count > 1
                Error (pp, "#type directives are only allowed in top-level shaders");

            LexerAdvance (pp, "#type_geometry".count);

            current_builder = *geometry_builder;
            StringBuilderAppend (current_builder, header_builder);
            StringBuilderAppend (current_builder, "#line %", current_lexer.line + 1);
        }
        else if LexerEqualsAlphaNumeric (pp, "#type_fragment")
        {
            if found_type_fragment
                Error (pp, "Duplicate #type_fragment directive");

            found_type_fragment = true;

            if file_stack.count > 1
                Error (pp, "#type directives are only allowed in top-level shaders");

            LexerAdvance (pp, "#type_fragment".count);

            current_builder = *fragment_builder;
            StringBuilderAppend (current_builder, header_builder);
            StringBuilderAppend (current_builder, "#line %", current_lexer.line + 1);
        }
        else if LexerMatchAlphaNumeric (pp, "#include")
        {
            LexerSkipWhitespacesAndComments (pp);

            filename, ok := LexerScanQuotedString (pp, allocator = Temp);
            if !ok
                Error (pp, "Expected a string for #include filename");

            filename = FormatString (Temp, "{}{}", String.path_strip_filename (current_lexer.name), filename);
            filename = get_absolute_path (filename);

            file_contents:, ok = read_entire_file (filename, log_errors = false);

            if !AddFile (pp, filename, file_contents)
            {
                Free (file_contents.data);
                Error (pp, "Circular include detected of file '%'", filename);
            }

            if !ok
                Error (pp, "Could not read file '%'", filename);
        }
        else if LexerMatchAlphaNumeric (pp, "#program_import")
        {
            LexerSkipWhitespacesAndComments (pp);

            import_name, ok := LexerScanQuotedString (pp, allocator = Temp);
            if !ok
                Error (pp, "Expected a string for #program_import name");

            export : *ShaderProgramExport;
            for * program_exports
            {
                if it.name == import_name
                {
                    export = it;
                    break;
                }
            }

            if !export
                Error (pp, "The program does not export '%'", import_name);

            StringBuilderAppend (current_builder, export.code);
        }
        else
        {
            StringBuilderAppendByte (current_builder, text[byte_index]);
            LexerAdvance (pp);
        }
    }

    return true,
        ifx found_type_vertex   then StringBuilderBuild (*vertex_builder,   allocator = source_allocator) else "",
        ifx found_type_geometry then StringBuilderBuild (*geometry_builder, allocator = source_allocator) else "",
        ifx found_type_fragment then StringBuilderBuild (*fragment_builder, allocator = source_allocator) else "";
}
