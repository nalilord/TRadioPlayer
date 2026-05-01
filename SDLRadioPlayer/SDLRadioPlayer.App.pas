unit SDLRadioPlayer.App;

interface

uses
{$IFDEF FPC}
  IniFiles,
  Math,
  SysUtils,
{$ELSE}
  {$IFDEF MSWINDOWS}
  Winapi.Windows,
  {$ENDIF}
  {$IF CompilerVersion >= 23.0}
  System.IniFiles,
  System.IOUtils,
  System.Math,
  System.StrUtils,
  System.SysUtils,
  {$ELSE}
  IniFiles,
  IOUtils,
  Math,
  StrUtils,
  SysUtils,
  {$IFEND}
{$ENDIF}
  SDL3Lite,
  Radio.Player,
  Radio.Types;

type
  TSDLRadioPlayerApp = class
  private const
    DEFAULT_URL = 'https://stream.radio38.de/radio38-live/mp3-192';
    WINDOW_WIDTH = 1280;
    WINDOW_HEIGHT = 820;
    URL_SCALE = 2.0;
    TEXT_SCALE = 1.5;
    SMALL_SCALE = 1.0;
  private
    FConfigPath: string;
    FDisplayBufferFill: Single;
    FDisplayPeakLeft: Single;
    FDisplayPeakRight: Single;
    FDisplayRMSLeft: Single;
    FDisplayRMSRight: Single;
    FDisplaySpectrum: TRadioSpectrumBins;
    FDisplaySpectrumPeaks: TRadioSpectrumBins;
    FInputFocused: Boolean;
    FLastAnimationTick: UInt64;
    FPlayer: TRadioPlayer;
    FQuitRequested: Boolean;
    FRenderer: PSDL_Renderer;
    FStatusText: string;
    FURL: string;
    FWindow: PSDL_Window;
    FWindowHeight: Integer;
    FWindowWidth: Integer;
    function BackendButtonLabel: string;
    function BuildBackendInfo: string;
    function ClipText(const Value: string; MaxWidth: Single; Scale: Single): string;
    function ConfigDir: string;
    function MakeRect(X, Y, W, H: Single): TSDL_FRect;
    function StepAnimated(CurrentValue, TargetValue, RiseRate, FallRate, DeltaSeconds: Single): Single;
    function PointInRect(X, Y: Single; const R: TSDL_FRect): Boolean;
    function SanitizeText(const Value: string): AnsiString;
    function StateText: string;
    procedure AppendText(const Value: string);
    procedure CycleBackend;
    procedure Draw;
    procedure DrawBackground;
    procedure DrawButton(const R: TSDL_FRect; const Caption: string; Highlighted: Boolean);
    procedure DrawHeader;
    procedure DrawLineText(X, Y: Single; const Value: string; Scale: Single = TEXT_SCALE);
    procedure DrawPanel(const R: TSDL_FRect; const Title: string);
    procedure DrawSpectrum(const R: TSDL_FRect);
    procedure DrawStatsPanel(const R: TSDL_FRect);
    procedure DrawStatusPanel(const R: TSDL_FRect);
    procedure DrawURLPanel(const R: TSDL_FRect);
    procedure DrawValueBar(const R: TSDL_FRect; Value: Single; FillR, FillG, FillB: Byte);
    procedure HandleError(Sender: TObject; const ErrorInfo: TRadioErrorInfo);
    procedure HandleReconnectAttempt(Sender: TObject; Attempt: Integer; DelayMS: Cardinal);
    procedure HandleReconnectFailed(Sender: TObject; Attempt: Integer; const ErrorInfo: TRadioErrorInfo);
    procedure HandleReconnectSucceeded(Sender: TObject; Attempt: Integer);
    procedure HandleStateChanged(Sender: TObject; State: TRadioPlayerState);
    procedure LoadConfig;
    procedure PasteClipboard;
    procedure ProcessButtonClick(X, Y: Single);
    procedure ProcessEvent(const Event: TSDL_Event);
    procedure RestartPlayback(const NewStatus: string);
    procedure ResetAnimation;
    procedure SaveConfig;
    procedure SetDrawColor(R, G, B: Byte; A: Byte = 255);
    procedure SetInputFocused(Value: Boolean);
    procedure SetStatus(const Text: string);
    procedure StopPlayback;
    procedure UpdateAnimation;
    procedure UpdateVolumeFromPoint(X: Single);
  public
    constructor Create;
    destructor Destroy; override;
    function Run: Integer;
  end;

implementation

type
  TAnsiBuilder = record
    class function FromString(const Value: string): AnsiString; static;
  end;

function CurrentTickMS: UInt64;
begin
{$IFDEF MSWINDOWS}
  Result := Winapi.Windows.GetTickCount64;
{$ELSE}
  Result := UInt64(Trunc(Now * 24 * 60 * 60 * 1000));
{$ENDIF}
end;

