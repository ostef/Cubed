#import "Common";

#scope_file

Win32 :: #import "Win32";
Windows_Utils :: #import "Windows_Utils";

g_all_windows : [..]*Window;
g_wndclass : Win32.WNDCLASSEXW;
g_custom_caption_wndclass : Win32.WNDCLASSEXW;
g_cursors : struct
{
    all : [SystemCursor.Count]Win32.HCURSOR;

    #place all;
    arrow : Win32.HCURSOR;
    arrow_busy : Win32.HCURSOR;
    busy : Win32.HCURSOR;
    cross : Win32.HCURSOR;
    hand : Win32.HCURSOR;
    ibeam : Win32.HCURSOR;
    size : Win32.HCURSOR;
    size_nwse : Win32.HCURSOR;
    size_nesw : Win32.HCURSOR;
    size_horizontal : Win32.HCURSOR;
    size_vertical : Win32.HCURSOR;
    not_allowed : Win32.HCURSOR;
};

g_message_queue : [..]Message;

g_initialized : bool;

InitializeWindowClassesAndCursors :: ()
{
    {
        using g_wndclass;

        cbSize        = size_of (Win32.WNDCLASSEXW);
        style         = Win32.CS_DBLCLKS | Win32.CS_OWNDC;
        lpfnWndProc   = xx WindowProc;
        hInstance     = Win32.GetModuleHandleW (null);
        lpszClassName = Windows_Utils.Utf8ToWide ("WindowClass");
        if !Win32.RegisterClassExW (*g_wndclass)
            ShowErrorBox ("RegisterClassExW for WindowClass failed: %", Windows_Utils.GetLastErrorString ());
    }
    {
        using g_custom_caption_wndclass;

        cbSize        = size_of (Win32.WNDCLASSEXW);
        style         = Win32.CS_DBLCLKS | Win32.CS_OWNDC;
        lpfnWndProc   = xx CustomCaptionWindowProc;
        hInstance     = Win32.GetModuleHandleW (null);
        lpszClassName = Windows_Utils.Utf8ToWide ("CustomCaptionWindowClass");
        if !Win32.RegisterClassExW (*g_custom_caption_wndclass)
            ShowErrorBox ("RegisterClassExW for CustomCaptionWindowClass failed: %", Windows_Utils.GetLastErrorString ());
    }
    {
        g_cursors.arrow = Win32.LoadCursorW (null, cast (*u16) Win32.IDC_ARROW);
        g_cursors.arrow_busy = Win32.LoadCursorW (null, cast (*u16) Win32.IDC_APPSTARTING);
        g_cursors.busy = Win32.LoadCursorW (null, cast (*u16) Win32.IDC_WAIT);
        g_cursors.cross = Win32.LoadCursorW (null, cast (*u16) Win32.IDC_CROSS);
        g_cursors.hand = Win32.LoadCursorW (null, cast (*u16) Win32.IDC_HAND);
        g_cursors.ibeam = Win32.LoadCursorW (null, cast (*u16) Win32.IDC_IBEAM);
        g_cursors.size = Win32.LoadCursorW (null, cast (*u16) Win32.IDC_SIZEALL);
        g_cursors.size_nwse = Win32.LoadCursorW (null, cast (*u16) Win32.IDC_SIZENWSE);
        g_cursors.size_nesw = Win32.LoadCursorW (null, cast (*u16) Win32.IDC_SIZENESW);
        g_cursors.size_horizontal = Win32.LoadCursorW (null, cast (*u16) Win32.IDC_SIZEWE);
        g_cursors.size_vertical = Win32.LoadCursorW (null, cast (*u16) Win32.IDC_SIZENS);
        g_cursors.not_allowed = Win32.LoadCursorW (null, cast (*u16) Win32.IDC_NO);
    }

    g_initialized = true;
}

#scope_export

CaptionHitTestProc :: #type (*Window, mouse_x : s32, mouse_y : s32) -> on_caption : bool;

Window :: struct
{
    hwnd : Win32.HWND;
    flags : WindowFlags;
    WM_CHAR_utf16_high_surrogate : u16;
    caption_hit_test : CaptionHitTestProc;
    mouse_is_outside : bool;
}

GetPlatformHandle :: inline (window : *Window) -> *void #must #no_context
{
    return window.hwnd;
}

GetWindowFromPlatformHandle :: inline (hwnd : Win32.HWND) -> *Window #must #no_context
{
    for g_all_windows
    {
        if it.hwnd == hwnd
            return it;
    }

    return null;
}

ShowErrorBox :: inline (parent : *Window, fmt_str : string, args : ..Any)
{
    TemporaryStorageScope ();

    str := FormatString (Temp, fmt_str, ..args);
    Win32.MessageBoxW (
        ifx parent then parent.hwnd else null,
        Windows_Utils.Utf8ToWide (str, Temp),
        null,
        Win32.MB_ICONERROR | Win32.MB_OK
    );
}

ShowErrorBox :: inline (fmt_str : string, args : ..Any)
{
    ShowErrorBox (null, fmt_str, ..args);
}

DisplayInfo :: struct
{
    is_primary : bool;
    x, y, w, h : s32;
    dpi : s32;
}

