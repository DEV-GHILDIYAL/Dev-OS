using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Text.Json;
using DevOS.HyperV;

namespace DevOS.HyperV;

public static class BrokerClient
{
    public static async Task<BrokerReply> ExecuteAsync(Operation operation)
    {
        var broker = ManagedPaths.Under(ManagedPaths.Install, "broker\\DevOS.Broker.exe");
        if (!File.Exists(broker)) return new(false, "BROKER_NOT_INSTALLED");
        var nonce = Guid.NewGuid().ToString("N");
        var start = new ProcessStartInfo(broker)
        {
            UseShellExecute = true, Verb = "runas", WindowStyle = ProcessWindowStyle.Hidden,
            Arguments = nonce + " " + Environment.ProcessId.ToString(System.Globalization.CultureInfo.InvariantCulture)
        };
        using var brokerProcess = Process.Start(start) ?? throw new IOException("Broker launch failed.");
        using var pipe = new NamedPipeClientStream(".", "DevOS-" + nonce, PipeDirection.InOut, PipeOptions.Asynchronous);
        using var connectionTimeout = new CancellationTokenSource(TimeSpan.FromSeconds(35));
        try
        {
            await pipe.ConnectAsync(connectionTimeout.Token);
            if (!PipeProtocol.GetNamedPipeServerProcessId(pipe.SafePipeHandle, out var pid) || pid != brokerProcess.Id)
                return new(false, "BROKER_IDENTITY_MISMATCH");
            using var operationTimeout = new CancellationTokenSource(TimeSpan.FromMinutes(31));
            await PipeProtocol.WriteAsync(pipe, new BrokerRequest(operation), operationTimeout.Token);
            var result = await PipeProtocol.ReadAsync(pipe, 65536, operationTimeout.Token);
            return JsonSerializer.Deserialize<BrokerReply>(result, Protocol.Json) ?? new(false, "INVALID_BROKER_REPLY");
        }
        catch (OperationCanceledException) { return new(false, "BROKER_TIMEOUT"); }
        catch (IOException) { return new(false, "BROKER_DISCONNECTED"); }
        catch (InvalidDataException) { return new(false, "INVALID_BROKER_REPLY"); }
        catch (JsonException) { return new(false, "INVALID_BROKER_REPLY"); }
    }
}