class function TAnsiBuilder.FromString(const Value: string): AnsiString;
begin
{$IFDEF FPC}
  Result := AnsiString(Value);
{$ELSE}
  Result := AnsiString(UTF8Encode(Value));
{$ENDIF}
end;

constructor TSDLRadioPlayerApp.Create;
begin
  inherited Create;
{$IFDEF FPC}
  FConfigPath := IncludeTrailingPathDelimiter(ConfigDir) + 'SDLRadioPlayer.ini';
{$ELSE}
  FConfigPath := TPath.Combine(ConfigDir, 'SDLRadioPlayer.ini');
{$ENDIF}
  FPlayer := TRadioPlayer.Create(nil);
  FPlayer.EventDispatchMode := redmMainThread;
  FPlayer.OutputSpectrumFFTSize := 1024;
  FPlayer.OutputSpectrumBinCount := 64;
  FPlayer.OutputSpectrumIntervalMS := 33;
  FPlayer.OnStateChangedData := HandleStateChanged;
  FPlayer.OnError := HandleError;
  FPlayer.OnReconnectAttempt := HandleReconnectAttempt;
  FPlayer.OnReconnectSucceeded := HandleReconnectSucceeded;
  FPlayer.OnReconnectFailed := HandleReconnectFailed;
  FURL := DEFAULT_URL;
  FWindowWidth := WINDOW_WIDTH;
  FWindowHeight := WINDOW_HEIGHT;
  FStatusText := 'Ready';
  ResetAnimation;
  if DirectoryExists(ConfigDir) or ForceDirectories(ConfigDir) then
    LoadConfig;
end;

destructor TSDLRadioPlayerApp.Destroy;
begin
  SaveConfig;
  FPlayer.Stop;
  FPlayer.Free;
  inherited Destroy;
end;

procedure TSDLRadioPlayerApp.AppendText(const Value: string);
begin
  FURL := FURL + Value;
end;

function TSDLRadioPlayerApp.BackendButtonLabel: string;
begin
  Result := 'BACKEND ' + UpperCase(OutputBackendName(FPlayer.OutputBackend));
end;

function TSDLRadioPlayerApp.BuildBackendInfo: string;
begin
  Result := 'BACKEND ' + UpperCase(OutputBackendName(FPlayer.OutputBackend)) +
    '   VOLUME ' + IntToStr(Round(FPlayer.Volume * 100)) + '%' +
    '   MUTED ' + UpperCase(BoolToStr(FPlayer.Muted, True));
{$IFDEF MSWINDOWS}
  if FPlayer.OutputBackend = robWASAPI then
    Result := Result + '   MODE ' + UpperCase(WASAPIVolumeModeName(FPlayer.WasapiVolumeMode));
{$ENDIF}
end;

function TSDLRadioPlayerApp.ClipText(const Value: string; MaxWidth: Single; Scale: Single): string;
var
  MaxChars: Integer;
begin
  MaxChars := Trunc(MaxWidth / (SDL_DEBUG_TEXT_FONT_CHARACTER_SIZE * Scale));
  if MaxChars < 1 then
    Exit('');
  if Length(Value) <= MaxChars then
    Exit(Value);
  if MaxChars <= 3 then
    Exit(Copy(Value, 1, MaxChars));
  Result := Copy(Value, 1, MaxChars - 3) + '...';
end;

function TSDLRadioPlayerApp.ConfigDir: string;
begin
{$IFDEF FPC}
  Result := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + 'sdl-radio-player';
{$ELSE}
  Result := TPath.Combine(TPath.GetHomePath, '.sdl-radio-player');
{$ENDIF}
end;

procedure TSDLRadioPlayerApp.CycleBackend;
begin
  case FPlayer.OutputBackend of
{$IFDEF MSWINDOWS}
    robWASAPI:
      FPlayer.OutputBackend := robWaveOut;
    robWaveOut:
      FPlayer.OutputBackend := robWASAPI;
{$ELSE}
    robPulseAudio:
      FPlayer.OutputBackend := robAPlay;
    robAPlay:
      FPlayer.OutputBackend := robPulseAudio;
{$ENDIF}
  else
{$IFDEF MSWINDOWS}
    FPlayer.OutputBackend := robWASAPI;
{$ELSE}
    FPlayer.OutputBackend := robPulseAudio;
{$ENDIF}
  end;
  RestartPlayback('Backend changed to ' + OutputBackendName(FPlayer.OutputBackend));
end;

procedure TSDLRadioPlayerApp.Draw;
var
  ActionsRect: TSDL_FRect;
  SpectrumRect: TSDL_FRect;
  StatsRect: TSDL_FRect;
  StatusRect: TSDL_FRect;
  UrlRect: TSDL_FRect;
