unit Radio.Player;

interface

uses
{$IFDEF FPC}
  Classes,
  Math,
  SysUtils,
  SyncObjs,
{$ELSE}
  System.Classes,
  System.Math,
  System.SysUtils,
  System.SyncObjs,
{$ENDIF}
{$IFDEF MSWINDOWS}
  {$IF CompilerVersion >= 23.0}
  Winapi.ActiveX,
  {$ELSE}
  ActiveX,
  {$IFEND}
{$ENDIF}
  libavcodec,
  libavcodec_codec_id,
  libavcodec_packet,
  libavutil_error,
  libavutil_frame,
  libavutil_samplefmt,
  Radio.Decoder,
  Radio.EventBus,
  Radio.FFmpeg.Api,
  Radio.FFmpeg,
  Radio.Logging,
  Radio.Metadata,
  Radio.Output,
{$IFDEF MSWINDOWS}
  {$IFDEF RADIO_HAS_WASAPI}
  Radio.Output.WASAPI,
  {$ENDIF}
  Radio.Output.WaveOut,
{$ENDIF}
{$IFDEF LINUX}
  Radio.Output.APlay,
  Radio.Output.PulseAudio,
{$ENDIF}
  Radio.PCMBuffer,
  Radio.Platform,
  Radio.Resampler,
  Radio.Spectrum,
  Radio.StreamClient,
  Radio.Types;

type
  TRadioPlayer = class(TComponent)
  private
    type
      TRadioWorkerThread = class(TThread)
      private
        FOwner: TRadioPlayer;
      protected
        procedure Execute; override;
      public
        constructor Create(AOwner: TRadioPlayer);
      end;
  private
    FCriticalSection: TCriticalSection;
    FStopEvent: TEvent;
    FWorker: TRadioWorkerThread;
    FURL: string;
    FState: TRadioPlayerState;
    FMetadata: TStreamMetadata;
    FLastSpectrum: TRadioSpectrumData;
    FStats: TRadioBufferStats;
    FReconnectPolicy: TRadioReconnectPolicy;
    FOutputBackend: TRadioOutputBackend;
    FActiveOutput: TAudioOutput;
    FBufferTimeMS: Integer;
    FEventDispatchMode: TRadioEventDispatchMode;
    FEventBus: TRadioEventBus;
    FOutputSpectrumAnalyzer: TRadioSpectrumAnalyzer;
    FOutputSpectrumBinCount: Integer;
    FOutputSpectrumEnabled: Boolean;
    FOutputSpectrumFFTSize: Integer;
    FOutputSpectrumIntervalMS: Cardinal;
    FVolume: Single;
    FMuted: Boolean;
    FOutputFailureMessage: string;
    FPrebufferTimeMS: Integer;
    FWasapiDeviceId: string;
    FWasapiVolumeMode: TRadioWASAPIVolumeMode;
    FLogger: IRadioLogger;
    FOnStateChanged: TNotifyEvent;
    FOnStateChangedData: TStateChangedEvent;
    FOnMetadataChanged: TNotifyEvent;
    FOnMetadataChangedData: TMetadataChangedEvent;
    FOnError: TRadioErrorEvent;
    FOnBufferStats: TBufferStatsEvent;
    FOnSpectrum: TSpectrumEvent;
    FOnReconnectAttempt: TReconnectAttemptEvent;
    FOnReconnectSucceeded: TReconnectSucceededEvent;
    FOnReconnectFailed: TReconnectFailedEvent;
    function GetMetadata: TStreamMetadata;
    function GetLastSpectrum: TRadioSpectrumData;
    function GetState: TRadioPlayerState;
    function GetStats: TRadioBufferStats;
    procedure ApplyStatsBufferSnapshot(PcmBuffer: TRadioPCMBuffer; Output: TAudioOutput;
      BytesPerSecond, BufferCapacityBytes, PrebufferBytes: Integer);
    procedure ApplyStatsRates(ElapsedMS: Cardinal; IntervalPackets, IntervalFrames: Integer;
      IntervalInputBytes, IntervalOutputBytes: Int64; StartTick: Cardinal);
    procedure ApplyStatsLevels(PeakLeft, PeakRight, RMSLeft, RMSRight: Single);
    procedure EnsureSpectrumAnalyzer;
    procedure HandleBufferUnderflow;
    function IsStopRequested: Boolean;
    function ReadOutputFailureMessage: string;
    function SnapshotMetadata: TStreamMetadata;
    function SnapshotSpectrum: TRadioSpectrumData;
    function SnapshotState: TRadioPlayerState;
    function SnapshotStats: TRadioBufferStats;
    function TryReadPCMLevels(Buffer: PByte; ByteCount, Channels: Integer; SampleType: TAudioSampleType;
      out PeakLeft, PeakRight, RMSLeft, RMSRight: Single): Boolean;
    procedure DispatchEvent(const Message: TRadioPlayerEventMessage);
    procedure Log(const MessageText: string; Level: TRadioLogLevel = rllInfo);
    procedure NotifyError(const ErrorInfo: TRadioErrorInfo);
    procedure NotifyMetadataChanged;
    procedure NotifyReconnectAttempt(Attempt: Integer; DelayMS: Cardinal);
    procedure NotifyReconnectFailed(Attempt: Integer; const ErrorInfo: TRadioErrorInfo);
    procedure NotifyReconnectSucceeded(Attempt: Integer);
    procedure NotifySpectrum(const Spectrum: TRadioSpectrumData);
    procedure NotifyStateChanged;
    procedure NotifyStats;
    function NextReconnectDelay(CurrentDelay: Cardinal): Cardinal;
    procedure RecordBytesWritten(ByteCount: Integer);
    procedure SetMuted(const Value: Boolean);
    procedure SetBufferTimeMS(const Value: Integer);
    procedure SetEventDispatchMode(const Value: TRadioEventDispatchMode);
    procedure SetOutputSpectrumBinCount(const Value: Integer);
    procedure SetOutputSpectrumEnabled(const Value: Boolean);
    procedure SetOutputSpectrumFFTSize(const Value: Integer);
    procedure SetOutputSpectrumIntervalMS(const Value: Cardinal);
    procedure SetPrebufferTimeMS(const Value: Integer);
    procedure SetState(const Value: TRadioPlayerState);
    procedure SetVolume(const Value: Single);
    procedure SetWasapiDeviceId(const Value: string);
    procedure SetWasapiVolumeMode(const Value: TRadioWASAPIVolumeMode);
    procedure SignalOutputFailure(const MessageText: string);
    procedure ProcessOutputAudio(Buffer: PByte; ByteCount: Integer; Output: TAudioOutput);
    procedure HandleEventBusMessage(const Message: TRadioPlayerEventMessage);
    procedure WorkerExecute;
  public
    class function EnumerateWASAPIDevices: TRadioWASAPIDeviceInfos; static;
    class procedure PumpMainThreadEvents(TimeoutMS: Cardinal = 0); static;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure Play(const AURL: string);
    procedure Stop;

    property URL: string read FURL;
    property State: TRadioPlayerState read GetState;
    property Metadata: TStreamMetadata read GetMetadata;
    property LastSpectrum: TRadioSpectrumData read GetLastSpectrum;
    property Stats: TRadioBufferStats read GetStats;
    property ReconnectPolicy: TRadioReconnectPolicy read FReconnectPolicy write FReconnectPolicy;
    property OutputBackend: TRadioOutputBackend read FOutputBackend write FOutputBackend;
    property Volume: Single read FVolume write SetVolume;
    property Muted: Boolean read FMuted write SetMuted;
    property Logger: IRadioLogger read FLogger write FLogger;
  published
    property BufferTimeMS: Integer read FBufferTimeMS write SetBufferTimeMS;
    property EventDispatchMode: TRadioEventDispatchMode read FEventDispatchMode write SetEventDispatchMode;
    property OutputSpectrumEnabled: Boolean read FOutputSpectrumEnabled write SetOutputSpectrumEnabled;
    property OutputSpectrumFFTSize: Integer read FOutputSpectrumFFTSize write SetOutputSpectrumFFTSize;
    property OutputSpectrumBinCount: Integer read FOutputSpectrumBinCount write SetOutputSpectrumBinCount;
    property OutputSpectrumIntervalMS: Cardinal read FOutputSpectrumIntervalMS write SetOutputSpectrumIntervalMS;
    property PrebufferTimeMS: Integer read FPrebufferTimeMS write SetPrebufferTimeMS;
    property WasapiDeviceId: string read FWasapiDeviceId write SetWasapiDeviceId;
    property WasapiVolumeMode: TRadioWASAPIVolumeMode read FWasapiVolumeMode write SetWasapiVolumeMode;
    property OnStateChanged: TNotifyEvent read FOnStateChanged write FOnStateChanged;
    property OnStateChangedData: TStateChangedEvent read FOnStateChangedData write FOnStateChangedData;
    property OnMetadataChanged: TNotifyEvent read FOnMetadataChanged write FOnMetadataChanged;
    property OnMetadataChangedData: TMetadataChangedEvent read FOnMetadataChangedData write FOnMetadataChangedData;
    property OnError: TRadioErrorEvent read FOnError write FOnError;
    property OnBufferStats: TBufferStatsEvent read FOnBufferStats write FOnBufferStats;
    property OnSpectrum: TSpectrumEvent read FOnSpectrum write FOnSpectrum;
    property OnReconnectAttempt: TReconnectAttemptEvent read FOnReconnectAttempt write FOnReconnectAttempt;
    property OnReconnectSucceeded: TReconnectSucceededEvent read FOnReconnectSucceeded write FOnReconnectSucceeded;
    property OnReconnectFailed: TReconnectFailedEvent read FOnReconnectFailed write FOnReconnectFailed;
  end;

