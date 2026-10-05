using System.Buffers.Binary;
using System.Net;
using System.Net.Sockets;
using NAudio.CoreAudioApi;
using NAudio.Wave;

internal sealed class AudioBridgeRuntime : IDisposable
{
    private const byte ProtocolVersion = 1;
    private const byte PlaybackStream = 1;
    private const byte CaptureStream = 2;
    private static readonly byte[] Magic = { (byte)'W', (byte)'S', (byte)'A', (byte)'B' };

    private readonly int _port;
    private readonly object _gate = new();
    private readonly MMDeviceEnumerator _enumerator = new();

    private string? _renderEndpointId;
    private string? _captureEndpointId;
    private BufferedWaveProvider? _playbackBuffer;
    private WasapiOut? _playback;
    private WasapiCapture? _capture;

    private TcpClient? _audioClient;
    private NetworkStream? _audioStream;
    private readonly SemaphoreSlim _audioWriteGate = new(1, 1);
    private uint _captureSequence;

    public AudioBridgeRuntime(int port) => _port = port;

    public object GetRoutes()
    {
        var render = _enumerator
            .EnumerateAudioEndPoints(DataFlow.Render, DeviceState.Active)
            .Select(x => new { id = x.ID, name = x.FriendlyName, flow = "render", state = x.State.ToString() })
            .ToArray();

        var capture = _enumerator
            .EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Active)
            .Select(x => new { id = x.ID, name = x.FriendlyName, flow = "capture", state = x.State.ToString() })
            .ToArray();

