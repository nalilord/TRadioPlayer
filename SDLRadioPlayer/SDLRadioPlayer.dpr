program SDLRadioPlayer;

{$APPTYPE GUI}

uses
{$IFDEF FPC}
  SysUtils,
{$ELSE}
  {$IF CompilerVersion >= 23.0}
  System.SysUtils,
  {$ELSE}
  SysUtils,
  {$IFEND}
{$ENDIF}
  SDLRadioPlayer.App in 'SDLRadioPlayer.App.pas';

var
  App: TSDLRadioPlayerApp;

begin
  App := TSDLRadioPlayerApp.Create;
  try
    Halt(App.Run);
  finally
    App.Free;
  end;
end.