GetDisplays :: inline (allocator := context.allocator) -> []DisplayInfo #must
{
    CountDisplayMonitors :: (
        monitor : Win32.HMONITOR,
        device_context : Win32.HDC,
        rect : *Win32.RECT,
        user_data : *void
    ) -> Win32.BOOL #c_call
    {
        (cast (*s64) user_data).* += 1;
        return 1;
    }

    UserData :: struct
    {
        displays : []DisplayInfo;
        index : s64;
    }

    AddDisplay :: (
        monitor : Win32.HMONITOR,
        device_context : Win32.HDC,
        rect : *Win32.RECT,
        user_data : *void
    ) -> Win32.BOOL #c_call
    {
        monitor_info : Win32.MONITORINFO;
        monitor_info.cbSize = size_of (Win32.MONITORINFO);
        Win32.GetMonitorInfoW (monitor, *monitor_info);

        using data := (cast (*UserData) user_data);
        if index >= displays.count
            return 0;

        displays[index].is_primary = (monitor_info.dwFlags & Win32.MONITORINFOF_PRIMARY) == Win32.MONITORINFOF_PRIMARY;
        displays[index].x = monitor_info.rcMonitor.left;
        displays[index].y = monitor_info.rcMonitor.top;
        displays[index].w = monitor_info.rcMonitor.right - monitor_info.rcMonitor.left;
        displays[index].h = monitor_info.rcMonitor.bottom - monitor_info.rcMonitor.top;

        // https://learn.microsoft.com/en-us/windows/win32/api/shellscalingapi/nf-shellscalingapi-getdpiformonitor
        // "The values of *dpiX and *dpiY are identical. You only need to record
        // one of the values to determine the DPI and respond appropriately."
        dpi_x : u32;
        if Win32.GetDpiForMonitor (monitor, Win32.MDT_EFFECTIVE_DPI, *dpi_x, null) == Win32.ERROR_SUCCESS
            displays[index].dpi = xx dpi_x;
        else
            displays[index].dpi = 96;

        index += 1;

        return 1;
    }

    count := 0;
    Win32.EnumDisplayMonitors (null, null, CountDisplayMonitors, *count);

    user_data : UserData;
    user_data.displays = AllocArray (DisplayInfo, count, allocator);
    Win32.EnumDisplayMonitors (null, null, AddDisplay, *user_data);

    return user_data.displays;
}

CreateWindowExtraParams :: struct
{
    caption_hit_test : CaptionHitTestProc;
}

CreateWindow :: (
    title : string,
    width : s32, height : s32,
    x : s32 = Window_Default_Pos, y : s32 = Window_Default_Pos,
    flags : WindowFlags = 0,
    parent : *Window = null,
    extra : CreateWindowExtraParams = .{}
) -> *Window #must
{
    if !g_initialized
        InitializeWindowClassesAndCursors ();

    if x == Window_Default_Pos
        x = Win32.CW_USEDEFAULT;
    if y == Window_Default_Pos
        y = Win32.CW_USEDEFAULT;
    if width == Window_Default_Size
        width = Win32.CW_USEDEFAULT;
    if height == Window_Default_Size
        height = Win32.CW_USEDEFAULT;

    wndclass := ifx flags & .Custom_Caption then *g_custom_caption_wndclass else *g_wndclass;
    style : u32 = Win32.WS_OVERLAPPEDWINDOW;
    ex_style : u32 = Win32.WS_EX_APPWINDOW;

    if flags & .Borderless
        style = Win32.WS_POPUP;
    else if flags & .Custom_Caption
        style = Win32.WS_THICKFRAME | Win32.WS_SYSMENU | Win32.WS_MAXIMIZEBOX | Win32.WS_MINIMIZEBOX;

    if !(flags & .Hidden)
        style |= Win32.WS_VISIBLE;

    if flags & .No_Taskbar_Icon
        ex_style = Win32.WS_EX_TOOLWINDOW;

    if flags & .Topmost
        ex_style |= Win32.WS_EX_TOPMOST;

    if flags & .No_Resize
        style ^= Win32.WS_THICKFRAME | Win32.WS_MAXIMIZEBOX;

    rect : Win32.RECT;
    if x != Win32.CW_USEDEFAULT
        rect.left = x;
    if y != Win32.CW_USEDEFAULT
        rect.top = y;
    rect.right = rect.left + width;
    rect.bottom = rect.top + height;

    Win32.AdjustWindowRect (*rect, style, 0);

    if x != Win32.CW_USEDEFAULT
        x = rect.left;
    if y != Win32.CW_USEDEFAULT
        y = rect.top;

    width = rect.right - rect.left;
    height = rect.bottom - rect.top;

    hwnd := Win32.CreateWindowExW (
        ex_style,
        wndclass.lpszClassName,
        Windows_Utils.Utf8ToWide (title, Temp),
        style,
        x,
        y,
        width,
        height,
        ifx parent then parent.hwnd else null,
        null,
        Win32.GetModuleHandleW (null),
        null
    );

    // Watch for the next event event
    track : Win32.TRACKMOUSEEVENT;
    track.cbSize = size_of (Win32.TRACKMOUSEEVENT);
    track.hwndTrack = hwnd;
    track.dwFlags = 0x02;
    Win32.TrackMouseEvent (*track);

    window := Alloc (Window);
    window.hwnd = hwnd;
    window.caption_hit_test = extra.caption_hit_test;
    window.flags = flags;

    Win32.SetWindowLongPtrW (hwnd, Win32.GWLP_USERDATA, cast (*s32) window);
    ArrayPush (*g_all_windows, window);

    return window;
}

DestroyWindow :: inline (window : *Window) #no_context
{
    Win32.DestroyWindow (window.hwnd);
}

CloseWindow :: inline (window : *Window) #no_context
{
    Win32.PostMessageW (window.hwnd, Win32.WM_CLOSE, 0, 0);
}