implementation

type
  TRadioOutputThread = class(TThread)
  private
    FBuffer: TRadioPCMBuffer;
    FOutput: TAudioOutput;
    FOwner: TRadioPlayer;
    FPrebufferBytes: Integer;
    FReadChunkBytes: Integer;
    FStopEvent: TEvent;
    FTempBuffer: TBytes;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TRadioPlayer; AOutput: TAudioOutput;
      ABuffer: TRadioPCMBuffer; AStopEvent: TEvent; APrebufferBytes: Integer;
      ABytesPerSecond: Integer);
  end;

  TRadioSession = class
  public
    StreamClient: TRadioStreamClient;
    Decoder: TAudioDecodeWorker;
    Resampler: TAudioResampler;
    Output: TAudioOutput;
    PCMBuffer: TRadioPCMBuffer;
    OutputThread: TRadioOutputThread;
    Packet: PAVPacket;
    Frame: PAVFrame;
    constructor Create(Backend: TRadioOutputBackend; const WasapiDeviceId: string;
      WasapiVolumeMode: TRadioWASAPIVolumeMode);
    destructor Destroy; override;
  end;

constructor TRadioOutputThread.Create(AOwner: TRadioPlayer; AOutput: TAudioOutput;
  ABuffer: TRadioPCMBuffer; AStopEvent: TEvent; APrebufferBytes: Integer;
  ABytesPerSecond: Integer);
var
  BytesPerFrame: Integer;
begin
  inherited Create(False);
  FreeOnTerminate := False;
  FOwner := AOwner;
  FOutput := AOutput;
  FBuffer := ABuffer;
  FStopEvent := AStopEvent;
  FPrebufferBytes := APrebufferBytes;
  BytesPerFrame := 4;
  if Assigned(FOutput) and (FOutput.BytesPerFrame > 0) then
    BytesPerFrame := FOutput.BytesPerFrame;

  if ABytesPerSecond > 0 then
    FReadChunkBytes := ABytesPerSecond div 100
  else
    FReadChunkBytes := 4096;

  if FReadChunkBytes < BytesPerFrame * 64 then
    FReadChunkBytes := BytesPerFrame * 64
  else if FReadChunkBytes > 16384 then
    FReadChunkBytes := 16384;

  FReadChunkBytes := (FReadChunkBytes div BytesPerFrame) * BytesPerFrame;
  if FReadChunkBytes <= 0 then
    FReadChunkBytes := BytesPerFrame;

  SetLength(FTempBuffer, FReadChunkBytes);
end;

procedure TRadioOutputThread.Execute;
var
  Buffered: Integer;
  UnderflowActive: Boolean;
  ReadBytes: Integer;
  Started: Boolean;
begin
  Started := False;
  UnderflowActive := False;
  try
    while not Terminated do
    begin
      if FStopEvent.WaitFor(0) = wrSignaled then
        Exit;

      if not Started then
      begin
        Buffered := FBuffer.BufferedBytes;
        if (FPrebufferBytes <= 0) or (Buffered >= FPrebufferBytes) or
           (FBuffer.IsClosed and (Buffered > 0)) then
        begin
          FOutput.Start;
          Started := True;
        end
        else if FBuffer.IsClosed and (Buffered = 0) then
          Exit
        else
        begin
          Sleep(5);
          Continue;
        end;
      end;

      ReadBytes := FBuffer.Read(@FTempBuffer[0], Length(FTempBuffer), 10, FStopEvent);
      if ReadBytes > 0 then
      begin
        UnderflowActive := False;
        FOutput.Write(@FTempBuffer[0], ReadBytes);
        FOwner.RecordBytesWritten(ReadBytes);
        FOwner.ProcessOutputAudio(@FTempBuffer[0], ReadBytes, FOutput);
      end
      else if not FBuffer.IsClosed then
      begin
        if Started and not UnderflowActive then
        begin
          UnderflowActive := True;
          FOwner.HandleBufferUnderflow;
        end;
      end
      else if FBuffer.IsClosed and (FBuffer.BufferedBytes = 0) then
        Exit;
    end;
  except
    on E: Exception do
      FOwner.SignalOutputFailure(E.Message);
  end;
end;

constructor TRadioSession.Create(Backend: TRadioOutputBackend;
  const WasapiDeviceId: string; WasapiVolumeMode: TRadioWASAPIVolumeMode);
{$IFDEF MSWINDOWS}
  {$IFDEF RADIO_HAS_WASAPI}