begin
  UpdateAnimation;
  DrawBackground;
  DrawHeader;

  UrlRect := MakeRect(32, 96, FWindowWidth - 64, 72);
  ActionsRect := MakeRect(32, 188, FWindowWidth - 64, 54);
  StatusRect := MakeRect(32, 262, 520, 250);
  StatsRect := MakeRect(572, 262, FWindowWidth - 604, 250);
  SpectrumRect := MakeRect(32, 532, FWindowWidth - 64, FWindowHeight - 564);

  DrawURLPanel(UrlRect);

  DrawButton(MakeRect(ActionsRect.x, ActionsRect.y, 120, ActionsRect.h), 'PLAY', FPlayer.State = rpsPlaying);
  DrawButton(MakeRect(ActionsRect.x + 136, ActionsRect.y, 120, ActionsRect.h), 'STOP', FPlayer.State in [rpsStopping, rpsStopped, rpsIdle]);
  DrawButton(MakeRect(ActionsRect.x + 272, ActionsRect.y, 120, ActionsRect.h), 'RESTART', False);
  DrawButton(MakeRect(ActionsRect.x + 408, ActionsRect.y, 120, ActionsRect.h), 'MUTE', FPlayer.Muted);
  DrawButton(MakeRect(ActionsRect.x + 544, ActionsRect.y, 200, ActionsRect.h), BackendButtonLabel, False);
  DrawButton(MakeRect(ActionsRect.x + 760, ActionsRect.y, 120, ActionsRect.h), 'VOL -', False);
  DrawButton(MakeRect(ActionsRect.x + 896, ActionsRect.y, 120, ActionsRect.h), 'VOL +', False);

  DrawStatusPanel(StatusRect);
  DrawStatsPanel(StatsRect);
  DrawSpectrum(SpectrumRect);

  SDL_RenderPresent(FRenderer);
end;

procedure TSDLRadioPlayerApp.ResetAnimation;
begin
  FDisplayBufferFill := 0.0;
  FDisplayRMSLeft := 0.0;
  FDisplayRMSRight := 0.0;
  FDisplayPeakLeft := 0.0;
  FDisplayPeakRight := 0.0;
  SetLength(FDisplaySpectrum, 0);
  SetLength(FDisplaySpectrumPeaks, 0);
  FLastAnimationTick := CurrentTickMS;
end;

procedure TSDLRadioPlayerApp.DrawBackground;
var
  Band: TSDL_FRect;
begin
  SetDrawColor(12, 18, 26);
  SDL_RenderClear(FRenderer);

  Band := MakeRect(0, 0, FWindowWidth, 88);
  SetDrawColor(18, 46, 64);
  SDL_RenderFillRect(FRenderer, @Band);

  Band := MakeRect(0, FWindowHeight - 120, FWindowWidth, 120);
  SetDrawColor(20, 34, 24);
  SDL_RenderFillRect(FRenderer, @Band);
end;

procedure TSDLRadioPlayerApp.DrawButton(const R: TSDL_FRect; const Caption: string; Highlighted: Boolean);
begin
  if Highlighted then
    SetDrawColor(214, 98, 55)
  else
    SetDrawColor(36, 59, 79);
  SDL_RenderFillRect(FRenderer, @R);
  SetDrawColor(238, 232, 222);
  SDL_RenderRect(FRenderer, @R);
  DrawLineText(R.x + 12, R.y + 16, Caption, SMALL_SCALE);
end;

procedure TSDLRadioPlayerApp.DrawHeader;
begin
  SetDrawColor(236, 210, 170);
  DrawLineText(32, 20, 'SDL RADIO PLAYER', 2.5);
  SetDrawColor(214, 228, 238);
  DrawLineText(32, 58, 'GUI HOST FOR TRADIOPLAYER', SMALL_SCALE);
end;

procedure TSDLRadioPlayerApp.DrawLineText(X, Y: Single; const Value: string; Scale: Single);
var
  Output: AnsiString;
begin
  Output := SanitizeText(Value);
  SDL_SetRenderScale(FRenderer, Scale, Scale);
  SDL_RenderDebugText(FRenderer, X / Scale, Y / Scale, PAnsiChar(Output));
  SDL_SetRenderScale(FRenderer, 1.0, 1.0);
end;

procedure TSDLRadioPlayerApp.DrawPanel(const R: TSDL_FRect; const Title: string);
begin
  SetDrawColor(24, 30, 40, 220);
  SDL_RenderFillRect(FRenderer, @R);
  SetDrawColor(66, 88, 110);
  SDL_RenderRect(FRenderer, @R);
  SetDrawColor(236, 210, 170);
  DrawLineText(R.x + 14, R.y + 12, Title, SMALL_SCALE);
end;

procedure TSDLRadioPlayerApp.DrawSpectrum(const R: TSDL_FRect);
var
  I: Integer;
  Spectrum: TRadioSpectrumData;
  BarRect: TSDL_FRect;
  BottomY: Single;
  InnerHeight: Single;
  InnerWidth: Single;
  LabelText: string;
  PeakRect: TSDL_FRect;
