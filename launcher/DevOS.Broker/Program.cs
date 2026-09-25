using System.Diagnostics;
using System.IO.Pipes;
using System.Security.Principal;
using System.Security.AccessControl;
using DevOS.HyperV;

if (args.Length != 2 || !Guid.TryParseExact(args[0], "N", out var nonce) ||
    !int.TryParse(args[1], out var launcherPid) || launcherPid <= 0) return 2;
NamedPipeServerStream? pipe = null;
var authenticated = false;
try
{
    using var identity = WindowsIdentity.GetCurrent();
    if (!new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator)) return 3;
    var expected = ManagedPaths.Under(ManagedPaths.Install, "broker\\DevOS.Broker.exe");
    if (!string.Equals(Environment.ProcessPath, expected, StringComparison.OrdinalIgnoreCase)) return 4;
    using var launcher = Process.GetProcessById(launcherPid);
    if (launcher.SessionId != Process.GetCurrentProcess().SessionId) return 5;
    using var connectTimeout = new CancellationTokenSource(TimeSpan.FromSeconds(30));
    // Explicit user ACL works across split UAC tokens; CurrentUserOnly can select
    // the elevated token's Administrators owner and reject the normal-user UI.
    var security = new PipeSecurity();
    security.SetAccessRuleProtection(true, false);
    security.SetOwner(identity.User!);
    security.AddAccessRule(new PipeAccessRule(new SecurityIdentifier("S-1-5-2"), PipeAccessRights.FullControl, AccessControlType.Deny));
    security.AddAccessRule(new PipeAccessRule(identity.User!, PipeAccessRights.FullControl, AccessControlType.Allow));
    pipe = NamedPipeServerStreamAcl.Create("DevOS-" + nonce.ToString("N"), PipeDirection.InOut, 1,
        PipeTransmissionMode.Byte, PipeOptions.Asynchronous, 4096, 65536, security);
    await pipe.WaitForConnectionAsync(connectTimeout.Token);
    if (!PipeProtocol.GetNamedPipeClientProcessId(pipe.SafePipeHandle, out var clientPid) || clientPid != launcherPid) return 6;
    authenticated = true;
    var request = Protocol.Parse(await PipeProtocol.ReadAsync(pipe, Protocol.MaxRequestBytes, connectTimeout.Token));
    ManagedPaths.RejectReparsePoints(ManagedPaths.Root);
    var lockPath = ManagedPaths.Under(ManagedPaths.Root, "operation.lock");
    // A protected exclusive file lock serializes operations across launcher instances.
    using var operationLock = new FileStream(lockPath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
    using var timeout = new CancellationTokenSource(request.Operation is Operation.Create or Operation.PrepareMedia
        ? TimeSpan.FromMinutes(30) : TimeSpan.FromMinutes(3));
    var reply = await new PowerShellBackend().ExecuteAsync(request.Operation, timeout.Token);
    var auditPath = ManagedPaths.Under(ManagedPaths.Root, "events.jsonl");
    // Bounded, allowlisted audit data; no process output, paths or exception text.
    if (!File.Exists(auditPath) || new FileInfo(auditPath).Length < 1024 * 1024)
        await File.AppendAllTextAsync(auditPath, System.Text.Json.JsonSerializer.Serialize(new
        {
            Time = DateTimeOffset.UtcNow, Operation = request.Operation.ToString(), reply.Success,
            Code = System.Text.RegularExpressions.Regex.IsMatch(reply.Code ?? "", "^[A-Z_]{1,80}$") ? reply.Code : "UNKNOWN_ERROR"
        }) + Environment.NewLine);
    using var replyTimeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
    await PipeProtocol.WriteAsync(pipe, reply, replyTimeout.Token);
    return reply.Success ? 0 : 1;
}
catch
{
    if (authenticated && pipe?.IsConnected == true)
    {
        try
        {
            using var replyTimeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            await PipeProtocol.WriteAsync(pipe, new BrokerReply(false, "BROKER_FAILED_RECHECK_STATE"), replyTimeout.Token);
        }
        catch { }
    }
    return 10;
}
finally { pipe?.Dispose(); }