var
  WasapiOutput: TAudioOutputWASAPI;
  {$ENDIF}
{$ENDIF}
begin
  inherited Create;
  StreamClient := TRadioStreamClient.Create;
  Decoder := TAudioDecodeWorker.Create;
  Resampler := TAudioResampler.Create;
  case Backend of
{$IFDEF MSWINDOWS}
    {$IFDEF RADIO_HAS_WASAPI}
    robWASAPI:
      begin
        WasapiOutput := TAudioOutputWASAPI.Create;
        WasapiOutput.DeviceId := WasapiDeviceId;
        WasapiOutput.VolumeMode := WasapiVolumeMode;
        Output := WasapiOutput;
      end;
    {$ENDIF}
    robWaveOut:
      Output := TAudioOutputWaveOut.Create;
{$ENDIF}
{$IFDEF LINUX}
    robAPlay:
      Output := TAudioOutputAPlay.Create;
    robPulseAudio:
      Output := TAudioOutputPulseAudio.Create;
{$ENDIF}
  else
{$IFDEF MSWINDOWS}
    Output := TAudioOutputWaveOut.Create;
{$ELSE}
    Output := TAudioOutputAPlay.Create;
{$ENDIF}
  end;
  Packet := TFFmpegApi.AllocPacket;
  Frame := TFFmpegApi.AllocFrame;
end;

destructor TRadioSession.Destroy;
begin
  OutputThread.Free;
  PCMBuffer.Free;
  if Assigned(Frame) then
    TFFmpegApi.FreeFrame(Frame);
  if Assigned(Packet) then
    TFFmpegApi.FreePacket(Packet);
  Output.Free;
  Resampler.Free;
  Decoder.Free;
  StreamClient.Free;
  inherited Destroy;
end;

constructor TRadioPlayer.TRadioWorkerThread.Create(AOwner: TRadioPlayer);
begin
  inherited Create(False);
  FreeOnTerminate := False;
  FOwner := AOwner;
end;

procedure TRadioPlayer.TRadioWorkerThread.Execute;
begin
  FOwner.WorkerExecute;
end;

constructor TRadioPlayer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCriticalSection := TCriticalSection.Create;
  FStopEvent := TEvent.Create(nil, True, False, '');
  FEventDispatchMode := redmDedicatedThread;
  FEventBus := TRadioEventBus.Create(HandleEventBusMessage, FEventDispatchMode);
  FState := rpsIdle;
  FMetadata := DefaultStreamMetadata;
  FLastSpectrum := Default(TRadioSpectrumData);
  FStats := DefaultBufferStats;
  FReconnectPolicy := DefaultReconnectPolicy;
{$IFDEF LINUX}
  FOutputBackend := robPulseAudio;
{$ELSE}
  {$IFDEF RADIO_HAS_WASAPI}
  FOutputBackend := robWASAPI;
  {$ELSE}
  FOutputBackend := robWaveOut;
  {$ENDIF}
{$ENDIF}
  FBufferTimeMS := 2000;
  FOutputSpectrumEnabled := True;
  FOutputSpectrumFFTSize := 2048;
  FOutputSpectrumBinCount := 24;
  FOutputSpectrumIntervalMS := 50;
  FPrebufferTimeMS := 500;
  FVolume := 1.0;
  FWasapiVolumeMode := rwvmSession;
end;

destructor TRadioPlayer.Destroy;
begin
  Stop;
  FreeAndNil(FOutputSpectrumAnalyzer);
  FEventBus.Free;
  FStopEvent.Free;
  FCriticalSection.Free;
  inherited Destroy;
end;

function TRadioPlayer.GetMetadata: TStreamMetadata;
begin
  FCriticalSection.Acquire;
  try
    Result := FMetadata;
  finally
    FCriticalSection.Release;
  end;
end;

function TRadioPlayer.GetLastSpectrum: TRadioSpectrumData;
begin
  Result := SnapshotSpectrum;
end;

function TRadioPlayer.GetState: TRadioPlayerState;
begin
  FCriticalSection.Acquire;
  try
    Result := FState;
  finally
    FCriticalSection.Release;
  end;
end;

function TRadioPlayer.GetStats: TRadioBufferStats;
begin
  FCriticalSection.Acquire;
  try
    Result := FStats;
  finally
    FCriticalSection.Release;
  end;
end;

class function TRadioPlayer.EnumerateWASAPIDevices: TRadioWASAPIDeviceInfos;
begin
{$IFDEF MSWINDOWS}
  {$IFDEF RADIO_HAS_WASAPI}
  Result := TAudioOutputWASAPI.EnumerateDevices;
  {$ELSE}
  SetLength(Result, 0);
  {$ENDIF}
{$ELSE}
  SetLength(Result, 0);
{$ENDIF}
end;

procedure TRadioPlayer.HandleEventBusMessage(const Message: TRadioPlayerEventMessage);
begin
  DispatchEvent(Message);
end;

class procedure TRadioPlayer.PumpMainThreadEvents(TimeoutMS: Cardinal);
begin
  CheckSynchronize(TimeoutMS);
end;

procedure TRadioPlayer.DispatchEvent(const Message: TRadioPlayerEventMessage);
begin
  case Message.Kind of
    rpekStateChanged:
      begin
        if Assigned(FOnStateChangedData) then
          FOnStateChangedData(Self, Message.State);
        if Assigned(FOnStateChanged) then
          FOnStateChanged(Self);
      end;
    rpekMetadataChanged:
      begin
        if Assigned(FOnMetadataChangedData) then
          FOnMetadataChangedData(Self, Message.Metadata);
        if Assigned(FOnMetadataChanged) then
          FOnMetadataChanged(Self);
      end;
    rpekError:
      if Assigned(FOnError) then
        FOnError(Self, Message.ErrorInfo);
    rpekBufferStats:
      if Assigned(FOnBufferStats) then
        FOnBufferStats(Self, Message.Stats);
    rpekSpectrum:
      if Assigned(FOnSpectrum) then
        FOnSpectrum(Self, Message.Spectrum);
    rpekReconnectAttempt:
      if Assigned(FOnReconnectAttempt) then
        FOnReconnectAttempt(Self, Message.Attempt, Message.DelayMS);
    rpekReconnectSucceeded:
      if Assigned(FOnReconnectSucceeded) then
        FOnReconnectSucceeded(Self, Message.Attempt);
    rpekReconnectFailed:
      if Assigned(FOnReconnectFailed) then
        FOnReconnectFailed(Self, Message.Attempt, Message.ErrorInfo);
  end;
end;

procedure TRadioPlayer.ApplyStatsBufferSnapshot(PcmBuffer: TRadioPCMBuffer; Output: TAudioOutput;
  BytesPerSecond, BufferCapacityBytes, PrebufferBytes: Integer);