begin
  DrawPanel(R, 'OUTPUT SPECTRUM');
  Spectrum := FPlayer.LastSpectrum;
  InnerWidth := R.w - 28;
  InnerHeight := R.h - 64;
  BottomY := R.y + R.h - 18;

  if Length(FDisplaySpectrum) = 0 then
  begin
    SetDrawColor(190, 202, 212);
    DrawLineText(R.x + 16, R.y + 48, 'NO SPECTRUM DATA YET', SMALL_SCALE);
    Exit;
  end;

  for I := 0 to High(FDisplaySpectrum) do
  begin
    BarRect.x := R.x + 14 + (InnerWidth / Length(FDisplaySpectrum)) * I;
    BarRect.w := Max(2.0, (InnerWidth / Length(FDisplaySpectrum)) - 2.0);
    BarRect.h := EnsureRange(FDisplaySpectrum[I], 0.0, 1.0) * InnerHeight;
    BarRect.y := BottomY - BarRect.h;
    SetDrawColor(66, 180, 160);
    SDL_RenderFillRect(FRenderer, @BarRect);

    PeakRect.x := BarRect.x;
    PeakRect.w := BarRect.w;
    PeakRect.h := 3.0;
    PeakRect.y := BottomY - (EnsureRange(FDisplaySpectrumPeaks[I], 0.0, 1.0) * InnerHeight) - PeakRect.h;
    SetDrawColor(236, 210, 170);
    SDL_RenderFillRect(FRenderer, @PeakRect);
  end;

  SetDrawColor(190, 202, 212);
  LabelText := Format('FFT %d  BINS %d  LATENCY %d MS',
    [Spectrum.FFTSize, Length(FDisplaySpectrum), Spectrum.TotalLatencyMS]);
  DrawLineText(R.x + 16, R.y + R.h - 36, LabelText, SMALL_SCALE);
end;

procedure TSDLRadioPlayerApp.DrawStatsPanel(const R: TSDL_FRect);
var
  LeftPeakRect: TSDL_FRect;
  LeftVuRect: TSDL_FRect;
  RightPeakRect: TSDL_FRect;
  RightVuRect: TSDL_FRect;
  Stats: TRadioBufferStats;
begin
  DrawPanel(R, 'RUNTIME STATS');
  Stats := FPlayer.Stats;

  SetDrawColor(216, 226, 232);
  DrawLineText(R.x + 16, R.y + 46,
    ClipText(Format('PACKETS %d (%d/S)  FRAMES %d (%d/S)',
      [Stats.PacketsReceived, Stats.PacketRate, Stats.DecodedFrames, Stats.DecodeRate]),
      R.w - 32, TEXT_SCALE), TEXT_SCALE);
  DrawLineText(R.x + 16, R.y + 78,
    ClipText(Format('INPUT %d KBPS  OUTPUT %d KBPS',
      [Stats.InputBitrate div 1000, Stats.OutputBitrate div 1000]),
      R.w - 32, TEXT_SCALE), TEXT_SCALE);
  DrawLineText(R.x + 16, R.y + 110,
    ClipText(Format('BUFFER %.1f%%  QUEUE %d MS  OUTPUT %d MS',
      [Stats.BufferFillPercent, Stats.QueueDurationMS, Stats.OutputLatencyMS]),
      R.w - 32, TEXT_SCALE), TEXT_SCALE);
  DrawLineText(R.x + 16, R.y + 142,
    ClipText(Format('UNDERFLOWS %d  RECONNECTS %d  OK %d  FAIL %d',
      [Stats.UnderflowCount, Stats.ReconnectCount, Stats.ReconnectSuccessCount, Stats.ReconnectFailureCount]),
      R.w - 32, TEXT_SCALE), TEXT_SCALE);
  DrawLineText(R.x + 16, R.y + 174,
    ClipText(Format('VU L %.2f / %.2f   R %.2f / %.2f',
      [FDisplayRMSLeft, FDisplayPeakLeft, FDisplayRMSRight, FDisplayPeakRight]),
      R.w - 32, TEXT_SCALE), TEXT_SCALE);

  DrawValueBar(MakeRect(R.x + 16, R.y + 206, R.w - 32, 12), FDisplayBufferFill, 66, 180, 160);
  LeftVuRect := MakeRect(R.x + 16, R.y + 226, (R.w - 40) * 0.5, 10);
  RightVuRect := MakeRect(R.x + 20 + (R.w - 40) * 0.5, R.y + 226, (R.w - 40) * 0.5, 10);
  DrawValueBar(LeftVuRect, FDisplayRMSLeft, 214, 98, 55);
  DrawValueBar(RightVuRect, FDisplayRMSRight, 236, 184, 82);

  LeftPeakRect := MakeRect(LeftVuRect.x + (LeftVuRect.w * EnsureRange(FDisplayPeakLeft, 0.0, 1.0)) - 1.0,
    LeftVuRect.y - 1.0, 2.0, LeftVuRect.h + 2.0);
  RightPeakRect := MakeRect(RightVuRect.x + (RightVuRect.w * EnsureRange(FDisplayPeakRight, 0.0, 1.0)) - 1.0,
    RightVuRect.y - 1.0, 2.0, RightVuRect.h + 2.0);
  SetDrawColor(236, 210, 170);
  SDL_RenderFillRect(FRenderer, @LeftPeakRect);
  SDL_RenderFillRect(FRenderer, @RightPeakRect);
