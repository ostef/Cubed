#import "Common";
Fenetres :: #import "Fenetres";
Fenetres_GL :: #import "Fenetres/GL";
Windows_Utils :: #import "Windows_Utils";
#import "GL";
Stylo :: #import "Stylo";

main :: ()
{
    window := Fenetres.CreateWindow ("Test", 1280, 720, 100, 100);

    window1 := Fenetres.CreateWindow ("Test 1", 640, 480, flags = .Borderless);
    window2 := Fenetres.CreateWindow ("Test 2", 640, 480);
    window3 := Fenetres.CreateWindow ("Test 3", 640, 480);

    gl_context := Fenetres_GL.CreateContext (window);
    Assert (gl_context != null, Windows_Utils.GetLastErrorString ());
    defer Fenetres_GL.DestroyContext (gl_context);

    gl_context1 := Fenetres_GL.CreateContext (window1);
    gl_context2 := Fenetres_GL.CreateContext (window2);
    gl_context3 := Fenetres_GL.CreateContext (window3);

    Fenetres_GL.MakeCurrent (window, gl_context);

    gl_load (*gl, Fenetres_GL.GetProcAddress);

    quit := false;
    while !quit
    {
        for Fenetres.PollMessages ()
        {
            if it.kind == .Mouse_Moved || it.kind == .Window_Moved || it.kind == .Window_Resized
                continue;

            Println (it);

            if it.kind == .Window_Closed
            {
                if it.window == window
                    quit = true;

                Fenetres.DestroyWindow (it.window);
            }
        }

        {
            w, h := Fenetres.GetViewportSize (window);

            Fenetres_GL.MakeCurrent (window, gl_context);

            glViewport (0, 0, xx w, xx h);
            glClearColor (1, 0, 0, 1);
            glClear (GL_COLOR_BUFFER_BIT);

            Fenetres.SwapBuffers (window);
        }

        {
            w, h := Fenetres.GetViewportSize (window1);

            Fenetres_GL.MakeCurrent (window1, gl_context1);

            glViewport (0, 0, xx w, xx h);
            glClearColor (0, 1, 0, 1);
            glClear (GL_COLOR_BUFFER_BIT);

            Fenetres.SwapBuffers (window1);
        }

        {
            w, h := Fenetres.GetViewportSize (window2);

            Fenetres_GL.MakeCurrent (window2, gl_context2);

            glViewport (0, 0, xx w, xx h);
            glClearColor (0, 0, 1, 1);
            glClear (GL_COLOR_BUFFER_BIT);

            Fenetres.SwapBuffers (window2);
        }

        {
            w, h := Fenetres.GetViewportSize (window3);

            Fenetres_GL.MakeCurrent (window3, gl_context3);

            glViewport (0, 0, xx w, xx h);
            glClearColor (0.3, 0.3, 0.3, 1);
            glClear (GL_COLOR_BUFFER_BIT);

            Fenetres.SwapBuffers (window3);
        }
    }
}