SwapBuffers :: inline (window : *Window) #no_context
{
    Win32.SwapBuffers (Win32.GetDC (window.hwnd));
}

GetWindowTitle :: inline (window : *Window, allocator := context.allocator) -> string #must
{
    len := Win32.GetWindowTextLengthW (window.hwnd) + 2;
    wide_buffer := Alloc (u16, len, Temp);
    Win32.GetWindowTextW (window.hwnd, wide_buffer, len);

    return Windows_Utils.WideToUtf8 (wide_buffer, allocator);
}

SetWindowTitle :: inline (window : *Window, title : string)
{
    wide_title := Windows_Utils.Utf8ToWide (title, Temp);
    Win32.SetWindowTextW (window.hwnd, wide_title);
}

GetWindowPosition :: inline (window : *Window) -> x : s32, y : s32 #no_context
{
    rect : Win32.RECT;
    Win32.GetWindowRect (window.hwnd, *rect);

    return rect.left, rect.top;
}

SetWindowPosition :: inline (window : *Window, x : s32, y : s32) #no_context
{
    Win32.SetWindowPos (window.hwnd, null, x, y, 0, 0, Win32.SWP_NOSIZE | Win32.SWP_NOZORDER | Win32.SWP_NOACTIVATE);
}

GetWindowSize :: inline (window : *Window) -> width : s32, height : s32 #no_context
{
    rect : Win32.RECT;
    Win32.GetWindowRect (window.hwnd, *rect);

    return rect.right - rect.left, rect.bottom - rect.top;
}

SetWindowSize :: inline (window : *Window, width : s32, height : s32) #no_context
{
    Win32.SetWindowPos (window.hwnd, null, 0, 0, width, height, Win32.SWP_NOMOVE | Win32.SWP_NOZORDER | Win32.SWP_NOACTIVATE);
}

GetViewportPosition :: inline (window : *Window) -> width : s32, height : s32 #no_context
{
    x, y := WindowToScreenPosition (window, 0, 0);

    return x, y;
}

SetViewportPosition :: inline (window : *Window, x : s32, y : s32) #no_context
{
    style := cast, no_check (u32) Win32.GetWindowLongW (window.hwnd, Win32.GWL_STYLE);
    ex_style := cast, no_check (u32) Win32.GetWindowLongW (window.hwnd, Win32.GWL_EXSTYLE);
    rect := Win32.RECT.{x, y, x, y};
    Win32.AdjustWindowRectEx (*rect, style, 0, ex_style);

    Win32.SetWindowPos (window.hwnd, null, rect.left, rect.top, 0, 0, Win32.SWP_NOZORDER | Win32.SWP_NOSIZE | Win32.SWP_NOACTIVATE);
}

GetViewportSize :: inline (window : *Window) -> width : s32, height : s32 #no_context
{
    rect : Win32.RECT;
    Win32.GetClientRect (window.hwnd, *rect);

    return rect.right - rect.left, rect.bottom - rect.top;
}

SetViewportSize :: inline (window : *Window, width : s32, height : s32) #no_context
{
    style := cast, no_check (u32) Win32.GetWindowLongW (window.hwnd, Win32.GWL_STYLE);
    ex_style := cast, no_check (u32) Win32.GetWindowLongW (window.hwnd, Win32.GWL_EXSTYLE);
    rect := Win32.RECT.{0, 0, width, height};
    Win32.AdjustWindowRectEx (*rect, style, 0, ex_style);

    Win32.SetWindowPos (window.hwnd, null, 0, 0, rect.right - rect.left, rect.bottom - rect.top, Win32.SWP_NOZORDER | Win32.SWP_NOMOVE | Win32.SWP_NOACTIVATE);
}

GetFocusedWindow :: () -> *Window #must, non_fenetres_window_focused : bool #no_context
{
    focused := Win32.GetFocus ();
    if !focused
        return null, false;

    for g_all_windows
    {
        if focused == it.hwnd
            return it, false;
    }

    return null, true;
}

SetFocusedWindow :: inline (window : *Window) #no_context
{
    Win32.SetFocus (window.hwnd);
}

IsFocused :: inline (window : *Window) -> bool #must #no_context
{
    return GetFocusedWindow () == window;
}

IsMaximized :: inline (window : *Window) -> bool #must #no_context
{
    placement : Win32.WINDOWPLACEMENT;
    placement.length = size_of (Win32.WINDOWPLACEMENT);
    if Win32.GetWindowPlacement (window.hwnd, *placement)
        return placement.showCmd == Win32.SW_SHOWMAXIMIZED;

    return false;
}

IsMinimized :: inline (window : *Window) -> bool #must #no_context
{
    placement : Win32.WINDOWPLACEMENT;
    placement.length = size_of (Win32.WINDOWPLACEMENT);
    if Win32.GetWindowPlacement (window.hwnd, *placement)
        return placement.showCmd == Win32.SW_SHOWMINIMIZED;

    return false;
}

Maximize :: inline (window : *Window) #no_context
{
    Win32.ShowWindow (window.hwnd, Win32.SW_MAXIMIZE);
}

Restore :: inline (window : *Window) #no_context
{
    Win32.ShowWindow (window.hwnd, Win32.SW_RESTORE);
}

Minimize :: inline (window : *Window) #no_context
{
    Win32.ShowWindow (window.hwnd, Win32.SW_MINIMIZE);
}