end;

procedure TSDLRadioPlayerApp.DrawStatusPanel(const R: TSDL_FRect);
var
  Meta: TStreamMetadata;
begin
  DrawPanel(R, 'NOW PLAYING');
  Meta := FPlayer.Metadata;

  SetDrawColor(240, 238, 234);
  DrawLineText(R.x + 16, R.y + 46, ClipText('STATE   ' + StateText, R.w - 32, TEXT_SCALE), TEXT_SCALE);
  DrawLineText(R.x + 16, R.y + 78, ClipText('STATUS  ' + FStatusText, R.w - 32, TEXT_SCALE), TEXT_SCALE);
  DrawLineText(R.x + 16, R.y + 110, ClipText('STATION ' + Meta.StationName, R.w - 32, TEXT_SCALE), TEXT_SCALE);
  DrawLineText(R.x + 16, R.y + 142, ClipText('TITLE   ' + Meta.StreamTitle, R.w - 32, TEXT_SCALE), TEXT_SCALE);
  DrawLineText(R.x + 16, R.y + 174, ClipText('CODEC   ' + Meta.CodecName, R.w - 32, TEXT_SCALE), TEXT_SCALE);
  DrawLineText(R.x + 16, R.y + 206, ClipText(BuildBackendInfo, R.w - 32, SMALL_SCALE), SMALL_SCALE);
  DrawValueBar(MakeRect(R.x + 16, R.y + 228, R.w - 32, 12), FPlayer.Volume, 214, 98, 55);
end;

procedure TSDLRadioPlayerApp.DrawURLPanel(const R: TSDL_FRect);
var
  DisplayText: string;
begin
  DrawPanel(R, 'STREAM URL');
  if FInputFocused then
    SetDrawColor(214, 98, 55)
  else
    SetDrawColor(76, 96, 118);
  SDL_RenderRect(FRenderer, @R);

  DisplayText := ClipText(FURL, R.w - 32, URL_SCALE);
  SetDrawColor(245, 244, 240);
  DrawLineText(R.x + 16, R.y + 28, DisplayText, URL_SCALE);
end;

procedure TSDLRadioPlayerApp.DrawValueBar(const R: TSDL_FRect; Value: Single; FillR, FillG, FillB: Byte);
var
  FillRect: TSDL_FRect;
begin
  SetDrawColor(48, 56, 64);
  SDL_RenderFillRect(FRenderer, @R);
  SetDrawColor(106, 116, 126);
  SDL_RenderRect(FRenderer, @R);

  FillRect := R;
  FillRect.w := EnsureRange(Value, 0.0, 1.0) * R.w;
  SetDrawColor(FillR, FillG, FillB);
  SDL_RenderFillRect(FRenderer, @FillRect);
end;

procedure TSDLRadioPlayerApp.HandleError(Sender: TObject; const ErrorInfo: TRadioErrorInfo);
begin
  SetStatus(ErrorInfo.MessageText);
end;

procedure TSDLRadioPlayerApp.HandleReconnectAttempt(Sender: TObject; Attempt: Integer; DelayMS: Cardinal);
begin
  SetStatus(Format('Reconnect %d in %d ms', [Attempt, DelayMS]));
end;

procedure TSDLRadioPlayerApp.HandleReconnectFailed(Sender: TObject; Attempt: Integer;
  const ErrorInfo: TRadioErrorInfo);
begin
  SetStatus(Format('Reconnect failed: %s', [ErrorInfo.MessageText]));
end;

procedure TSDLRadioPlayerApp.HandleReconnectSucceeded(Sender: TObject; Attempt: Integer);
begin
  SetStatus(Format('Reconnect succeeded on attempt %d', [Attempt]));
end;

procedure TSDLRadioPlayerApp.HandleStateChanged(Sender: TObject; State: TRadioPlayerState);
begin
  case State of
    rpsOpening:
      SetStatus('Opening stream');
    rpsBuffering:
      SetStatus('Buffering audio');
    rpsPlaying:
      SetStatus('Playing');
    rpsReconnecting:
      SetStatus('Reconnecting');
    rpsStopping:
      SetStatus('Stopping');
    rpsStopped:
      SetStatus('Stopped');
    rpsError:
      SetStatus('Error');
  else
    SetStatus('Idle');
  end;
end;

procedure TSDLRadioPlayerApp.LoadConfig;
var
  Ini: TMemIniFile;
