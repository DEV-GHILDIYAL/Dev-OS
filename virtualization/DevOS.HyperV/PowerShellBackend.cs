using System.Diagnostics;
using System.Text;
using System.Text.Json;

namespace DevOS.HyperV;

public sealed class PowerShellBackend
{
    public async Task<BrokerReply> ExecuteAsync(Operation operation, CancellationToken cancellationToken)
    {
        if (!Enum.IsDefined(operation)) throw new InvalidDataException("Invalid operation.");
        using var resource = typeof(PowerShellBackend).Assembly.GetManifestResourceStream("DevOS.HyperV.Scripts.HyperV.ps1")!;
        using var reader = new StreamReader(resource);
        // Only an enum literal and embedded, build-time code enter the command.
        var script = "$operation = '" + operation + "'\r\n" + await reader.ReadToEndAsync(cancellationToken);
        var start = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe"))
        {
            UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true,
            RedirectStandardInput = true
        };
        start.ArgumentList.Add("-NoProfile");
        start.ArgumentList.Add("-NonInteractive");
        start.ArgumentList.Add("-EncodedCommand");
        start.ArgumentList.Add(Convert.ToBase64String(Encoding.Unicode.GetBytes("[ScriptBlock]::Create([Console]::In.ReadToEnd()).Invoke()")));
        using var process = Process.Start(start) ?? throw new IOException("Cannot start Windows PowerShell.");
        var stdout = ReadBoundedAsync(process.StandardOutput, cancellationToken);
        var stderr = ReadBoundedAsync(process.StandardError, cancellationToken);
        try
        {
            await process.StandardInput.WriteAsync(script.AsMemory(), cancellationToken);
            process.StandardInput.Close();
            await process.WaitForExitAsync(cancellationToken);
            var output = await stdout;
            _ = await stderr; // Never persist raw diagnostic output.
            if (process.ExitCode != 0) return new(false, "BACKEND_FAILED");
            try { return JsonSerializer.Deserialize<BrokerReply>(output, Protocol.Json) ?? new(false, "INVALID_BACKEND_RESPONSE"); }
            catch (JsonException) { return new(false, "INVALID_BACKEND_RESPONSE"); }
        }
        catch (OperationCanceledException)
        {
            if (!process.HasExited) process.Kill(entireProcessTree: true);
            await process.WaitForExitAsync(CancellationToken.None);
            return new(false, "TIMEOUT_RECHECK_STATE");
        }
    }
    private static async Task<string> ReadBoundedAsync(StreamReader reader, CancellationToken token)
    {
        var output = new StringBuilder();
        var buffer = new char[4096];
        int count;
        while ((count = await reader.ReadAsync(buffer.AsMemory(), token)) != 0)
        {
            if (output.Length + count <= 65536) output.Append(buffer, 0, count);
        }
        return output.ToString();
    }
}
