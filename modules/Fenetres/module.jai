#if OS == .WINDOWS
    #load "windows.jai";

Window_Default_Pos :: -1;
Window_Default_Size :: -1;

WindowFlags :: enum_flags
{
    Hidden;
    Custom_Caption;
    Borderless;
    No_Taskbar_Icon;
    Topmost;
}

SystemCursor :: enum
{
    Arrow;
    Arrow_Busy;
    Busy;
    Cross;
    Hand;
    IBeam;
    Size;
    Size_NWSE;
    Size_NESW;
    Size_Horizontal;
    Size_Vertical;
    Not_Allowed;

    Count;
}

Message :: struct
{
    Kind :: enum
    {
        Invalid;

        Window_Moved;
        Window_Resized;
        Window_Maximized;
        Window_Minimized;
        Window_Closed;
        Window_Shown;
        Window_Hidden;
        Window_Received_Focus;
        Window_Lost_Focus;

        Text_Input;
        Key_Pressed;
        Key_Repeated;
        Key_Released;

        Mouse_Raw_Moved;
        Mouse_Moved;
        Mouse_Wheel;
        Mouse_Button_Pressed;
        Mouse_Button_Repeated;
        Mouse_Button_Released;
        Mouse_Entered_Window;
        Mouse_Left_Window;
    }

    kind : Kind;
    window : *Window;
    window_x, window_y : s32;
    window_w, window_h : s32;
    viewport_w, viewport_h : s32;
    codepoint : u32;
    mods : KeyMods;
    key_code : KeyCode;
    mouse_delta_x, mouse_delta_y : s32;
    mouse_x, mouse_y : s32;
    mouse_wheel_x, mouse_wheel_y : float;
    mouse_button : MouseButton;
}

MouseButton :: enum
{
    Invalid;
    Left;
    Right;
    Middle;
}

KeyMods :: enum_flags
{
    Ctrl;
    Shift;
    Alt;
}

KeyCode :: enum
{
    Invalid;
    Backspace;
    Tab;
    Clear;
    Return;
    Shift;
    Ctrl;
    Alt;
    Left_Shift;
    Right_Shift;
    Left_Ctrl;
    Right_Ctrl;
    Left_Alt;
    Right_Alt;
    Left_Super;
    Right_Super;
    Pause;
    Caps_Lock;
    Escape;
    Space;
    Page_Up;
    Page_Down;
    End;
    Home;
    Left;
    Up;
    Right;
    Down;
    Select;
    Print;
    Execute;
    Print_Screen;
    Insert;
    Delete;
    Help;
    Zero;
    One;
    Two;
    Three;
    Four;
    Five;
    Six;
    Seven;
    Eight;
    Nine;
    A; B; C; D; E; F; G; H; I; J; K; L; M;
    N; O; P; Q; R; S; T; U; V; W; X; Y; Z;
    Numpad0;
    Numpad1;
    Numpad2;
    Numpad3;
    Numpad4;
    Numpad5;
    Numpad6;
    Numpad7;
    Numpad8;
    Numpad9;
    Scroll_Lock;
    Num_Lock;
    Multiply;
    Add;
    Separator;
    Subtract;
    Decimal;
    Divide;
    F1; F2; F3; F4; F5; F6; F7; F8; F9; F10; F11; F12;

    OEM1;
    Colon     :: OEM1;
    Semicolon :: OEM1;

    OEM_Plus;
    OEM_Comma;
    OEM_Minus;
    OEM_Period;

    OEM2;
    Slash              :: OEM2;
    Interrogation_Mark :: OEM2;

    OEM3;
    Backtick :: OEM3;
    Tilde    :: OEM3;

    OEM4;
    Open_Bracket :: OEM4;
    Open_Square_Bracket :: OEM4;
    Open_Curly_Bracket  :: OEM4;

    OEM5;
    Backslash :: OEM5;
    Pipe      :: OEM5;

    OEM6;
    Close_Bracket :: OEM6;
    Close_Square_Bracket :: OEM6;
    Close_Curly_Bracket  :: OEM6;

    OEM7;
    Quote :: OEM7;

    OEM8;
    OEM102;

    Count;
}