SetWindowVisibility :: inline (window : *Window, visible : bool) #no_context
{
    if visible
        Win32.ShowWindow (window.hwnd, Win32.SW_SHOWNA);
    else
        Win32.ShowWindow (window.hwnd, Win32.SW_HIDE);
}

ShowAndFocusWindow :: inline (window : *Window) #no_context
{
    Win32.ShowWindow (window.hwnd, Win32.SW_SHOW);
}

GetMousePosition :: inline () -> x : s32, y : s32 #no_context
{
    result : Win32.POINT;
    Win32.GetCursorPos (*result);

    return result.x, result.y;
}

ScreenToWindowPosition :: inline (window : *Window, x : s32, y : s32) -> x : s32, y : s32 #no_context
{
    result := Win32.POINT.{x,y};
    Win32.ScreenToClient (window.hwnd, *result);

    return result.x, result.y;
}

WindowToScreenPosition :: inline (window : *Window, x : s32, y : s32) -> x : s32, y : s32 #no_context
{
    result := Win32.POINT.{x,y};
    Win32.ClientToScreen (window.hwnd, *result);

    return result.x, result.y;
}

GetMousePosition :: inline (window : *Window) -> x : s32, y : s32 #no_context
{
    result : Win32.POINT;
    Win32.GetCursorPos (*result);
    Win32.ScreenToClient (window.hwnd, *result);

    return result.x, result.y;
}

SetMousePosition :: inline (window : *Window, x : s32, y : s32) #no_context
{
    p : Win32.POINT;
    p.x = x;
    p.y = y;
    Win32.ClientToScreen (window, *p);
    Win32.SetCursorPos (p.x, p.y);
}

SetMousePosition :: inline (x : s32, y : s32) #no_context
{
    p : Win32.POINT;
    p.x = x;
    p.y = y;
    Win32.SetCursorPos (p.x, p.y);
}

SetMouseCapture :: inline (window : *Window, capture : bool) #no_context
{
    if capture
        Win32.SetCapture (window.hwnd);
    else
        Win32.ReleaseCapture ();
}

GetMouseCapture :: inline () -> *Window #must, non_fenetres_window : bool #no_context
{
    hwnd := Win32.GetCapture ();
    if !hwnd
        return null, false;

    window := GetWindowFromPlatformHandle (hwnd);
    if !window
        return null, true;

    return window, false;
}

PollMessages :: () -> []Message
{
    ArrayClear (*g_message_queue);

    windows_msg : Win32.MSG;
    while Win32.PeekMessageW (*windows_msg, null, 0, 0, Win32.PM_REMOVE)
    {
        Win32.TranslateMessage (*windows_msg);
        Win32.DispatchMessageW (*windows_msg);
    }

    return g_message_queue;
}

#scope_file

g_show_cursor : bool;

#scope_export

SetCursorVisibility :: inline (visible : bool) #no_context
{
    if g_show_cursor == visible
        return;

    // This function does not behave like expected: see https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-showcursor
    // "If bShow is TRUE, the display count is incremented by one. If bShow is FALSE, the display count is decremented by one."
    Win32.ShowCursor (xx visible);
    g_show_cursor = visible;
}

SetCursor :: inline (cursor : SystemCursor) #no_context
{
    Win32.SetCursor (g_cursors.all[cursor]);
}

VKToMouseButton :: inline (vk : u32) -> MouseButton #must #no_context
{
    if vk ==
    {
    case Win32.VK_LBUTTON;
        return .Left;
    case Win32.VK_RBUTTON;
        return .Right;
    case Win32.VK_MBUTTON;
        return .Middle;
    }

    return .Invalid;
}

MouseButtonToVK :: inline (button : MouseButton) -> s32 #must #no_context
{
    if button ==
    {
    case .Left;
        return Win32.VK_LBUTTON;
    case .Right;
        return Win32.VK_RBUTTON;
    case .Middle;
        return Win32.VK_MBUTTON;
    }

    return 0;
}

VKToKeyCode :: (vk : s32) -> KeyCode #must #no_context
{
    #insert -> string
    {
        #import "String_Builder";

        builder : StringBuilder;

        StringBuilderAppendLine (*builder, "if vk ==\n{{");
        for i : 0..256
        {
            for VK_To_Key_Code_Map
            {
                if it.vk == i
                {
                    StringBuilderAppendLine (*builder, "case %; return .%;", i, it.key_code);
                    continue i;
                }
            }
        }
        StringBuilderAppendLine (*builder, "}");

        return StringBuilderBuild (*builder);
    };

    return .Invalid;
}

KeyCodeToVK :: (key_code : KeyCode) -> s32 #must #no_context
{
    #insert -> string
    {
        #import "String_Builder";

        builder : StringBuilder;

        StringBuilderAppendLine (*builder, "if key_code ==\n{{");
        for i : 0..256
        {
            for VK_To_Key_Code_Map
            {
                if it.key_code == xx i
                {
                    StringBuilderAppendLine (*builder, "case .%; return %;", it.key_code, it.vk);
                    continue i;
                }
            }
        }
        StringBuilderAppendLine (*builder, "}");

        return StringBuilderBuild (*builder);
    };

    return 0;
}

GetKeyModState :: inline () -> KeyMods #must #no_context
{
    result : KeyMods;
    if (Win32.GetAsyncKeyState (Win32.VK_CONTROL) & 0x8000) != 0
        result |= .Ctrl;
    if (Win32.GetAsyncKeyState (Win32.VK_SHIFT) & 0x8000) != 0
        result |= .Shift;
    if (Win32.GetAsyncKeyState (Win32.VK_MENU) & 0x8000) != 0
        result |= .Alt;

    return result;
}

