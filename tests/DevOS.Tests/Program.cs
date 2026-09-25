using System.Text;
using System.IO.Pipes;
using DevOS.HyperV;

if (args is ["--inspect"] or ["--broker-inspect"])
{
    using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(45));
    var reply = args[0] == "--broker-inspect" ? await BrokerClient.ExecuteAsync(Operation.Inspect)
        : await new PowerShellBackend().ExecuteAsync(Operation.Inspect, timeout.Token);
    Console.WriteLine(System.Text.Json.JsonSerializer.Serialize(reply, Protocol.Json));
    return reply.Success ? 0 : 1;
}

var tests = new List<(string Name, Action Test)>();
void Test(string name, Action action) => tests.Add((name, action));
void Assert(bool value) { if (!value) throw new Exception("Assertion failed"); }
void Reject(Action action) { try { action(); } catch { return; } throw new Exception("Expected rejection"); }
Test("approved configuration", () => new VmConfiguration().Validate());
Test("reject altered configuration", () => Reject(() => new VmConfiguration(Cpu: 4).Validate()));
Test("ownership requires matching ID and marker", () =>
{
    var id = Guid.NewGuid(); var marker = "DevOS:" + Guid.NewGuid().ToString("N");
    Assert(Ownership.Matches(id, id, marker, marker));
    Assert(!Ownership.Matches(id, Guid.NewGuid(), marker, marker));
    Assert(!Ownership.Matches(id, id, marker, marker + "x"));
    Assert(!Ownership.Matches(Guid.Empty, Guid.Empty, marker, marker));
});
var good = new Observation { Registered = true, Exists = true, Owned = true, Compliant = true, Power = "Running" };
Test("map power states", () =>
{
    Assert(good.State == EnvironmentState.Running);
    Assert((good with { Power = "Off" }).State == EnvironmentState.OffUnverified);
    Assert((good with { Power = "Starting" }).State == EnvironmentState.Starting);
    Assert((good with { Power = "Stopping" }).State == EnvironmentState.ShuttingDown);
    Assert((good with { Power = "Saved" }).State == EnvironmentState.ErrorUnknown);
});
Test("reconcile missing, drift and query failure", () =>
{
    Assert(new Observation().State == EnvironmentState.Uninitialized);
    Assert((good with { Exists = false }).State == EnvironmentState.ErrorUnknown);
    Assert((good with { Owned = false }).State == EnvironmentState.ErrorUnknown);
    Assert((good with { Compliant = false }).State == EnvironmentState.ErrorUnknown);
    Assert((good with { Code = "DENIED" }).State == EnvironmentState.ErrorUnknown);
});
Test("restart uses new observation", () =>
{
    var before = good with { Power = "Off" }; var after = good;
    Assert(before.State == EnvironmentState.OffUnverified && after.State == EnvironmentState.Running);
});
Test("managed paths reject escape and alternate streams", () =>
{
    var root = Path.Combine(Path.GetTempPath(), "DevOS-tests");
    Assert(ManagedPaths.Under(root, "vm\\disk.vhdx").StartsWith(root));
    foreach (var path in new[] { "..\\escape", "C:\\escape", "disk:stream", ".\\disk", "a/../disk" }) Reject(() => ManagedPaths.Under(root, path));
});
Test("broker accepts only enum operation", () =>
{
    Assert(Protocol.Parse(Encoding.UTF8.GetBytes("{\"Operation\":\"Start\"}")).Operation == Operation.Start);
    foreach (var input in new[] { "{}", "null", "{\"Operation\":100}", "{\"Operation\":\"Delete\"}", "{\"Operation\":\"Start\",\"Path\":\"C:\\\\foo\"}", "{\"Operation\":\"Start\",\"Operation\":\"Shutdown\"}" })
        Reject(() => Protocol.Parse(Encoding.UTF8.GetBytes(input)));
    Reject(() => Protocol.Parse(new byte[4097]));
});
Test("closed pipe reports transport failure", () =>
{
    var name = "DevOS-test-" + Guid.NewGuid().ToString("N");
    using var server = new NamedPipeServerStream(name, PipeDirection.Out, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous);
    using var client = new NamedPipeClientStream(".", name, PipeDirection.In, PipeOptions.Asynchronous);
    var accepted = server.WaitForConnectionAsync();
    client.Connect();
    accepted.GetAwaiter().GetResult();
    server.Dispose();
    try { PipeProtocol.ReadAsync(client, 65536, CancellationToken.None).GetAwaiter().GetResult(); }
    catch (IOException ex) when (ex.InnerException is EndOfStreamException) { return; }
    throw new Exception("Expected a transport failure after pipe closure.");
});
var failed = 0;
foreach (var test in tests)
{
    try { test.Test(); Console.WriteLine("PASS " + test.Name); }
    catch (Exception e) { failed++; Console.WriteLine("FAIL " + test.Name + ": " + e.Message); }
}
Console.WriteLine($"{tests.Count - failed} PASS, {failed} FAIL");
return failed == 0 ? 0 : 1;
