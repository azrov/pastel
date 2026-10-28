{ Pastel - minimal SDL2 bindings, loaded at run time.

  Only the functions Pastel needs are declared. The library is loaded with
  dlopen/LoadLibrary, so building a Pastel app needs no SDL development files,
  and a missing library gives a clear message instead of a crash.
  Part of the Pastel project, MIT License. }
unit Pastel.SDL2;

{$mode objfpc}{$H+}
{$packrecords c}

interface

uses
  dynlibs;

const
  SDL_INIT_VIDEO = $00000020;

  SDL_WINDOWPOS_CENTERED = $2FFF0000;
  SDL_WINDOW_SHOWN = $00000004;
  SDL_WINDOW_RESIZABLE = $00000020;
  SDL_WINDOW_MINIMIZED = $00000040;
  SDL_WINDOW_MAXIMIZED = $00000080;
  SDL_WINDOW_FULLSCREEN_DESKTOP = $00001001;
  SDL_WINDOW_ALWAYS_ON_TOP = $00008000;

  SDL_RENDERER_SOFTWARE = $00000001;
  SDL_RENDERER_ACCELERATED = $00000002;
  SDL_RENDERER_PRESENTVSYNC = $00000004;

  SDL_PIXELFORMAT_ARGB8888 = $16362004;
  SDL_TEXTUREACCESS_STREAMING = 1;

  { Event types }
  SDL_QUIT_EV = $100;
  SDL_WINDOWEVENT = $200;
  SDL_KEYDOWN = $300;
  SDL_KEYUP = $301;
  SDL_TEXTINPUT = $303;
  SDL_MOUSEMOTION = $400;
  SDL_MOUSEBUTTONDOWN = $401;
  SDL_MOUSEBUTTONUP = $402;
  SDL_MOUSEWHEEL = $403;

  { Window events }
  SDL_WINDOWEVENT_EXPOSED = 3;
  SDL_WINDOWEVENT_RESIZED = 5;
  SDL_WINDOWEVENT_SIZE_CHANGED = 6;
  SDL_WINDOWEVENT_MINIMIZED = 7;
  SDL_WINDOWEVENT_MAXIMIZED = 8;
  SDL_WINDOWEVENT_RESTORED = 9;
  SDL_WINDOWEVENT_LEAVE = 11;
  SDL_WINDOWEVENT_FOCUS_LOST = 13;

  SDL_BUTTON_LEFT = 1;

  { Key codes }
  SDLK_BACKSPACE = 8;
  SDLK_TAB = 9;
  SDLK_RETURN = 13;
  SDLK_ESCAPE = 27;
  SDLK_SPACE = 32;
  SDLK_DELETE = 127;
  SDLK_KP_ENTER = $40000058;
  SDLK_RIGHT = $4000004F;
  SDLK_LEFT = $40000050;
  SDLK_DOWN = $40000051;
  SDLK_UP = $40000052;
  SDLK_HOME = $4000004A;
  SDLK_END = $4000004D;
  SDLK_a = Ord('a');
  SDLK_c = Ord('c');
  SDLK_v = Ord('v');
  SDLK_x = Ord('x');

  KMOD_SHIFT = $0003;
  KMOD_CTRL = $00C0;
  KMOD_GUI = $0C00;

  SDL_SYSTEM_CURSOR_ARROW = 0;
  SDL_SYSTEM_CURSOR_IBEAM = 1;
  SDL_SYSTEM_CURSOR_HAND = 11;

