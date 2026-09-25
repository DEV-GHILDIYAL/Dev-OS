using System.Buffers.Binary;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Text.Json;
using Microsoft.Win32.SafeHandles;

namespace DevOS.HyperV;

public static class PipeProtocol
{
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GetNamedPipeClientProcessId(SafePipeHandle pipe, out uint pid);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GetNamedPipeServerProcessId(SafePipeHandle pipe, out uint pid);
    public static async Task<byte[]> ReadAsync(PipeStream pipe, int limit, CancellationToken token)
    {
        try
        {
            var length = new byte[4];
            await pipe.ReadExactlyAsync(length, token);
            var count = BinaryPrimitives.ReadInt32LittleEndian(length);
            if (count <= 0 || count > limit) throw new InvalidDataException("Message too large.");
            var bytes = new byte[count];
            await pipe.ReadExactlyAsync(bytes, token);
            return bytes;
        }
        catch (EndOfStreamException ex)
        {
            throw new IOException("Pipe closed before a complete message was received.", ex);
        }
    }

    public static async Task WriteAsync<T>(PipeStream pipe, T value, CancellationToken token)
    {
        var type = value?.GetType() ?? typeof(T);
        var bytes = JsonSerializer.SerializeToUtf8Bytes(value, type, Protocol.Json);
        var length = new byte[4];
        BinaryPrimitives.WriteInt32LittleEndian(length, bytes.Length);
        await pipe.WriteAsync(length, token);
        await pipe.WriteAsync(bytes, token);
        await pipe.FlushAsync(token);
    }
}