GetClipboardTextData :: (allocator := context.allocator) -> string #must
{
    if !Win32.OpenClipboard (null)
        return "";

    defer Win32.CloseClipboard ();

    data := Win32.GetClipboardData (Win32.CF_UNICODETEXT);
    if !data
        return "";

    buffer := Win32.GlobalLock (data);
    defer Win32.GlobalUnlock (data);

    return Windows_Utils.WideToUtf8 (buffer, allocator);
}

SetClipboardTextData :: (text : string)
{
    if !Win32.OpenClipboard (null)
        return;

    defer Win32.CloseClipboard ();

    wide_str, wide_len := Windows_Utils.Utf8ToWide (text, Temp);

    clipbuffer := Win32.GlobalAlloc (0, xx (wide_len * 2 + 2));

    buffer := Win32.GlobalLock (clipbuffer);
    memcpy (buffer, wide_str, wide_len * 2 + 2);
    Win32.GlobalUnlock (clipbuffer);

    Win32.SetClipboardData (Win32.CF_UNICODETEXT, clipbuffer);
}

ClearClipboard :: inline ()
{
    if !Win32.OpenClipboard (null)
        return;

    Win32.EmptyClipboard ();
    Win32.CloseClipboard ();
}

#scope_file

Keystroke :: struct
{
    repeat_count : s16;
    scan_code : u8;
    extended : bool;
    previous_key_state : bool;
    transition_state : bool;
    alt_down : bool;
    dialog_mode : bool;
    menu_mode : bool;
}

DecomposeKeystrokeParam :: inline (lparam : Win32.LPARAM) -> Keystroke #must
{
    KF_EXTENDED :: 256;
    KF_DLGMODE  :: 2048;
    KF_MENUMODE :: 4096;
    KF_ALTDOWN  :: 8192;
    KF_REPEAT   :: 16384;
    KF_UP       :: 32768;

    using result : Keystroke;
    repeat_count = Win32.LOWORD (lparam);
    scan_code = cast, no_check (u8) Win32.HIWORD (lparam);
    extended           = (Win32.HIWORD (lparam) & KF_EXTENDED) == KF_EXTENDED;
    previous_key_state = (Win32.HIWORD (lparam) & KF_REPEAT) == KF_REPEAT;
    transition_state   = (Win32.HIWORD (lparam) & KF_UP) == KF_UP;
    alt_down           = (Win32.HIWORD (lparam) & KF_ALTDOWN) == KF_ALTDOWN;
    dialog_mode        = (Win32.HIWORD (lparam) & KF_DLGMODE) == KF_DLGMODE;
    menu_mode          = (Win32.HIWORD (lparam) & KF_MENUMODE) == KF_MENUMODE;

    return result;
}