begin
  if not FileExists(FConfigPath) then
    Exit;
  Ini := TMemIniFile.Create(FConfigPath);
  try
    FURL := Ini.ReadString('Player', 'LastURL', FURL);
    FPlayer.Volume := EnsureRange(Ini.ReadFloat('Player', 'Volume', FPlayer.Volume), 0.0, 1.0);
    FPlayer.Muted := Ini.ReadBool('Player', 'Muted', False);
    FPlayer.BufferTimeMS := Ini.ReadInteger('Player', 'BufferTimeMS', FPlayer.BufferTimeMS);
    FPlayer.PrebufferTimeMS := Ini.ReadInteger('Player', 'PrebufferTimeMS', FPlayer.PrebufferTimeMS);
    FWindowWidth := Max(960, Ini.ReadInteger('Window', 'Width', FWindowWidth));
    FWindowHeight := Max(640, Ini.ReadInteger('Window', 'Height', FWindowHeight));
{$IFDEF MSWINDOWS}
    if SameText(Ini.ReadString('Player', 'Backend', OutputBackendName(FPlayer.OutputBackend)), 'waveout') then
      FPlayer.OutputBackend := robWaveOut
    else
      FPlayer.OutputBackend := robWASAPI;
{$ELSE}
    if SameText(Ini.ReadString('Player', 'Backend', OutputBackendName(FPlayer.OutputBackend)), 'aplay') then
      FPlayer.OutputBackend := robAPlay
    else
      FPlayer.OutputBackend := robPulseAudio;
{$ENDIF}
  finally
    Ini.Free;
  end;
end;

function TSDLRadioPlayerApp.MakeRect(X, Y, W, H: Single): TSDL_FRect;
begin
  Result.x := X;
  Result.y := Y;
  Result.w := W;
  Result.h := H;
end;

function TSDLRadioPlayerApp.StepAnimated(CurrentValue, TargetValue, RiseRate, FallRate,
  DeltaSeconds: Single): Single;
var
  Rate: Single;
begin
  if TargetValue >= CurrentValue then
    Rate := RiseRate
  else
    Rate := FallRate;

  if DeltaSeconds <= 0.0 then
    Exit(TargetValue);

  Result := CurrentValue + (TargetValue - CurrentValue) *
    EnsureRange(DeltaSeconds * Rate, 0.0, 1.0);
end;

procedure TSDLRadioPlayerApp.PasteClipboard;
var
  Clip: PAnsiChar;
begin
  if not SDL_HasClipboardText then
    Exit;
  Clip := SDL_GetClipboardText;
  try
    if Assigned(Clip) then
      AppendText(UTF8ToString(UTF8String(AnsiString(Clip))));
  finally
    SDL_free(Clip);
  end;
end;

function TSDLRadioPlayerApp.PointInRect(X, Y: Single; const R: TSDL_FRect): Boolean;
begin
  Result := (X >= R.x) and (Y >= R.y) and (X <= R.x + R.w) and (Y <= R.y + R.h);
end;

procedure TSDLRadioPlayerApp.ProcessButtonClick(X, Y: Single);
var
  ActionsY: Single;
  UrlRect: TSDL_FRect;
  VolumeRect: TSDL_FRect;
begin
  UrlRect := MakeRect(32, 96, FWindowWidth - 64, 72);
  if PointInRect(X, Y, UrlRect) then
  begin
    SetInputFocused(True);
    Exit;
  end;
  SetInputFocused(False);

  ActionsY := 188;
  if PointInRect(X, Y, MakeRect(32, ActionsY, 120, 54)) then
    RestartPlayback('Opening stream')
  else if PointInRect(X, Y, MakeRect(168, ActionsY, 120, 54)) then
    StopPlayback
  else if PointInRect(X, Y, MakeRect(304, ActionsY, 120, 54)) then
    RestartPlayback('Restarting stream')
  else if PointInRect(X, Y, MakeRect(440, ActionsY, 120, 54)) then
  begin
    FPlayer.Muted := not FPlayer.Muted;
    SetStatus(IfThen(FPlayer.Muted, 'Muted', 'Unmuted'));
  end
  else if PointInRect(X, Y, MakeRect(576, ActionsY, 200, 54)) then
    CycleBackend
  else if PointInRect(X, Y, MakeRect(792, ActionsY, 120, 54)) then
    FPlayer.Volume := EnsureRange(FPlayer.Volume - 0.05, 0.0, 1.0)
  else if PointInRect(X, Y, MakeRect(928, ActionsY, 120, 54)) then
    FPlayer.Volume := EnsureRange(FPlayer.Volume + 0.05, 0.0, 1.0);

  VolumeRect := MakeRect(48, 490, 488, 12);
  if PointInRect(X, Y, VolumeRect) then
    UpdateVolumeFromPoint(X);
end;

procedure TSDLRadioPlayerApp.ProcessEvent(const Event: TSDL_Event);
var
  Pasted: Boolean;