begin
  FCriticalSection.Acquire;
  try
    if Assigned(PcmBuffer) then
      FStats.QueueBufferedBytes := PcmBuffer.BufferedBytes
    else
      FStats.QueueBufferedBytes := 0;

    if Assigned(Output) then
      FStats.OutputBufferedBytes := Output.GetBufferedBytes
    else
      FStats.OutputBufferedBytes := 0;

    FStats.BufferCapacityBytes := BufferCapacityBytes;
    FStats.PrebufferBytes := PrebufferBytes;
    FStats.BufferedBytes := FStats.QueueBufferedBytes + FStats.OutputBufferedBytes;
    FStats.OutputLatencyMS := 0;
    if Assigned(Output) then
      FStats.OutputLatencyMS := Output.GetLatencyMS;
    FStats.QueueDurationMS := 0;
    if (BytesPerSecond > 0) and (FStats.QueueBufferedBytes > 0) then
      FStats.QueueDurationMS := (FStats.QueueBufferedBytes * 1000) div BytesPerSecond;
    FStats.LatencyMS := FStats.OutputLatencyMS + FStats.QueueDurationMS;
    FStats.BufferFillPercent := 0;
    if BufferCapacityBytes > 0 then
      FStats.BufferFillPercent := (FStats.QueueBufferedBytes * 100.0) / BufferCapacityBytes;
  finally
    FCriticalSection.Release;
  end;
end;

procedure TRadioPlayer.ApplyStatsLevels(PeakLeft, PeakRight, RMSLeft, RMSRight: Single);
begin
  FCriticalSection.Acquire;
  try
    FStats.PeakLeft := PeakLeft;
    FStats.PeakRight := PeakRight;
    FStats.RMSLeft := RMSLeft;
    FStats.RMSRight := RMSRight;
  finally
    FCriticalSection.Release;
  end;
end;

procedure TRadioPlayer.EnsureSpectrumAnalyzer;
begin
  if not Assigned(FOutputSpectrumAnalyzer) then
    FOutputSpectrumAnalyzer := TRadioSpectrumAnalyzer.Create(FOutputSpectrumFFTSize, FOutputSpectrumBinCount);
end;

procedure TRadioPlayer.ApplyStatsRates(ElapsedMS: Cardinal; IntervalPackets, IntervalFrames: Integer;
  IntervalInputBytes, IntervalOutputBytes: Int64; StartTick: Cardinal);
begin
  if ElapsedMS = 0 then
    ElapsedMS := 1;

  FCriticalSection.Acquire;
  try
    FStats.PacketRate := (Int64(IntervalPackets) * 1000) div ElapsedMS;
    FStats.DecodeRate := (Int64(IntervalFrames) * 1000) div ElapsedMS;
    FStats.InputBitrate := (IntervalInputBytes * 8 * 1000) div ElapsedMS;
    FStats.OutputBitrate := (IntervalOutputBytes * 8 * 1000) div ElapsedMS;
    FStats.AverageInputBitrate := 0;
    if StartTick > 0 then
      FStats.AverageInputBitrate := (FStats.BytesReceived * 8 * 1000) div StartTick;
    FStats.AverageOutputBitrate := 0;
    if StartTick > 0 then
      FStats.AverageOutputBitrate := (FStats.BytesWritten * 8 * 1000) div StartTick;
    FStats.UptimeMS := StartTick;
  finally
    FCriticalSection.Release;
  end;
end;

procedure TRadioPlayer.HandleBufferUnderflow;
begin
  FCriticalSection.Acquire;
  try
    Inc(FStats.UnderflowCount);
  finally
    FCriticalSection.Release;
  end;

  Log('PCM buffer underflow detected', rllWarning);
  if SnapshotState = rpsPlaying then
    SetState(rpsBuffering);
end;

function TRadioPlayer.IsStopRequested: Boolean;
begin
  Result := FStopEvent.WaitFor(0) = wrSignaled;
end;

procedure TRadioPlayer.Log(const MessageText: string; Level: TRadioLogLevel);
begin
  if Assigned(FLogger) then
    FLogger.Log(Level, MessageText);
end;

procedure TRadioPlayer.NotifyStats;
var
  Message: TRadioPlayerEventMessage;
begin
  Message.Kind := rpekBufferStats;
  Message.Stats := SnapshotStats;
  FEventBus.Post(Message);
end;

procedure TRadioPlayer.NotifyError(const ErrorInfo: TRadioErrorInfo);
var
  Message: TRadioPlayerEventMessage;
begin
  Message.Kind := rpekError;
  Message.ErrorInfo := ErrorInfo;
  FEventBus.Post(Message);
end;

procedure TRadioPlayer.NotifyMetadataChanged;
var
  Message: TRadioPlayerEventMessage;
begin
  Message.Kind := rpekMetadataChanged;
  Message.Metadata := SnapshotMetadata;
  FEventBus.Post(Message);
end;

procedure TRadioPlayer.NotifyReconnectAttempt(Attempt: Integer; DelayMS: Cardinal);
var
  Message: TRadioPlayerEventMessage;
begin
  Message.Kind := rpekReconnectAttempt;
  Message.Attempt := Attempt;
  Message.DelayMS := DelayMS;
  FEventBus.Post(Message);
end;

procedure TRadioPlayer.NotifyReconnectFailed(Attempt: Integer; const ErrorInfo: TRadioErrorInfo);
var
  Message: TRadioPlayerEventMessage;
begin
  Message.Kind := rpekReconnectFailed;
  Message.Attempt := Attempt;
  Message.ErrorInfo := ErrorInfo;
  FEventBus.Post(Message);
end;

procedure TRadioPlayer.NotifyReconnectSucceeded(Attempt: Integer);
var
  Message: TRadioPlayerEventMessage;
begin
  Message.Kind := rpekReconnectSucceeded;
  Message.Attempt := Attempt;
  FEventBus.Post(Message);
end;

procedure TRadioPlayer.NotifySpectrum(const Spectrum: TRadioSpectrumData);
var
  Message: TRadioPlayerEventMessage;
begin
  FCriticalSection.Acquire;
  try
    FLastSpectrum := Spectrum;
  finally
    FCriticalSection.Release;
  end;

  Message.Kind := rpekSpectrum;
  Message.Spectrum := Spectrum;
  FEventBus.Post(Message);
end;

procedure TRadioPlayer.NotifyStateChanged;
var
  Message: TRadioPlayerEventMessage;
begin
  Message.Kind := rpekStateChanged;
  Message.State := SnapshotState;
  FEventBus.Post(Message);
end;

function TRadioPlayer.NextReconnectDelay(CurrentDelay: Cardinal): Cardinal;
begin
  if CurrentDelay = 0 then
    Exit(FReconnectPolicy.InitialDelayMS);

  Result := CurrentDelay * 2;
  if Result > FReconnectPolicy.MaxDelayMS then
    Result := FReconnectPolicy.MaxDelayMS;
end;

procedure TRadioPlayer.Play(const AURL: string);
begin
  Stop;

  FCriticalSection.Acquire;
  try
    FURL := AURL;
    FMetadata := DefaultStreamMetadata;
    FLastSpectrum := Default(TRadioSpectrumData);
    FStats := DefaultBufferStats;
    FOutputFailureMessage := '';
  finally
    FCriticalSection.Release;
  end;

  FStopEvent.ResetEvent;
  FWorker := TRadioWorkerThread.Create(Self);