WindowProc :: (hwnd : Win32.HWND, msg : u32, wparam : Win32.WPARAM, lparam : Win32.LPARAM) -> Win32.LRESULT
#c_call
{
    window := cast (*Window) Win32.GetWindowLongPtrW (hwnd, Win32.GWLP_USERDATA);
    if !window
        return Win32.DefWindowProcW (hwnd, msg, wparam, lparam);

    window_message : Message;
    window_message.window = window;

    ctx : Context;
    push_context ctx
    {
        if msg ==
        {
        case Win32.WM_DESTROY;
            for g_all_windows
            {
                if it == window
                {
                    remove it;
                    break;
                }
            }

            Free (window);
            Win32.SetWindowLongPtrW (hwnd, Win32.GWLP_USERDATA, cast (*s32) null);

        case Win32.WM_MOVE;
            window_message.kind = .Window_Moved;
            window_message.window_x = Win32.LOWORD (lparam);
            window_message.window_y = Win32.HIWORD (lparam);
            ArrayPush (*g_message_queue, window_message);

        case Win32.WM_SIZE;
            if wparam ==
            {
            case Win32.SIZE_RESTORED;
                window_message.kind = .Window_Resized;
            case Win32.SIZE_MINIMIZED;
                window_message.kind = .Window_Minimized;
            case Win32.SIZE_MAXIMIZED;
                window_message.kind = .Window_Maximized;
            }
            window_message.viewport_w = Win32.LOWORD (lparam);
            window_message.viewport_h = Win32.HIWORD (lparam);
            ArrayPush (*g_message_queue, window_message);

        case Win32.WM_CLOSE;
            window_message.kind = .Window_Closed;
            ArrayPush (*g_message_queue, window_message);

        case Win32.WM_SHOWWINDOW;
            if wparam
                window_message.kind = .Window_Shown;
            else
                window_message.kind = .Window_Hidden;
            ArrayPush (*g_message_queue, window_message);

        case Win32.WM_SETFOCUS;
            window_message.kind = .Window_Received_Focus;
            ArrayPush (*g_message_queue, window_message);

        case Win32.WM_KILLFOCUS;
            window_message.kind = .Window_Lost_Focus;
            ArrayPush (*g_message_queue, window_message);

        case Win32.WM_CHAR;
            codepoint := cast (u32) wparam;
            Utf16_Hi_Surrogate  :: cast (u16) 0xd800;
            Utf16_Lo_Surrogate  :: cast (u16) 0xdc00;
            Utf16_Surrogate_End :: cast (u16) 0xdfff;

            if codepoint >= Utf16_Hi_Surrogate && codepoint < Utf16_Lo_Surrogate
            {
                window.WM_CHAR_utf16_high_surrogate = cast (u16) codepoint;
            }
            else
            {
                if codepoint >= Utf16_Lo_Surrogate && codepoint <= Utf16_Surrogate_End
                {
                    low_surrogate := cast (u16) codepoint;
                    codepoint  = (window.WM_CHAR_utf16_high_surrogate - Utf16_Hi_Surrogate) << 10;
                    codepoint |= (low_surrogate - Utf16_Hi_Surrogate);
                    codepoint += 0x10000;
                }

                window_message.kind = .Text_Input;
                window_message.mods = GetKeyModState ();
                window_message.codepoint = codepoint;
                ArrayPush (*g_message_queue, window_message);
            }

        case Win32.WM_SYSKEYDOWN; #through;
        case Win32.WM_SYSKEYUP; #through;
        case Win32.WM_KEYDOWN; #through;
        case Win32.WM_KEYUP;
            using keystroke := DecomposeKeystrokeParam (lparam);

            if msg == Win32.WM_KEYUP || msg == Win32.WM_SYSKEYUP
                window_message.kind = .Key_Released;
            else if previous_key_state
                window_message.kind = .Key_Repeated;
            else
                window_message.kind = .Key_Pressed;

            window_message.mods = GetKeyModState ();
            window_message.key_code = VKToKeyCode (xx wparam);
            ArrayPush (*g_message_queue, window_message);

            if msg == Win32.WM_SYSKEYDOWN || msg == Win32.WM_SYSKEYUP
                return Win32.DefWindowProcW (hwnd, msg, wparam, lparam);

        case Win32.WM_LBUTTONDOWN;
            window_message.kind = .Mouse_Button_Pressed;
            window_message.mouse_button = .Left;
            window_message.mods = GetKeyModState ();
            window_message.mouse_x, window_message.mouse_y = Win32.LOWORD (lparam), Win32.HIWORD (lparam);
            ArrayPush (*g_message_queue, window_message);

        case Win32.WM_RBUTTONDOWN;
            window_message.kind = .Mouse_Button_Pressed;
            window_message.mouse_button = .Right;
            window_message.mods = GetKeyModState ();
            window_message.mouse_x, window_message.mouse_y = Win32.LOWORD (lparam), Win32.HIWORD (lparam);
            ArrayPush (*g_message_queue, window_message);

        case Win32.WM_MBUTTONDOWN;
            window_message.kind = .Mouse_Button_Pressed;
            window_message.mouse_button = .Middle;
            window_message.mods = GetKeyModState ();
            window_message.mouse_x, window_message.mouse_y = Win32.LOWORD (lparam), Win32.HIWORD (lparam);
            ArrayPush (*g_message_queue, window_message);

        case Win32.WM_LBUTTONUP;
            window_message.kind = .Mouse_Button_Released;
            window_message.mouse_button = .Left;
            window_message.mods = GetKeyModState ();
            window_message.mouse_x, window_message.mouse_y = Win32.LOWORD (lparam), Win32.HIWORD (lparam);
            ArrayPush (*g_message_queue, window_message);

        case Win32.WM_RBUTTONUP;
            window_message.kind = .Mouse_Button_Released;
            window_message.mouse_button = .Right;
            window_message.mods = GetKeyModState ();
            window_message.mouse_x, window_message.mouse_y = Win32.LOWORD (lparam), Win32.HIWORD (lparam);
            ArrayPush (*g_message_queue, window_message);

        case Win32.WM_MBUTTONUP;
            window_message.kind = .Mouse_Button_Released;
            window_message.mouse_button = .Middle;
            window_message.mods = GetKeyModState ();
            window_message.mouse_x, window_message.mouse_y = Win32.LOWORD (lparam), Win32.HIWORD (lparam);
            ArrayPush (*g_message_queue, window_message);

        case Win32.WM_LBUTTONDBLCLK;
            window_message.kind = .Mouse_Button_Repeated;
            window_message.mouse_button = .Left;
            window_message.mods = GetKeyModState ();
            window_message.mouse_x, window_message.mouse_y = Win32.LOWORD (lparam), Win32.HIWORD (lparam);
            ArrayPush (*g_message_queue, window_message);

        case Win32.WM_RBUTTONDBLCLK;
            window_message.kind = .Mouse_Button_Repeated;
            window_message.mouse_button = .Right;
            window_message.mods = GetKeyModState ();
            window_message.mouse_x, window_message.mouse_y = Win32.LOWORD (lparam), Win32.HIWORD (lparam);
            ArrayPush (*g_message_queue, window_message);

        case Win32.WM_MBUTTONDBLCLK;
            window_message.kind = .Mouse_Button_Repeated;
            window_message.mouse_button = .Middle;
            window_message.mods = GetKeyModState ();
            window_message.mouse_x, window_message.mouse_y = Win32.LOWORD (lparam), Win32.HIWORD (lparam);
            ArrayPush (*g_message_queue, window_message);

        case Win32.WM_MOUSEHWHEEL; #through;
        case Win32.WM_MOUSEWHEEL;
            window_message.kind = .Mouse_Wheel;
            window_message.mods = GetKeyModState ();
            if msg == Win32.WM_MOUSEHWHEEL
                window_message.mouse_wheel_x = Win32.HIWORD (wparam) / 120.0;
            else
                window_message.mouse_wheel_y = Win32.HIWORD (wparam) / 120.0;
            window_message.mouse_x, window_message.mouse_y = Win32.LOWORD (lparam), Win32.HIWORD (lparam);
            ArrayPush (*g_message_queue, window_message);

        case Win32.WM_MOUSEMOVE;
            if window.mouse_is_outside
            {
                window.mouse_is_outside = false;

                // Watch for the next WM_MOUSELEAVE event
                track : Win32.TRACKMOUSEEVENT;
                track.cbSize = size_of (Win32.TRACKMOUSEEVENT);
                track.hwndTrack = hwnd;
                track.dwFlags = 0x02;
                Win32.TrackMouseEvent (*track);

                enter_message := window_message;
                enter_message.kind = .Mouse_Entered_Window;
                enter_message.mods = GetKeyModState ();
                enter_message.mouse_x, enter_message.mouse_y = Win32.LOWORD (lparam), Win32.HIWORD (lparam);
                ArrayPush (*g_message_queue, enter_message);
            }

            window_message.kind = .Mouse_Moved;
            window_message.mods = GetKeyModState ();
            window_message.mouse_x, window_message.mouse_y = Win32.LOWORD (lparam), Win32.HIWORD (lparam);
            ArrayPush (*g_message_queue, window_message);

        case Win32.WM_MOUSELEAVE;
            window.mouse_is_outside = true;
            window_message.kind = .Mouse_Left_Window;
            ArrayPush (*g_message_queue, window_message);

        case Win32.WM_SETCURSOR;
            Win32.SetCursor (g_cursors.arrow);

            return Win32.DefWindowProcW (hwnd, msg, wparam, lparam);

        case;
            return Win32.DefWindowProcW (hwnd, msg, wparam, lparam);
        }
    }

    return 0;
}