begin
  case Event.type_ of
    SDL_EVENT_QUIT:
      FQuitRequested := True;
    SDL_EVENT_WINDOW_CLOSE_REQUESTED:
      FQuitRequested := True;
    SDL_EVENT_WINDOW_RESIZED, SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
      begin
        FWindowWidth := Event.window.data1;
        FWindowHeight := Event.window.data2;
      end;
    SDL_EVENT_MOUSE_BUTTON_DOWN:
      if Event.button.down then
        ProcessButtonClick(Event.button.x, Event.button.y);
    SDL_EVENT_TEXT_INPUT:
      if FInputFocused and Assigned(Event.text.text) then
        AppendText(UTF8ToString(UTF8String(AnsiString(Event.text.text))));
    SDL_EVENT_KEY_DOWN:
      begin
        if Event.key.key = SDLK_ESCAPE then
        begin
          if FInputFocused then
            SetInputFocused(False)
          else
            FQuitRequested := True;
        end
        else if Event.key.key = SDLK_TAB then
          SetInputFocused(not FInputFocused)
        else if FInputFocused and (Event.key.key = SDLK_BACKSPACE) then
        begin
          if Length(FURL) > 0 then
            Delete(FURL, Length(FURL), 1);
        end
        else if FInputFocused and ((Event.key.key = SDLK_RETURN) or (Event.key.key = SDLK_RETURN2)) then
          RestartPlayback('Opening stream')
        else if FInputFocused and (Event.key.key = SDLK_v) then
        begin
          Pasted := (Event.key.mod_ and SDL_KMOD_CTRL) <> 0;
          if Pasted then
            PasteClipboard;
        end;
      end;
  end;
end;

procedure TSDLRadioPlayerApp.RestartPlayback(const NewStatus: string);
begin
  if Trim(FURL) = '' then
    Exit;
  SetStatus(NewStatus);
  FPlayer.Stop;
  FPlayer.Play(FURL);
end;

function TSDLRadioPlayerApp.Run: Integer;
var
  Event: TSDL_Event;
  TitleText: AnsiString;
begin
  Result := 1;
  if not SDL_Init(SDL_INIT_VIDEO) then
    Exit;
  try
    TitleText := TAnsiBuilder.FromString('SDLRadioPlayer');
    if not SDL_CreateWindowAndRenderer(PAnsiChar(TitleText), FWindowWidth, FWindowHeight, 0, @FWindow, @FRenderer) then
      Exit;
    try
      SDL_StartTextInput(FWindow);
      SetInputFocused(True);
      RestartPlayback('Opening stream');
      while not FQuitRequested do
      begin
        TRadioPlayer.PumpMainThreadEvents(0);
        while SDL_PollEvent(@Event) do
          ProcessEvent(Event);
        Draw;
        SDL_Delay(33);
      end;
      Result := 0;
    finally
      SDL_StopTextInput(FWindow);
      SDL_DestroyRenderer(FRenderer);
      SDL_DestroyWindow(FWindow);
    end;
  finally
    SDL_Quit;
  end;
end;

function TSDLRadioPlayerApp.SanitizeText(const Value: string): AnsiString;
var
  I: Integer;
  C: Char;
  Output: AnsiString;
begin
  SetLength(Output, Length(Value));
  for I := 1 to Length(Value) do
  begin
    C := Value[I];
    if (Ord(C) >= 32) and (Ord(C) <= 126) then
      Output[I] := AnsiChar(C)
    else
      Output[I] := '?';
  end;
  Result := Output;
end;

function TSDLRadioPlayerApp.StateText: string;
begin
  case FPlayer.State of
    rpsOpening:
      Result := 'OPENING';
    rpsBuffering:
      Result := 'BUFFERING';
    rpsPlaying:
      Result := 'PLAYING';
    rpsReconnecting:
      Result := 'RECONNECTING';
    rpsStopping:
      Result := 'STOPPING';
    rpsStopped:
      Result := 'STOPPED';
    rpsError:
      Result := 'ERROR';
  else
    Result := 'IDLE';
  end;
end;

procedure TSDLRadioPlayerApp.SaveConfig;
var
  Ini: TMemIniFile;
begin
  if not (DirectoryExists(ConfigDir) or ForceDirectories(ConfigDir)) then
    Exit;
  Ini := TMemIniFile.Create(FConfigPath);
  try
    Ini.WriteString('Player', 'LastURL', FURL);
    Ini.WriteString('Player', 'Backend', OutputBackendName(FPlayer.OutputBackend));
    Ini.WriteFloat('Player', 'Volume', FPlayer.Volume);
    Ini.WriteBool('Player', 'Muted', FPlayer.Muted);
    Ini.WriteInteger('Player', 'BufferTimeMS', FPlayer.BufferTimeMS);
    Ini.WriteInteger('Player', 'PrebufferTimeMS', FPlayer.PrebufferTimeMS);
    Ini.WriteInteger('Window', 'Width', FWindowWidth);
    Ini.WriteInteger('Window', 'Height', FWindowHeight);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
