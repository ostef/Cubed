#import "Common";
#import "Compiler";

build :: ()
{
    set_build_options_dc (.{do_output = false, write_added_strings = false});

    ws := compiler_create_workspace ("Cubed");

    options := get_build_options (ws);
    options.output_executable_name = "cubed";
    options.import_path = get_build_options ().import_path;
    options.Commonly_Propagated = get_build_options ().Commonly_Propagated;
    // options.enable_bytecode_inliner = false;
    options.stack_trace = true;

    set_build_options (options, ws);

    compiler_begin_intercept (ws);
    add_build_file ("main.jai", ws);

    while true
    {
        msg := compiler_wait_for_message ();
        if msg.kind == .COMPLETE
            break;
    }

    compiler_end_intercept (ws);
}

#run build ();