end;

procedure TRadioPlayer.RecordBytesWritten(ByteCount: Integer);
begin
  FCriticalSection.Acquire;
  try
    Inc(FStats.BytesWritten, ByteCount);
  finally
    FCriticalSection.Release;
  end;
end;

procedure TRadioPlayer.ProcessOutputAudio(Buffer: PByte; ByteCount: Integer; Output: TAudioOutput);
var
  Analyzer: TRadioSpectrumAnalyzer;
  HasSpectrum: Boolean;
  OutputLatencyMS: Integer;
  PeakLeft: Single;
  PeakRight: Single;
  QueueDurationMS: Integer;
  RMSLeft: Single;
  RMSRight: Single;
  Spectrum: TRadioSpectrumData;
begin
  if not Assigned(Output) or not Assigned(Buffer) or (ByteCount <= 0) then
    Exit;
  HasSpectrum := False;

  if TryReadPCMLevels(Buffer, ByteCount, Output.Channels, Output.SampleType,
    PeakLeft, PeakRight, RMSLeft, RMSRight) then
    ApplyStatsLevels(PeakLeft, PeakRight, RMSLeft, RMSRight);

  FCriticalSection.Acquire;
  try
    if FOutputSpectrumEnabled then
    begin
      EnsureSpectrumAnalyzer;
      Analyzer := FOutputSpectrumAnalyzer;
      QueueDurationMS := FStats.QueueDurationMS;
      OutputLatencyMS := Output.GetLatencyMS;
      HasSpectrum := Analyzer.Consume(Buffer, ByteCount, Output.Channels, Output.SampleRate,
        Output.SampleType, FOutputSpectrumIntervalMS, OutputLatencyMS, QueueDurationMS, Spectrum);
    end;
  finally
    FCriticalSection.Release;
  end;

  if HasSpectrum then
    NotifySpectrum(Spectrum);
end;

function TRadioPlayer.ReadOutputFailureMessage: string;
begin
  FCriticalSection.Acquire;
  try
    Result := FOutputFailureMessage;
  finally
    FCriticalSection.Release;
  end;
end;

procedure TRadioPlayer.SetMuted(const Value: Boolean);
var
  ActiveOutput: TAudioOutput;
begin
  FCriticalSection.Acquire;
  try
    FMuted := Value;
    ActiveOutput := FActiveOutput;
    if Assigned(ActiveOutput) then
      ActiveOutput.SetMuted(Value);
  finally
    FCriticalSection.Release;
  end;
end;

procedure TRadioPlayer.SetState(const Value: TRadioPlayerState);
var
  Changed: Boolean;
begin
  FCriticalSection.Acquire;
  try
    Changed := FState <> Value;
    FState := Value;
  finally
    FCriticalSection.Release;
  end;

  if Changed then
    NotifyStateChanged;
end;

procedure TRadioPlayer.SetBufferTimeMS(const Value: Integer);
var
  ClampedValue: Integer;
begin
  ClampedValue := Value;
  if ClampedValue < 100 then
    ClampedValue := 100
  else if ClampedValue > 30000 then
    ClampedValue := 30000;

  FCriticalSection.Acquire;
  try
    FBufferTimeMS := ClampedValue;
    if FPrebufferTimeMS > FBufferTimeMS then
      FPrebufferTimeMS := FBufferTimeMS;
  finally
    FCriticalSection.Release;
  end;
end;

procedure TRadioPlayer.SetEventDispatchMode(const Value: TRadioEventDispatchMode);
begin
  FCriticalSection.Acquire;
  try
    FEventDispatchMode := Value;
    if Assigned(FEventBus) then
      FEventBus.Mode := Value;
  finally
    FCriticalSection.Release;
  end;
end;

procedure TRadioPlayer.SetOutputSpectrumBinCount(const Value: Integer);
var
  ClampedValue: Integer;
begin
  ClampedValue := Value;
  if ClampedValue < 8 then
    ClampedValue := 8
  else if ClampedValue > 96 then
    ClampedValue := 96;

  FCriticalSection.Acquire;
  try
    if FOutputSpectrumBinCount <> ClampedValue then
    begin
      FOutputSpectrumBinCount := ClampedValue;
      FreeAndNil(FOutputSpectrumAnalyzer);
    end;
  finally
    FCriticalSection.Release;
  end;
end;

procedure TRadioPlayer.SetOutputSpectrumEnabled(const Value: Boolean);
begin
  FCriticalSection.Acquire;
  try
    FOutputSpectrumEnabled := Value;
    if not Value then
      FreeAndNil(FOutputSpectrumAnalyzer);
  finally
    FCriticalSection.Release;
  end;
end;

procedure TRadioPlayer.SetOutputSpectrumFFTSize(const Value: Integer);
var
  ClampedValue: Integer;
begin
  ClampedValue := Value;
  if ClampedValue < 256 then
    ClampedValue := 256;
  if (ClampedValue and (ClampedValue - 1)) <> 0 then
    raise EArgumentException.Create('OutputSpectrumFFTSize must be a power of two');

  FCriticalSection.Acquire;
  try
    if FOutputSpectrumFFTSize <> ClampedValue then
    begin
      FOutputSpectrumFFTSize := ClampedValue;
      FreeAndNil(FOutputSpectrumAnalyzer);
    end;
  finally
    FCriticalSection.Release;
  end;
end;

procedure TRadioPlayer.SetOutputSpectrumIntervalMS(const Value: Cardinal);
begin
  FCriticalSection.Acquire;
  try
    FOutputSpectrumIntervalMS := Value;
  finally
    FCriticalSection.Release;
  end;
end;

procedure TRadioPlayer.SetPrebufferTimeMS(const Value: Integer);
var
  ClampedValue: Integer;
begin
  ClampedValue := Value;
  if ClampedValue < 0 then
    ClampedValue := 0;

  FCriticalSection.Acquire;
  try
    if ClampedValue > FBufferTimeMS then
      ClampedValue := FBufferTimeMS;
    FPrebufferTimeMS := ClampedValue;
  finally
    FCriticalSection.Release;
  end;
end;

procedure TRadioPlayer.SetVolume(const Value: Single);
var
  ActiveOutput: TAudioOutput;
  ClampedValue: Single;
begin
  if Value < 0 then
    ClampedValue := 0
  else if Value > 1 then
    ClampedValue := 1
  else
    ClampedValue := Value;

  FCriticalSection.Acquire;
  try
    FVolume := ClampedValue;
    ActiveOutput := FActiveOutput;
    if Assigned(ActiveOutput) then
      ActiveOutput.SetVolume(ClampedValue);
  finally
    FCriticalSection.Release;
  end;
end;

procedure TRadioPlayer.SetWasapiDeviceId(const Value: string);
begin
  FCriticalSection.Acquire;
  try
    FWasapiDeviceId := Value;
  finally
    FCriticalSection.Release;
  end;
end;