end;

procedure TSDLRadioPlayerApp.SetDrawColor(R, G, B: Byte; A: Byte);
begin
  SDL_SetRenderDrawColor(FRenderer, R, G, B, A);
end;

procedure TSDLRadioPlayerApp.SetInputFocused(Value: Boolean);
begin
  FInputFocused := Value;
  if not Assigned(FWindow) then
    Exit;
  if Value then
    SDL_StartTextInput(FWindow)
  else
    SDL_StopTextInput(FWindow);
end;

procedure TSDLRadioPlayerApp.SetStatus(const Text: string);
begin
  FStatusText := Text;
end;

procedure TSDLRadioPlayerApp.StopPlayback;
begin
  SetStatus('Stopped');
  FPlayer.Stop;
end;

procedure TSDLRadioPlayerApp.UpdateAnimation;
const
  BAR_RISE_RATE = 10.0;
  BAR_FALL_RATE = 2.8;
  PEAK_RISE_RATE = 16.0;
  PEAK_FALL_RATE = 0.8;
  BUFFER_RISE_RATE = 6.0;
  BUFFER_FALL_RATE = 2.2;
var
  ActiveOutput: Boolean;
  DeltaSeconds: Single;
  I: Integer;
  NowTick: UInt64;
  Spectrum: TRadioSpectrumData;
  Stats: TRadioBufferStats;
  TargetBin: Single;
begin
  NowTick := CurrentTickMS;
  if FLastAnimationTick = 0 then
    DeltaSeconds := 0.0
  else
    DeltaSeconds := (NowTick - FLastAnimationTick) / 1000.0;
  FLastAnimationTick := NowTick;
  DeltaSeconds := EnsureRange(DeltaSeconds, 0.0, 0.1);

  Stats := FPlayer.Stats;
  Spectrum := FPlayer.LastSpectrum;
  ActiveOutput := FPlayer.State in [rpsOpening, rpsBuffering, rpsPlaying, rpsReconnecting];

  FDisplayBufferFill := StepAnimated(FDisplayBufferFill,
    EnsureRange(IfThen(ActiveOutput, Stats.BufferFillPercent / 100.0, 0.0), 0.0, 1.0),
    BUFFER_RISE_RATE, BUFFER_FALL_RATE, DeltaSeconds);
  FDisplayRMSLeft := StepAnimated(FDisplayRMSLeft,
    EnsureRange(IfThen(ActiveOutput, Stats.RMSLeft, 0.0), 0.0, 1.0),
    BAR_RISE_RATE, BAR_FALL_RATE, DeltaSeconds);
  FDisplayRMSRight := StepAnimated(FDisplayRMSRight,
    EnsureRange(IfThen(ActiveOutput, Stats.RMSRight, 0.0), 0.0, 1.0),
    BAR_RISE_RATE, BAR_FALL_RATE, DeltaSeconds);
  FDisplayPeakLeft := StepAnimated(FDisplayPeakLeft,
    EnsureRange(IfThen(ActiveOutput, Stats.PeakLeft, 0.0), 0.0, 1.0),
    PEAK_RISE_RATE, PEAK_FALL_RATE, DeltaSeconds);
  FDisplayPeakRight := StepAnimated(FDisplayPeakRight,
    EnsureRange(IfThen(ActiveOutput, Stats.PeakRight, 0.0), 0.0, 1.0),
    PEAK_RISE_RATE, PEAK_FALL_RATE, DeltaSeconds);

  if Length(Spectrum.Bins) <> Length(FDisplaySpectrum) then
  begin
    SetLength(FDisplaySpectrum, Length(Spectrum.Bins));
    SetLength(FDisplaySpectrumPeaks, Length(Spectrum.Bins));
    for I := 0 to High(FDisplaySpectrum) do
    begin
      FDisplaySpectrum[I] := 0.0;
      FDisplaySpectrumPeaks[I] := 0.0;
    end;
  end;

  for I := 0 to High(FDisplaySpectrum) do
  begin
    if ActiveOutput and (I <= High(Spectrum.Bins)) then
      TargetBin := EnsureRange(Spectrum.Bins[I], 0.0, 1.0)
    else
      TargetBin := 0.0;

    FDisplaySpectrum[I] := StepAnimated(FDisplaySpectrum[I], TargetBin,
      BAR_RISE_RATE, BAR_FALL_RATE, DeltaSeconds);
    FDisplaySpectrumPeaks[I] := StepAnimated(FDisplaySpectrumPeaks[I], TargetBin,
      PEAK_RISE_RATE, PEAK_FALL_RATE, DeltaSeconds);
  end;
end;

procedure TSDLRadioPlayerApp.UpdateVolumeFromPoint(X: Single);
var
  Relative: Single;
begin
  Relative := (X - 48) / 488;
  FPlayer.Volume := EnsureRange(Relative, 0.0, 1.0);
end;

end.
