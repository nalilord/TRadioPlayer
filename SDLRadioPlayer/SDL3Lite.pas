unit SDL3Lite;

interface

type
  TSDL_InitFlags = type LongWord;
  TSDL_EventType = type LongWord;
  TSDL_WindowID = type LongWord;
  TSDL_Keycode = type LongWord;
  TSDL_Keymod = type LongWord;

  PSDL_Window = Pointer;
  PPSDL_Window = ^PSDL_Window;
  PSDL_Renderer = Pointer;
  PPSDL_Renderer = ^PSDL_Renderer;

  PSDL_FRect = ^TSDL_FRect;
  TSDL_FRect = record
    x: Single;
    y: Single;
    w: Single;
    h: Single;
  end;

  TSDL_WindowEvent = record
    type_: TSDL_EventType;
    reserved: LongWord;
    timestamp: UInt64;
    windowID: TSDL_WindowID;
    data1: Integer;
    data2: Integer;
  end;

  TSDL_KeyboardEvent = record
    type_: TSDL_EventType;
    reserved: LongWord;
    timestamp: UInt64;
    windowID: TSDL_WindowID;
    which: LongWord;
    scancode: LongWord;
    key: TSDL_Keycode;
    mod_: TSDL_Keymod;
    raw: Word;
    down: Boolean;
    repeat_: Boolean;
  end;

  TSDL_TextInputEvent = record
    type_: TSDL_EventType;
    reserved: LongWord;
    timestamp: UInt64;
    windowID: TSDL_WindowID;
    text: PAnsiChar;
  end;

  TSDL_MouseButtonEvent = record
    type_: TSDL_EventType;
    reserved: LongWord;
    timestamp: UInt64;
    windowID: TSDL_WindowID;
    which: LongWord;
    button: Byte;
    down: Boolean;
    clicks: Byte;
    padding: Byte;
    x: Single;
    y: Single;
  end;

  PSDL_Event = ^TSDL_Event;
  TSDL_Event = record
    case Integer of
      0: (type_: LongWord);
      1: (window: TSDL_WindowEvent);
      2: (key: TSDL_KeyboardEvent);
      3: (text: TSDL_TextInputEvent);
      4: (button: TSDL_MouseButtonEvent);
      5: (padding: array[0..127] of Byte);
  end;

const
  SDL_LibName = 'SDL3.dll';

  SDL_INIT_VIDEO = TSDL_InitFlags($00000020);

  SDL_EVENT_QUIT = TSDL_EventType($100);
  SDL_EVENT_WINDOW_RESIZED = TSDL_EventType(518);
  SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED = TSDL_EventType(519);
  SDL_EVENT_WINDOW_CLOSE_REQUESTED = TSDL_EventType(528);
  SDL_EVENT_KEY_DOWN = TSDL_EventType($300);
  SDL_EVENT_TEXT_INPUT = TSDL_EventType(771);
  SDL_EVENT_MOUSE_BUTTON_DOWN = TSDL_EventType(1025);

  SDLK_RETURN = TSDL_Keycode($0000000d);
  SDLK_ESCAPE = TSDL_Keycode($0000001b);
  SDLK_BACKSPACE = TSDL_Keycode($00000008);
  SDLK_TAB = TSDL_Keycode($00000009);
  SDLK_RETURN2 = TSDL_Keycode($4000009e);
  SDLK_V = TSDL_Keycode($00000076);

  SDL_KMOD_LCTRL = TSDL_Keymod($0040);
  SDL_KMOD_RCTRL = TSDL_Keymod($0080);
  SDL_KMOD_CTRL = TSDL_Keymod(SDL_KMOD_LCTRL or SDL_KMOD_RCTRL);

  SDL_DEBUG_TEXT_FONT_CHARACTER_SIZE = 8;

function SDL_Init(flags: TSDL_InitFlags): Boolean; cdecl; external SDL_LibName;
procedure SDL_Quit; cdecl; external SDL_LibName;
function SDL_CreateWindowAndRenderer(title: PAnsiChar; width: Integer; height: Integer;
  window_flags: UInt64; window: PPSDL_Window; renderer: PPSDL_Renderer): Boolean; cdecl; external SDL_LibName;
procedure SDL_DestroyWindow(window: PSDL_Window); cdecl; external SDL_LibName;
procedure SDL_DestroyRenderer(renderer: PSDL_Renderer); cdecl; external SDL_LibName;
function SDL_PollEvent(event: PSDL_Event): Boolean; cdecl; external SDL_LibName;
function SDL_StartTextInput(window: PSDL_Window): Boolean; cdecl; external SDL_LibName;
function SDL_StopTextInput(window: PSDL_Window): Boolean; cdecl; external SDL_LibName;
function SDL_HasClipboardText: Boolean; cdecl; external SDL_LibName;
function SDL_GetClipboardText: PAnsiChar; cdecl; external SDL_LibName;
function SDL_SetRenderDrawColor(renderer: PSDL_Renderer; r, g, b, a: Byte): Boolean; cdecl; external SDL_LibName;
function SDL_RenderClear(renderer: PSDL_Renderer): Boolean; cdecl; external SDL_LibName;
function SDL_RenderFillRect(renderer: PSDL_Renderer; rect: PSDL_FRect): Boolean; cdecl; external SDL_LibName;
function SDL_RenderRect(renderer: PSDL_Renderer; rect: PSDL_FRect): Boolean; cdecl; external SDL_LibName;
function SDL_RenderPresent(renderer: PSDL_Renderer): Boolean; cdecl; external SDL_LibName;
function SDL_RenderDebugText(renderer: PSDL_Renderer; x, y: Single; str: PAnsiChar): Boolean; cdecl; external SDL_LibName;
function SDL_SetRenderScale(renderer: PSDL_Renderer; scaleX, scaleY: Single): Boolean; cdecl; external SDL_LibName;
procedure SDL_Delay(ms: LongWord); cdecl; external SDL_LibName;
procedure SDL_free(mem: Pointer); cdecl; external SDL_LibName;

implementation

end.