procedure TRadioPlayer.SignalOutputFailure(const MessageText: string);
begin
  FCriticalSection.Acquire;
  try
    if FOutputFailureMessage = '' then
      FOutputFailureMessage := MessageText;
  finally
    FCriticalSection.Release;
  end;

  FStopEvent.SetEvent;
end;

procedure TRadioPlayer.SetWasapiVolumeMode(const Value: TRadioWASAPIVolumeMode);
var
  ActiveOutput: TAudioOutput;
begin
  FCriticalSection.Acquire;
  try
    FWasapiVolumeMode := Value;
    ActiveOutput := FActiveOutput;
{$IFDEF MSWINDOWS}
  {$IFDEF RADIO_HAS_WASAPI}
    if Assigned(ActiveOutput) and (ActiveOutput is TAudioOutputWASAPI) then
      TAudioOutputWASAPI(ActiveOutput).VolumeMode := Value;
  {$ENDIF}
{$ENDIF}
  finally
    FCriticalSection.Release;
  end;
end;

procedure TRadioPlayer.Stop;
begin
  if not Assigned(FWorker) then
    Exit;

  SetState(rpsStopping);
  FStopEvent.SetEvent;
  FWorker.WaitFor;
  FreeAndNil(FWorker);
end;

function TRadioPlayer.SnapshotMetadata: TStreamMetadata;
begin
  FCriticalSection.Acquire;
  try
    Result := FMetadata;
  finally
    FCriticalSection.Release;
  end;
end;

function TRadioPlayer.SnapshotSpectrum: TRadioSpectrumData;
begin
  FCriticalSection.Acquire;
  try
    Result := FLastSpectrum;
  finally
    FCriticalSection.Release;
  end;
end;

function TRadioPlayer.SnapshotState: TRadioPlayerState;
begin
  FCriticalSection.Acquire;
  try
    Result := FState;
  finally
    FCriticalSection.Release;
  end;
end;

function TRadioPlayer.SnapshotStats: TRadioBufferStats;
begin
  FCriticalSection.Acquire;
  try
    Result := FStats;
  finally
    FCriticalSection.Release;
  end;
end;

function TRadioPlayer.TryReadPCMLevels(Buffer: PByte; ByteCount, Channels: Integer;
  SampleType: TAudioSampleType; out PeakLeft, PeakRight, RMSLeft, RMSRight: Single): Boolean;
var
  FrameCount: Integer;
  I: Integer;
  LeftValue: Single;
  RightValue: Single;
  Sample16: PSmallInt;
  Sample32: PSingle;
  SumSqLeft: Double;
  SumSqRight: Double;
begin
  PeakLeft := 0;
  PeakRight := 0;
  RMSLeft := 0;
  RMSRight := 0;
  Result := False;

  if (Channels < 1) or not Assigned(Buffer) or (ByteCount <= 0) then
    Exit;

  SumSqLeft := 0;
  SumSqRight := 0;
  case SampleType of
    astFloat32:
      begin
        FrameCount := ByteCount div (Channels * SizeOf(Single));
        if FrameCount <= 0 then
          Exit;
        Sample32 := PSingle(Buffer);
        for I := 0 to FrameCount - 1 do
        begin
          LeftValue := EnsureRange(Sample32^, -1.0, 1.0);
          Inc(Sample32);
          if Channels > 1 then
          begin
            RightValue := EnsureRange(Sample32^, -1.0, 1.0);
            Inc(Sample32);
          end
          else
            RightValue := LeftValue;

          if Abs(LeftValue) > PeakLeft then
            PeakLeft := Abs(LeftValue);
          if Abs(RightValue) > PeakRight then
            PeakRight := Abs(RightValue);
          SumSqLeft := SumSqLeft + Sqr(LeftValue);
          SumSqRight := SumSqRight + Sqr(RightValue);

          Inc(Sample32, Channels - Min(Channels, 2));
        end;
      end;
  else
    begin
      FrameCount := ByteCount div (Channels * SizeOf(SmallInt));
      if FrameCount <= 0 then
        Exit;
      Sample16 := PSmallInt(Buffer);
      for I := 0 to FrameCount - 1 do
      begin
        LeftValue := Sample16^ / 32768.0;
        Inc(Sample16);
        if Channels > 1 then
        begin
          RightValue := Sample16^ / 32768.0;
          Inc(Sample16);
        end
        else
          RightValue := LeftValue;

        if Abs(LeftValue) > PeakLeft then
          PeakLeft := Abs(LeftValue);
        if Abs(RightValue) > PeakRight then
          PeakRight := Abs(RightValue);
        SumSqLeft := SumSqLeft + Sqr(LeftValue);
        SumSqRight := SumSqRight + Sqr(RightValue);

        Inc(Sample16, Channels - Min(Channels, 2));
      end;
    end;
  end;

  RMSLeft := Sqrt(SumSqLeft / FrameCount);
  RMSRight := Sqrt(SumSqRight / FrameCount);
  Result := True;
end;

procedure TRadioPlayer.WorkerExecute;
const
  OUTPUT_SAMPLE_RATE = 44100;
  OUTPUT_CHANNELS = 2;