        return new { type = "audio.routes.result", render, capture };
    }

    public object SelectRoute(string? renderEndpointId, string? captureEndpointId)
    {
        lock (_gate)
        {
            if (!string.IsNullOrWhiteSpace(renderEndpointId))
                _renderEndpointId = renderEndpointId;
            if (!string.IsNullOrWhiteSpace(captureEndpointId))
                _captureEndpointId = captureEndpointId;
        }

        return new
        {
            type = "audio.route.selected",
            renderEndpointId = _renderEndpointId,
            captureEndpointId = _captureEndpointId
        };
    }

    public object StartPlayback(int sampleRate, int channels)
    {
        lock (_gate)
        {
            StopPlaybackLocked();

            if (string.IsNullOrWhiteSpace(_renderEndpointId))
                return new { type = "audio.playback.state", state = "failed", error = "render_endpoint_not_selected" };

            var endpoint = _enumerator.GetDevice(_renderEndpointId);
            var format = new WaveFormat(sampleRate, 16, channels);
            _playbackBuffer = new BufferedWaveProvider(format)
            {
                BufferDuration = TimeSpan.FromMilliseconds(750),
                DiscardOnBufferOverflow = true,
                ReadFully = true
            };

            _playback = new WasapiOut(endpoint, AudioClientShareMode.Shared, true, 80);
            _playback.Init(_playbackBuffer);
            _playback.Play();

            return new
            {
                type = "audio.playback.state",
                state = "started",
                endpointName = endpoint.FriendlyName,
                sampleRate,
                channels,
                sampleFormat = "s16le"
            };
        }
    }

    public object StopPlayback()
    {
        lock (_gate)
        {
            StopPlaybackLocked();
            return new { type = "audio.playback.state", state = "stopped" };
        }
    }

    public object StartCapture()
    {
        lock (_gate)
        {
            StopCaptureLocked();

            if (string.IsNullOrWhiteSpace(_captureEndpointId))
                return new { type = "audio.capture.state", state = "failed", error = "capture_endpoint_not_selected" };

            var endpoint = _enumerator.GetDevice(_captureEndpointId);
            _capture = new WasapiCapture(endpoint);
            _captureSequence = 0;

            _capture.DataAvailable += (_, e) =>
            {
                var copy = new byte[e.BytesRecorded];
                Buffer.BlockCopy(e.Buffer, 0, copy, 0, e.BytesRecorded);
                _ = SendFrameAsync(CaptureStream, copy, _captureSequence++);
            };

            _capture.RecordingStopped += (_, e) =>
            {
                if (e.Exception is not null)
                    Console.Error.WriteLine($"Audio capture stopped: {e.Exception}");
            };

            _capture.StartRecording();

            return new
            {
                type = "audio.capture.state",
                state = "started",
                endpointName = endpoint.FriendlyName,
                sampleRate = _capture.WaveFormat.SampleRate,
                channels = _capture.WaveFormat.Channels,
                bitsPerSample = _capture.WaveFormat.BitsPerSample,
                encoding = _capture.WaveFormat.Encoding.ToString()
            };
        }
    }

    public object StopCapture()
    {
        lock (_gate)
        {
            StopCaptureLocked();
            return new { type = "audio.capture.state", state = "stopped" };
        }
    }

    public async Task RunServerAsync(CancellationToken cancellationToken = default)
    {
        var listener = new TcpListener(IPAddress.Loopback, _port);
        listener.Start();
        Console.WriteLine($"WSA audio bridge listening on 127.0.0.1:{_port}");

        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                var client = await listener.AcceptTcpClientAsync(cancellationToken);
                _ = Task.Run(() => RunAudioSessionAsync(client, cancellationToken), cancellationToken);
            }
        }
        finally
        {
            listener.Stop();
        }
    }

    private async Task RunAudioSessionAsync(TcpClient client, CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            _audioClient?.Dispose();
            _audioClient = client;
            _audioStream = client.GetStream();
        }

        Console.WriteLine("WSA audio stream connected.");

        try
        {
            var stream = client.GetStream();
            var header = new byte[16];

            while (!cancellationToken.IsCancellationRequested)
            {
                if (!await ReadExactlyAsync(stream, header, cancellationToken))
                    break;

                if (!header.AsSpan(0, 4).SequenceEqual(Magic) || header[4] != ProtocolVersion)
                    throw new InvalidDataException("Invalid WSAB audio frame header.");

                var streamId = header[5];
                var length = BinaryPrimitives.ReadUInt32LittleEndian(header.AsSpan(8, 4));
                if (length > 1024 * 1024)
                    throw new InvalidDataException("Audio frame is too large.");

                var payload = new byte[(int)length];
                if (!await ReadExactlyAsync(stream, payload, cancellationToken))
                    break;

                if (streamId == PlaybackStream)
                {
                    lock (_gate)
                    {
                        _playbackBuffer?.AddSamples(payload, 0, payload.Length);
                    }
                }
            }
        }
        catch (Exception ex) when (ex is IOException or SocketException or InvalidDataException)
        {
            Console.Error.WriteLine($"Audio session ended: {ex.Message}");
        }
        finally
        {
            lock (_gate)
            {
                if (ReferenceEquals(_audioClient, client))
                {
                    _audioStream = null;
                    _audioClient = null;
                }
            }

            client.Dispose();
        }
    }

    private async Task SendFrameAsync(byte streamId, byte[] payload, uint sequence)
    {
        NetworkStream? stream;
        lock (_gate)
            stream = _audioStream;

        if (stream is null || !stream.CanWrite)
            return;

        var header = new byte[16];
        Magic.CopyTo(header, 0);
        header[4] = ProtocolVersion;
        header[5] = streamId;
        BinaryPrimitives.WriteUInt16LittleEndian(header.AsSpan(6, 2), 0);
        BinaryPrimitives.WriteUInt32LittleEndian(header.AsSpan(8, 4), (uint)payload.Length);
        BinaryPrimitives.WriteUInt32LittleEndian(header.AsSpan(12, 4), sequence);

        await _audioWriteGate.WaitAsync();
        try
        {
            await stream.WriteAsync(header);
            await stream.WriteAsync(payload);
            await stream.FlushAsync();
        }
        catch
        {
            // Connection loss is reported by the audio session loop.
        }
        finally
        {
            _audioWriteGate.Release();
        }
    }

    private static async Task<bool> ReadExactlyAsync(Stream stream, byte[] buffer, CancellationToken cancellationToken)
    {
        var offset = 0;
        while (offset < buffer.Length)
        {
            var read = await stream.ReadAsync(buffer.AsMemory(offset), cancellationToken);
            if (read == 0)
                return false;
            offset += read;
        }
        return true;
    }

    private void StopPlaybackLocked()
    {
        try { _playback?.Stop(); } catch { }
        _playback?.Dispose();
        _playback = null;
        _playbackBuffer = null;
    }

    private void StopCaptureLocked()
    {
        try { _capture?.StopRecording(); } catch { }
        _capture?.Dispose();
        _capture = null;
    }

    public void Dispose()
    {
        lock (_gate)
        {
            StopPlaybackLocked();
            StopCaptureLocked();
            _audioClient?.Dispose();
            _audioStream = null;
            _audioClient = null;
        }

        _audioWriteGate.Dispose();
        _enumerator.Dispose();
    }
}
