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

    pp.original_filename = filename;
    pp.program_exports = program_exports;
    pp.allocator = allocator;
    pp.file_stack.allocator = allocator;
    pp.header_builder.allocator = allocator;
    pp.vertex_builder.allocator = allocator;
    pp.geometry_builder.allocator = allocator;
    pp.fragment_builder.allocator = allocator;
    pp.current_builder = *pp.header_builder;

    file_contents, ok := read_entire_file (filename, log_errors = false);
    if !ok
    {
        LogError ("Could not open file '%'", filename);
        return false;
    }

    AddFile (pp, filename, file_contents);

    return true;
}

AddFile :: inline (using pp : *ShaderPreprocessor, filename : string, file_contents : string)
{
    current_lexer = ArrayPush (*file_stack);
    current_lexer.name = filename;
    current_lexer.text = file_contents;
}

ShaderPreprocessorIsAtEnd :: (using pp : *ShaderPreprocessor) -> bool #must
{
    return file_stack.count == 0;
}

PreprocessShaderSource :: (using pp : *ShaderPreprocessor, source_allocator := context.allocator) -> bool, vertex : string, geometry : string, fragment : string
{
    AllocatorScope (allocator);

    while !ShaderPreprocessorIsAtEnd (pp)
    {
        if LexerIsAtEnd (pp)
        {
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
                SyntaxError (pp, "Duplicate #type_vertex directive");

            found_type_vertex = true;

            if file_stack.count > 1
                SyntaxError (pp, "#type directives are only allowed in top-level shaders");

            LexerAdvance (pp, "#type_vertex".count);

            current_builder = *vertex_builder;
            StringBuilderAppend (current_builder, header_builder);
            StringBuilderAppend (current_builder, "#line %", current_lexer.line + 1);
        }
        else if LexerEqualsAlphaNumeric (pp, "#type_geometry")
        {
            if found_type_geometry
                SyntaxError (pp, "Duplicate #type_geometry directive");

            found_type_geometry = true;

            if file_stack.count > 1
                SyntaxError (pp, "#type directives are only allowed in top-level shaders");

            LexerAdvance (pp, "#type_geometry".count);

            current_builder = *geometry_builder;
            StringBuilderAppend (current_builder, header_builder);
            StringBuilderAppend (current_builder, "#line %", current_lexer.line + 1);
        }
        else if LexerEqualsAlphaNumeric (pp, "#type_fragment")
        {
            if found_type_fragment
                SyntaxError (pp, "Duplicate #type_fragment directive");

            found_type_fragment = true;

            if file_stack.count > 1
                SyntaxError (pp, "#type directives are only allowed in top-level shaders");

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
            {
                SyntaxError (pp, "Expected a string for #include filename");

                continue;
            }

            filename = FormatString (Temp, "{}{}", String.path_strip_filename (current_lexer.name), filename);

            file_contents:, ok = read_entire_file (filename, log_errors = false);
            if !ok
                SyntaxError (pp, "Could not read file '%'", filename);

            AddFile (pp, filename, file_contents);
        }
        else if LexerMatchAlphaNumeric (pp, "#program_import")
        {
            LexerSkipWhitespacesAndComments (pp);

            import_name, ok := LexerScanQuotedString (pp, allocator = Temp);
            if !ok
            {
                SyntaxError (pp, "Expected a string for #program_import name");

                continue;
            }

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
            {
                SyntaxError (pp, "The program does not export '%'", import_name);
                continue;
            }

            StringBuilderAppend (current_builder, export.code);
        }
        else
        {
            StringBuilderAppendByte (current_builder, text[byte_index]);
            LexerAdvance (pp);
        }
    }

    if has_errors
        return false, "", "", "";

    return true,
        ifx found_type_vertex   then StringBuilderBuild (*vertex_builder,   allocator = source_allocator) else "",
        ifx found_type_geometry then StringBuilderBuild (*geometry_builder, allocator = source_allocator) else "",
        ifx found_type_fragment then StringBuilderBuild (*fragment_builder, allocator = source_allocator) else "";
}