var
  BufferCapacityBytes: Integer;
  BytesPerSecond: Integer;
  ElapsedMS: Cardinal;
  ErrorInfo: TRadioErrorInfo;
  DelayMS: Cardinal;
  Attempt: Integer;
  DisconnectResult: Integer;
  EnqueuedBytes: Integer;
  InputByteCount: Integer;
  IntervalFrames: Integer;
  IntervalInputBytes: Int64;
  IntervalOutputBytes: Int64;
  IntervalPackets: Integer;
  LastStatsTick: Cardinal;
  PcmBufferTimeMS: Integer;
  PrebufferBytes: Integer;
  PcmPrebufferTimeMS: Integer;
  Session: TRadioSession;
  SessionStartTick: Cardinal;
  ReadResult: Integer;
  ReceiveResult: Integer;
  ReconnectAttemptCount: Integer;
  SendResult: Integer;
  Buffer: PByte;
  ByteCount: Integer;
  MetadataChanged: Boolean;
  NewMetadata: TStreamMetadata;
  CurrentBackend: TRadioOutputBackend;
  CurrentWasapiDeviceId: string;
  CurrentWasapiVolumeMode: TRadioWASAPIVolumeMode;
  CurrentURL: string;
{$IFDEF MSWINDOWS}
  CoInitResult: HResult;
{$ENDIF}
begin
{$IFDEF MSWINDOWS}
  CoInitResult := CoInitializeEx(nil, COINIT_MULTITHREADED);
{$ENDIF}
  Session := nil;
  try
    try
      DelayMS := 0;
      Attempt := 0;
      ReconnectAttemptCount := 0;
      LastStatsTick := GetTickCountMS;
      SessionStartTick := LastStatsTick;

      FCriticalSection.Acquire;
      try
        CurrentURL := FURL;
        CurrentBackend := FOutputBackend;
        PcmBufferTimeMS := FBufferTimeMS;
        PcmPrebufferTimeMS := FPrebufferTimeMS;
        CurrentWasapiDeviceId := FWasapiDeviceId;
        CurrentWasapiVolumeMode := FWasapiVolumeMode;
      finally
        FCriticalSection.Release;
      end;

      Session := TRadioSession.Create(CurrentBackend, CurrentWasapiDeviceId, CurrentWasapiVolumeMode);

      while not IsStopRequested do
      begin
        SetState(rpsOpening);
        Log('Opening stream: ' + CurrentURL);

        ReadResult := Session.StreamClient.Open(CurrentURL, FReconnectPolicy);
        if ReadResult < 0 then
        begin
          ErrorInfo.Code := 1;
          ErrorInfo.MessageText := 'Could not open stream';
          ErrorInfo.FFmpegError := ReadResult;
          ErrorInfo.FFmpegErrorText := FFmpegErrorText(ReadResult);
          ErrorInfo.Recoverable := FReconnectPolicy.Enabled and not IsStopRequested;

          FCriticalSection.Acquire;
          try
            FStats.LastError := ErrorInfo.MessageText;
            FStats.LastFFmpegError := ReadResult;
          finally
            FCriticalSection.Release;
          end;
          NotifyError(ErrorInfo);

          if not ErrorInfo.Recoverable then
          begin
            if Attempt > 0 then
            begin
              FCriticalSection.Acquire;
              try
                Inc(FStats.ReconnectFailureCount);
              finally
                FCriticalSection.Release;
              end;
              NotifyReconnectFailed(Attempt, ErrorInfo);
            end;
            Log('Could not open stream: ' + ErrorInfo.FFmpegErrorText, rllError);
            SetState(rpsError);
            Exit;
          end;

          Inc(Attempt);
          ReconnectAttemptCount := Attempt;
          DelayMS := NextReconnectDelay(DelayMS);
          Log(Format('Open failed, reconnect attempt %d in %d ms (%s)',
            [Attempt, DelayMS, ErrorInfo.FFmpegErrorText]), rllWarning);
          SetState(rpsReconnecting);
          NotifyReconnectAttempt(Attempt, DelayMS);
          FStopEvent.WaitFor(DelayMS);
          Continue;
        end;

        DelayMS := 0;
        Attempt := 0;
        IntervalPackets := 0;
        IntervalFrames := 0;
        IntervalInputBytes := 0;
        IntervalOutputBytes := 0;

        ReadResult := Session.Decoder.Open(Session.StreamClient.Codec, Session.StreamClient.CodecParameters);
        if ReadResult < 0 then
        begin
          ErrorInfo.Code := 2;
          ErrorInfo.MessageText := 'Could not open decoder';
          ErrorInfo.FFmpegError := ReadResult;
          ErrorInfo.FFmpegErrorText := FFmpegErrorText(ReadResult);
          ErrorInfo.Recoverable := False;
          NotifyError(ErrorInfo);
          Log('Could not open decoder: ' + ErrorInfo.FFmpegErrorText, rllError);
          SetState(rpsError);
          Exit;
        end;

        Session.Output.Open(OUTPUT_SAMPLE_RATE, OUTPUT_CHANNELS, 16);
        Session.Output.SetVolume(FVolume);
        Session.Output.SetMuted(FMuted);

        FCriticalSection.Acquire;
        try
          FActiveOutput := Session.Output;
        finally
          FCriticalSection.Release;
        end;

        case Session.Output.SampleType of
          astFloat32:
            ReadResult := Session.Resampler.OpenFromCodec(Session.Decoder.CodecContext,
              Session.Output.SampleRate, Session.Output.Channels, AV_SAMPLE_FMT_FLT);
        else
          ReadResult := Session.Resampler.OpenFromCodec(Session.Decoder.CodecContext,
            Session.Output.SampleRate, Session.Output.Channels, AV_SAMPLE_FMT_S16);
        end;
        if ReadResult < 0 then
        begin
          ErrorInfo.Code := 3;
          ErrorInfo.MessageText := 'Could not initialize resampler';
          ErrorInfo.FFmpegError := ReadResult;
          ErrorInfo.FFmpegErrorText := FFmpegErrorText(ReadResult);
          ErrorInfo.Recoverable := False;
          NotifyError(ErrorInfo);
          Log('Could not initialize resampler: ' + ErrorInfo.FFmpegErrorText, rllError);
          SetState(rpsError);
          Exit;
        end;

        BytesPerSecond := Session.Resampler.BytesPerSecond;
        BufferCapacityBytes := (BytesPerSecond * PcmBufferTimeMS) div 1000;
        if BufferCapacityBytes < 16384 then
          BufferCapacityBytes := 16384;
        PrebufferBytes := (BytesPerSecond * PcmPrebufferTimeMS) div 1000;
        if PrebufferBytes > BufferCapacityBytes then
          PrebufferBytes := BufferCapacityBytes;

        Session.PCMBuffer := TRadioPCMBuffer.Create(BufferCapacityBytes);
        Session.OutputThread := TRadioOutputThread.Create(Self, Session.Output,
          Session.PCMBuffer, FStopEvent, PrebufferBytes, BytesPerSecond);

        NewMetadata := Session.StreamClient.Metadata;
        NewMetadata.CodecName := UTF8PtrToString(avcodec_get_name(Session.Decoder.CodecContext^.codec_id));
        NewMetadata.SampleRate := Session.Output.SampleRate;
        NewMetadata.Channels := Session.Output.Channels;
        FCriticalSection.Acquire;
        try
          FMetadata := NewMetadata;
        finally
          FCriticalSection.Release;
        end;
        Log(Format('Stream ready: codec=%s out=%d Hz/%d ch sampleType=%d',
          [NewMetadata.CodecName, Session.Output.SampleRate, Session.Output.Channels,
           Ord(Session.Output.SampleType)]), rllInfo);
        if ReconnectAttemptCount > 0 then
        begin
          FCriticalSection.Acquire;
          try
            Inc(FStats.ReconnectSuccessCount);
          finally
            FCriticalSection.Release;
          end;
          NotifyReconnectSucceeded(ReconnectAttemptCount);
          Log(Format('Reconnect attempt %d succeeded', [ReconnectAttemptCount]), rllInfo);
          ReconnectAttemptCount := 0;
        end;
        NotifyMetadataChanged;

        SetState(rpsBuffering);
        DisconnectResult := 0;

        while not IsStopRequested do
        begin
          ReadResult := Session.StreamClient.ReadPacket(Session.Packet);
          if ReadResult < 0 then
          begin
            DisconnectResult := ReadResult;
            Log('Stream read failed: ' + FFmpegErrorText(DisconnectResult), rllWarning);
            Break;
          end;

          InputByteCount := Session.Packet^.size;

          FCriticalSection.Acquire;
          try
            Inc(FStats.PacketsReceived);
            Inc(FStats.BytesReceived, InputByteCount);
          finally
            FCriticalSection.Release;
          end;
          Inc(IntervalPackets);
          Inc(IntervalInputBytes, InputByteCount);

          Session.StreamClient.RefreshMetadata(MetadataChanged);
          if MetadataChanged then
          begin
            NewMetadata := Session.StreamClient.Metadata;
            NewMetadata.CodecName := UTF8PtrToString(avcodec_get_name(Session.Decoder.CodecContext^.codec_id));
            FCriticalSection.Acquire;
            try
              FMetadata := NewMetadata;
            finally
              FCriticalSection.Release;
            end;
            Log('Metadata updated: ' + NewMetadata.StreamTitle, rllInfo);
            NotifyMetadataChanged;
          end;

          if Session.Packet^.stream_index = Session.StreamClient.AudioStreamIndex then
          begin
            SendResult := Session.Decoder.SendPacket(Session.Packet);
            if SendResult >= 0 then
            begin
              while not IsStopRequested do
              begin
                ReceiveResult := Session.Decoder.ReceiveFrame(Session.Frame);
                if (ReceiveResult = AVERROR_EAGAIN) or (ReceiveResult = AVERROR_EOF) then
                  Break;
                if ReceiveResult < 0 then
                begin
                  FCriticalSection.Acquire;
                  try
                    Inc(FStats.PacketsDropped);
                    FStats.LastFFmpegError := ReceiveResult;
                    FStats.LastError := FFmpegErrorText(ReceiveResult);
                  finally
                    FCriticalSection.Release;
                  end;
                  Break;
                end;

                FCriticalSection.Acquire;
                try
                  Inc(FStats.DecodedFrames);
                finally
                  FCriticalSection.Release;
                end;
                Inc(IntervalFrames);

                ReadResult := Session.Resampler.ConvertFrame(Session.Frame, Buffer, ByteCount);
                if (ReadResult >= 0) and (ByteCount > 0) then
                begin
                  EnqueuedBytes := Session.PCMBuffer.Write(Buffer, ByteCount, FStopEvent);
                  Inc(IntervalOutputBytes, ByteCount);
                  if (EnqueuedBytes <= 0) and IsStopRequested then
                    Break;
                  if (SnapshotState <> rpsPlaying) and
                     ((PrebufferBytes <= 0) or (Session.PCMBuffer.BufferedBytes >= PrebufferBytes)) then
                  begin
                    SetState(rpsPlaying);
                  end;
                  ApplyStatsBufferSnapshot(Session.PCMBuffer, Session.Output, BytesPerSecond,
                    BufferCapacityBytes, PrebufferBytes);
                end;
                TFFmpegApi.UnrefFrame(Session.Frame);
              end;
            end;
          end;

          TFFmpegApi.UnrefPacket(Session.Packet);

          if ReadOutputFailureMessage <> '' then
          begin
            DisconnectResult := AVERROR_EXTERNAL;
            Break;
          end;

          if GetTickCountMS - LastStatsTick >= 1000 then
          begin
            ElapsedMS := GetTickCountMS - LastStatsTick;
            LastStatsTick := GetTickCountMS;
            ApplyStatsBufferSnapshot(Session.PCMBuffer, Session.Output, BytesPerSecond,
              BufferCapacityBytes, PrebufferBytes);
            ApplyStatsRates(ElapsedMS, IntervalPackets, IntervalFrames, IntervalInputBytes,
              IntervalOutputBytes, LastStatsTick - SessionStartTick);
            NotifyStats;
            IntervalPackets := 0;
            IntervalFrames := 0;
            IntervalInputBytes := 0;
            IntervalOutputBytes := 0;
          end;
        end;

        TFFmpegApi.UnrefPacket(Session.Packet);
        ReadResult := Session.Resampler.Flush(Buffer, ByteCount);
        if (ReadResult >= 0) and (ByteCount > 0) and not IsStopRequested then
          Session.PCMBuffer.Write(Buffer, ByteCount, FStopEvent);

        if Assigned(Session.PCMBuffer) then
          Session.PCMBuffer.CloseInput;
        if Assigned(Session.OutputThread) then
        begin
          Session.OutputThread.WaitFor;
          FreeAndNil(Session.OutputThread);
        end;

        Session.Output.Stop;
        Session.Output.Close;
        Session.Resampler.Close;
        Session.Decoder.Close;
        Session.StreamClient.Close;
        FCriticalSection.Acquire;
        try
          FActiveOutput := nil;
        finally
          FCriticalSection.Release;
        end;

        if ReadOutputFailureMessage <> '' then
        begin
          ErrorInfo.Code := 5;
          ErrorInfo.MessageText := 'Audio output failed: ' + ReadOutputFailureMessage;
          ErrorInfo.FFmpegError := 0;
          ErrorInfo.FFmpegErrorText := '';
          ErrorInfo.Recoverable := False;
          NotifyError(ErrorInfo);
          Log(ErrorInfo.MessageText, rllError);
          SetState(rpsError);
          Exit;
        end;

        if IsStopRequested then
          Break;

        ErrorInfo.Code := 4;
        ErrorInfo.MessageText := 'Stream disconnected';
        ErrorInfo.FFmpegError := DisconnectResult;
        ErrorInfo.FFmpegErrorText := FFmpegErrorText(DisconnectResult);
        ErrorInfo.Recoverable := FReconnectPolicy.Enabled;

        FCriticalSection.Acquire;
        try
          Inc(FStats.ReconnectCount);
          FStats.LastError := ErrorInfo.MessageText;
          FStats.LastFFmpegError := DisconnectResult;
        finally
          FCriticalSection.Release;
        end;

        if not ErrorInfo.Recoverable then
        begin
          Inc(ReconnectAttemptCount);
          FCriticalSection.Acquire;
          try
            Inc(FStats.ReconnectFailureCount);
          finally
            FCriticalSection.Release;
          end;
          NotifyError(ErrorInfo);
          NotifyReconnectFailed(ReconnectAttemptCount, ErrorInfo);
          Log('Reconnect failed: ' + ErrorInfo.FFmpegErrorText, rllError);
          SetState(rpsError);
          Exit;
        end;

        Inc(Attempt);
        ReconnectAttemptCount := Attempt;
        DelayMS := NextReconnectDelay(DelayMS);
        Log(Format('Stream disconnected, reconnect attempt %d in %d ms (%s)',
          [Attempt, DelayMS, ErrorInfo.FFmpegErrorText]), rllWarning);
        SetState(rpsReconnecting);
        NotifyReconnectAttempt(Attempt, DelayMS);
        NotifyError(ErrorInfo);
        FStopEvent.WaitFor(DelayMS);
      end;

      Log('Playback loop stopped', rllInfo);
      SetState(rpsStopped);
    except
      on E: Exception do
      begin
        FCriticalSection.Acquire;
        try
          FActiveOutput := nil;
        finally
          FCriticalSection.Release;
        end;
        ErrorInfo.Code := 100;
        ErrorInfo.MessageText := E.Message;
        ErrorInfo.FFmpegError := 0;
        ErrorInfo.FFmpegErrorText := '';
        ErrorInfo.Recoverable := False;
        NotifyError(ErrorInfo);
        SetState(rpsError);
      end;
    end;
  finally
    Session.Free;
{$IFDEF MSWINDOWS}
    if (CoInitResult = S_OK) or (CoInitResult = S_FALSE) then
      CoUninitialize;
{$ENDIF}
  end;
end;

end.