type
  PSDL_Window = Pointer;
  PSDL_Renderer = Pointer;
  PSDL_Texture = Pointer;
  PSDL_Cursor = Pointer;

  TSDL_Keysym = record
    scancode: LongInt;
    sym: LongInt;
    mods: Word;
    unused: LongWord;
  end;

  TSDL_WindowEvent = record
    type_: LongWord;
    timestamp: LongWord;
    windowID: LongWord;
    event: Byte;
    padding1, padding2, padding3: Byte;
    data1: LongInt;
    data2: LongInt;
  end;

  TSDL_KeyboardEvent = record
    type_: LongWord;
    timestamp: LongWord;
    windowID: LongWord;
    state: Byte;
    repeat_: Byte;
    padding2, padding3: Byte;
    keysym: TSDL_Keysym;
  end;

  TSDL_TextInputEvent = record
    type_: LongWord;
    timestamp: LongWord;
    windowID: LongWord;
    text: array[0..31] of Char;
  end;

  TSDL_MouseMotionEvent = record
    type_: LongWord;
    timestamp: LongWord;
    windowID: LongWord;
    which: LongWord;
    state: LongWord;
    x, y: LongInt;
    xrel, yrel: LongInt;
  end;

  TSDL_MouseButtonEvent = record
    type_: LongWord;
    timestamp: LongWord;
    windowID: LongWord;
    which: LongWord;
    button: Byte;
    state: Byte;
    clicks: Byte;
    padding1: Byte;
    x, y: LongInt;
  end;

  TSDL_MouseWheelEvent = record
    type_: LongWord;
    timestamp: LongWord;
    windowID: LongWord;
    which: LongWord;
    x, y: LongInt;
    direction: LongWord;
  end;

  TSDL_Event = record
    case LongInt of
      0: (type_: LongWord);
      1: (window: TSDL_WindowEvent);
      2: (key: TSDL_KeyboardEvent);
      3: (text: TSDL_TextInputEvent);
      4: (motion: TSDL_MouseMotionEvent);
      5: (button: TSDL_MouseButtonEvent);
      6: (wheel: TSDL_MouseWheelEvent);
      7: (padding: array[0..55] of Byte);
  end;

var
  SDL_Init: function(flags: LongWord): LongInt; cdecl;
  SDL_Quit: procedure; cdecl;
  SDL_GetError: function: PChar; cdecl;
  SDL_SetHint: function(name, value: PChar): LongInt; cdecl;
  SDL_GetTicks: function: LongWord; cdecl;

  SDL_CreateWindow: function(title: PChar; x, y, w, h: LongInt; flags: LongWord): PSDL_Window; cdecl;
  SDL_DestroyWindow: procedure(window: PSDL_Window); cdecl;
  SDL_SetWindowTitle: procedure(window: PSDL_Window; title: PChar); cdecl;
  SDL_GetWindowSize: procedure(window: PSDL_Window; w, h: PLongInt); cdecl;
  SDL_SetWindowMinimumSize: procedure(window: PSDL_Window; w, h: LongInt); cdecl;
  SDL_GetWindowFlags: function(window: PSDL_Window): LongWord; cdecl;
  SDL_MaximizeWindow: procedure(window: PSDL_Window); cdecl;
  SDL_MinimizeWindow: procedure(window: PSDL_Window); cdecl;
  SDL_RestoreWindow: procedure(window: PSDL_Window); cdecl;
  SDL_SetWindowFullscreen: function(window: PSDL_Window; flags: LongWord): LongInt; cdecl;
  { optional: nil with SDL older than 2.0.5 / 2.0.16 }
  SDL_SetWindowResizable: procedure(window: PSDL_Window; resizable: LongInt); cdecl;
  SDL_SetWindowAlwaysOnTop: procedure(window: PSDL_Window; onTop: LongInt); cdecl;

  SDL_CreateRenderer: function(window: PSDL_Window; index: LongInt; flags: LongWord): PSDL_Renderer; cdecl;
  SDL_DestroyRenderer: procedure(renderer: PSDL_Renderer); cdecl;
  SDL_GetRendererOutputSize: function(renderer: PSDL_Renderer; w, h: PLongInt): LongInt; cdecl;
  SDL_CreateTexture: function(renderer: PSDL_Renderer; format: LongWord; access, w, h: LongInt): PSDL_Texture; cdecl;
  SDL_DestroyTexture: procedure(texture: PSDL_Texture); cdecl;
  SDL_UpdateTexture: function(texture: PSDL_Texture; rect: Pointer; pixels: Pointer; pitch: LongInt): LongInt; cdecl;
  SDL_RenderClear: function(renderer: PSDL_Renderer): LongInt; cdecl;
  SDL_RenderCopy: function(renderer: PSDL_Renderer; texture: PSDL_Texture; src, dst: Pointer): LongInt; cdecl;
  SDL_RenderPresent: procedure(renderer: PSDL_Renderer); cdecl;

  SDL_PollEvent: function(event: Pointer): LongInt; cdecl;
  SDL_WaitEventTimeout: function(event: Pointer; timeout: LongInt): LongInt; cdecl;
  SDL_StartTextInput: procedure; cdecl;

  SDL_CreateSystemCursor: function(id: LongInt): PSDL_Cursor; cdecl;
  SDL_SetCursor: procedure(cursor: PSDL_Cursor); cdecl;

  SDL_SetClipboardText: function(text: PChar): LongInt; cdecl;
  SDL_GetClipboardText: function: PChar; cdecl;
  SDL_free: procedure(p: Pointer); cdecl;