CustomCaptionWindowProc :: (hwnd : Win32.HWND, msg : u32, wparam : Win32.WPARAM, lparam : Win32.LPARAM) -> Win32.LRESULT
#c_call
{
    window := cast (*Window) Win32.GetWindowLongPtrW (hwnd, Win32.GWLP_USERDATA);
    if !window
        return Win32.DefWindowProcW (hwnd, msg, wparam, lparam);

    window_message : Message;

    ctx : Context;
    push_context ctx
    {
        if msg ==
        {
        case Win32.WM_CREATE;
            size_rect : Win32.RECT;
            Win32.GetWindowRect (hwnd, *size_rect);
            Win32.SetWindowPos (hwnd, null,
                size_rect.left, size_rect.top,
                size_rect.right - size_rect.left, size_rect.bottom - size_rect.top,
                Win32.SWP_FRAMECHANGED | Win32.SWP_NOMOVE | Win32.SWP_NOSIZE
            );

            return Win32.DefWindowProcW (hwnd, msg, wparam, lparam);

        case Win32.WM_NCCALCSIZE;
            if wparam == 0
                return Win32.DefWindowProcW (hwnd, msg, wparam, lparam);

            frame_x := Win32.GetSystemMetrics (Win32.SM_CXFRAME);
            frame_y := Win32.GetSystemMetrics (Win32.SM_CYFRAME);
            padding := Win32.GetSystemMetrics (Win32.SM_CXPADDEDBORDER);
            params := cast (*Win32.NCCALCSIZE_PARAMS) lparam;

            client_rect := *params.rgrc[0];
            client_rect.right  -= frame_x + padding;
            client_rect.left   += frame_x + padding;
            client_rect.bottom -= frame_y + padding;

            if IsMaximized (window)
                client_rect.top += padding * 2;

            return 0;

        case Win32.WM_NCHITTEST;
            hit := Win32.DefWindowProcW (hwnd, msg, wparam, lparam);

            if hit ==
            {
            case Win32.HTNOWHERE; #through;
            case Win32.HTRIGHT; #through;
            case Win32.HTLEFT; #through;
            case Win32.HTTOPLEFT; #through;
            case Win32.HTTOP; #through;
            case Win32.HTTOPRIGHT; #through;
            case Win32.HTBOTTOMRIGHT; #through;
            case Win32.HTBOTTOM; #through;
            case Win32.HTBOTTOMLEFT;
                return hit;
            }

            cursor : Win32.POINT;
            cursor.x, cursor.y = Win32.LOWORD (lparam), Win32.HIWORD (lparam);
            Win32.ScreenToClient (hwnd, *cursor);

            on_caption := window.caption_hit_test && window.caption_hit_test (window, cursor.x, cursor.y);
            on_resize_border := cursor.y > 0 && cursor.y < Win32.GetSystemMetrics (Win32.SM_CYFRAME) + Win32.GetSystemMetrics (Win32.SM_CXPADDEDBORDER);

            // Don't resize when we are not on the caption, because we could be on
            // some UI elements. If we don't have a caption_hit_test, then ignore
            // that. The user should provide a hit test function anyway...
            if on_resize_border && (on_caption || !window.caption_hit_test)
                return Win32.HTTOP;
            else if on_caption
                return Win32.HTCAPTION;

            return Win32.HTCLIENT;
        }
    }

    return WindowProc (hwnd, msg, wparam, lparam);
}

VKKeyCodePair :: struct
{
    vk : s32;
    key_code : KeyCode;
}

VK_To_Key_Code_Map :: VKKeyCodePair.[
    .{ Win32.VK_BACK, .Backspace },
    .{ Win32.VK_TAB, .Tab },
    .{ Win32.VK_CLEAR, .Clear },
    .{ Win32.VK_RETURN, .Return },
    .{ Win32.VK_SHIFT, .Shift },
    .{ Win32.VK_CONTROL, .Ctrl },
    .{ Win32.VK_MENU, .Alt },
    .{ Win32.VK_PAUSE, .Pause },
    .{ Win32.VK_CAPITAL, .Caps_Lock },
    .{ Win32.VK_ESCAPE, .Escape },
    .{ Win32.VK_SPACE, .Space },
    .{ Win32.VK_PRIOR, .Page_Up },
    .{ Win32.VK_NEXT, .Page_Down },
    .{ Win32.VK_END, .End },
    .{ Win32.VK_HOME, .Home },
    .{ Win32.VK_LEFT, .Left },
    .{ Win32.VK_UP, .Up },
    .{ Win32.VK_RIGHT, .Right },
    .{ Win32.VK_DOWN, .Down },
    .{ Win32.VK_SELECT, .Select },
    .{ Win32.VK_PRINT, .Print },
    .{ Win32.VK_EXECUTE, .Execute },
    .{ Win32.VK_SNAPSHOT, .Print_Screen },
    .{ Win32.VK_INSERT, .Insert },
    .{ Win32.VK_DELETE, .Delete },
    .{ Win32.VK_HELP, .Help },
    .{ #char "0", .Zero },
    .{ #char "1", .One },
    .{ #char "2", .Two },
    .{ #char "3", .Three },
    .{ #char "4", .Four },
    .{ #char "5", .Five },
    .{ #char "6", .Six },
    .{ #char "7", .Seven },
    .{ #char "8", .Eight },
    .{ #char "9", .Nine },
    .{ #char "A", .A },
    .{ #char "B", .B },
    .{ #char "C", .C },
    .{ #char "D", .D },
    .{ #char "E", .E },
    .{ #char "F", .F },
    .{ #char "G", .G },
    .{ #char "H", .H },
    .{ #char "I", .I },
    .{ #char "J", .J },
    .{ #char "K", .K },
    .{ #char "L", .L },
    .{ #char "M", .M },
    .{ #char "N", .N },
    .{ #char "O", .O },
    .{ #char "P", .P },
    .{ #char "Q", .Q },
    .{ #char "R", .R },
    .{ #char "S", .S },
    .{ #char "T", .T },
    .{ #char "U", .U },
    .{ #char "V", .V },
    .{ #char "W", .W },
    .{ #char "X", .X },
    .{ #char "Y", .Y },
    .{ #char "Z", .Z },
    .{ Win32.VK_LWIN, .Left_Super },
    .{ Win32.VK_RWIN, .Right_Super },
    .{ Win32.VK_NUMPAD0, .Numpad0 },
    .{ Win32.VK_NUMPAD1, .Numpad1 },
    .{ Win32.VK_NUMPAD2, .Numpad2 },
    .{ Win32.VK_NUMPAD3, .Numpad3 },
    .{ Win32.VK_NUMPAD4, .Numpad4 },
    .{ Win32.VK_NUMPAD5, .Numpad5 },
    .{ Win32.VK_NUMPAD6, .Numpad6 },
    .{ Win32.VK_NUMPAD7, .Numpad7 },
    .{ Win32.VK_NUMPAD8, .Numpad8 },
    .{ Win32.VK_NUMPAD9, .Numpad9 },
    .{ Win32.VK_MULTIPLY, .Multiply },
    .{ Win32.VK_ADD, .Add },
    .{ Win32.VK_SEPARATOR, .Separator },
    .{ Win32.VK_SUBTRACT, .Subtract },
    .{ Win32.VK_DECIMAL, .Decimal },
    .{ Win32.VK_DIVIDE, .Divide },
    .{ Win32.VK_F1, .F1 },
    .{ Win32.VK_F2, .F2 },
    .{ Win32.VK_F3, .F3 },
    .{ Win32.VK_F4, .F4 },
    .{ Win32.VK_F5, .F5 },
    .{ Win32.VK_F6, .F6 },
    .{ Win32.VK_F7, .F7 },
    .{ Win32.VK_F8, .F8 },
    .{ Win32.VK_F9, .F9 },
    .{ Win32.VK_F10, .F10 },
    .{ Win32.VK_F11, .F11 },
    .{ Win32.VK_F12, .F12 },
    .{ Win32.VK_NUMLOCK, .Num_Lock },
    .{ Win32.VK_SCROLL, .Scroll_Lock },
    .{ Win32.VK_LSHIFT, .Left_Shift },
    .{ Win32.VK_RSHIFT, .Right_Shift },
    .{ Win32.VK_LCONTROL, .Left_Ctrl },
    .{ Win32.VK_RCONTROL, .Right_Ctrl },
    .{ Win32.VK_LMENU, .Left_Alt },
    .{ Win32.VK_RMENU, .Right_Alt },
    .{ Win32.VK_OEM_1, .OEM1 },
    .{ Win32.VK_OEM_PLUS, .OEM_Plus },
    .{ Win32.VK_OEM_COMMA, .OEM_Comma },
    .{ Win32.VK_OEM_MINUS, .OEM_Minus },
    .{ Win32.VK_OEM_PERIOD, .OEM_Period },
    .{ Win32.VK_OEM_2, .OEM2 },
    .{ Win32.VK_OEM_3, .OEM3 },
    .{ Win32.VK_OEM_4, .OEM4 },
    .{ Win32.VK_OEM_5, .OEM5 },
    .{ Win32.VK_OEM_6, .OEM6 },
    .{ Win32.VK_OEM_7, .OEM7 },
    .{ Win32.VK_OEM_8, .OEM8 },
    .{ Win32.VK_OEM_102, .OEM102 }
];