{ Loads the SDL2 library. Returns '' on success, otherwise an explanation. }
function LoadSDL2: string;

implementation

uses
  SysUtils;

var
  LibHandle: TLibHandle = NilHandle;

function LoadSDL2: string;
const
  {$IF defined(WINDOWS)}
  Names: array[0..0] of string = ('SDL2.dll');
  {$ELSEIF defined(DARWIN)}
  Names: array[0..1] of string = ('libSDL2-2.0.0.dylib', 'libSDL2.dylib');
  {$ELSE}
  Names: array[0..1] of string = ('libSDL2-2.0.so.0', 'libSDL2.so');
  {$ENDIF}
var
  N, Missing: string;

  procedure Bind(var Proc; const Name: string);
  begin
    Pointer(Proc) := GetProcedureAddress(LibHandle, Name);
    if Pointer(Proc) = nil then
      Missing := Missing + ' ' + Name;
  end;

begin
  if LibHandle <> NilHandle then
    Exit('');
  for N in Names do
  begin
    LibHandle := LoadLibrary(N);
    if LibHandle <> NilHandle then
      Break;
  end;
  if LibHandle = NilHandle then
  begin
    {$IF defined(WINDOWS)}
    Exit('SDL2.dll was not found. Put it next to the program (download: https://github.com/libsdl-org/SDL/releases).');
    {$ELSEIF defined(DARWIN)}
    Exit('SDL2 was not found. Install it with: brew install sdl2');
    {$ELSE}
    Exit('SDL2 was not found. Install it with: sudo apt install libsdl2-2.0-0');
    {$ENDIF}
  end;

  Missing := '';
  Bind(SDL_Init, 'SDL_Init');
  Bind(SDL_Quit, 'SDL_Quit');
  Bind(SDL_GetError, 'SDL_GetError');
  Bind(SDL_SetHint, 'SDL_SetHint');
  Bind(SDL_GetTicks, 'SDL_GetTicks');
  Bind(SDL_CreateWindow, 'SDL_CreateWindow');
  Bind(SDL_DestroyWindow, 'SDL_DestroyWindow');
  Bind(SDL_SetWindowTitle, 'SDL_SetWindowTitle');
  Bind(SDL_GetWindowSize, 'SDL_GetWindowSize');
  Bind(SDL_SetWindowMinimumSize, 'SDL_SetWindowMinimumSize');
  Bind(SDL_GetWindowFlags, 'SDL_GetWindowFlags');
  Bind(SDL_MaximizeWindow, 'SDL_MaximizeWindow');
  Bind(SDL_MinimizeWindow, 'SDL_MinimizeWindow');
  Bind(SDL_RestoreWindow, 'SDL_RestoreWindow');
  Bind(SDL_SetWindowFullscreen, 'SDL_SetWindowFullscreen');
  Pointer(SDL_SetWindowResizable) := GetProcedureAddress(LibHandle, 'SDL_SetWindowResizable');
  Pointer(SDL_SetWindowAlwaysOnTop) := GetProcedureAddress(LibHandle, 'SDL_SetWindowAlwaysOnTop');
  Bind(SDL_CreateRenderer, 'SDL_CreateRenderer');
  Bind(SDL_DestroyRenderer, 'SDL_DestroyRenderer');
  Bind(SDL_GetRendererOutputSize, 'SDL_GetRendererOutputSize');
  Bind(SDL_CreateTexture, 'SDL_CreateTexture');
  Bind(SDL_DestroyTexture, 'SDL_DestroyTexture');
  Bind(SDL_UpdateTexture, 'SDL_UpdateTexture');
  Bind(SDL_RenderClear, 'SDL_RenderClear');
  Bind(SDL_RenderCopy, 'SDL_RenderCopy');
  Bind(SDL_RenderPresent, 'SDL_RenderPresent');
  Bind(SDL_PollEvent, 'SDL_PollEvent');
  Bind(SDL_WaitEventTimeout, 'SDL_WaitEventTimeout');
  Bind(SDL_StartTextInput, 'SDL_StartTextInput');
  Bind(SDL_CreateSystemCursor, 'SDL_CreateSystemCursor');
  Bind(SDL_SetCursor, 'SDL_SetCursor');
  Bind(SDL_SetClipboardText, 'SDL_SetClipboardText');
  Bind(SDL_GetClipboardText, 'SDL_GetClipboardText');
  Bind(SDL_free, 'SDL_free');
  if Missing <> '' then
    Exit('the installed SDL2 is too old (missing:' + Missing + ')');
  Result := '';
end;

end.
