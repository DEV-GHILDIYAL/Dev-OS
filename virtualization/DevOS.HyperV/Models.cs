using System.Text.Json;
using System.Text.Json.Serialization;

namespace DevOS.HyperV;

public enum Operation { Inspect, PrepareMedia, Create, Start, Shutdown, ConnectInstallationNetwork, DisconnectNetwork, EjectMedia }
public enum EnvironmentState { Uninitialized, OffUnverified, Starting, Running, ShuttingDown, ErrorUnknown }
public sealed record VmConfiguration(int Generation = 2, int Cpu = 2, int MemoryMiB = 4096, int DiskGiB = 48)
{
    public void Validate()
    {
        if (this != new VmConfiguration()) throw new InvalidDataException("Only the approved Phase 1 configuration is supported.");
    }
}
public sealed record BrokerRequest(Operation Operation);
public sealed record BrokerReply(bool Success, string? Code, Observation? Observation = null);
public sealed record Observation
{
    public string Windows { get; init; } = "Unknown";
    public string Feature { get; init; } = "Unknown (administrator query required)";
    public bool Module { get; init; }
    public string Vmms { get; init; } = "Missing";
    public bool HypervisorPresent { get; init; }
    public long AvailableMemoryMiB { get; init; }
    public long AvailableStorageGiB { get; init; }
    public bool Registered { get; init; }
    public bool Exists { get; init; }
    public bool Owned { get; init; }
    public bool Compliant { get; init; }
    public string Power { get; init; } = "Unknown";
    public string? VmId { get; init; }
    public string Network { get; init; } = "Unknown";
    public string Code { get; init; } = "OK";
    public DateTimeOffset ObservedAt { get; init; } = DateTimeOffset.UtcNow;
    [JsonIgnore] public EnvironmentState State => StateMapping.Reconcile(this);
}
public static class StateMapping
{
    public static EnvironmentState Reconcile(Observation o)
    {
        if (o.Code != "OK") return EnvironmentState.ErrorUnknown;
        if (!o.Registered && !o.Exists) return EnvironmentState.Uninitialized;
        if (!o.Registered || !o.Exists || !o.Owned || !o.Compliant) return EnvironmentState.ErrorUnknown;
        return o.Power switch
        {
            "Off" => EnvironmentState.OffUnverified,
            "Running" => EnvironmentState.Running,
            "Starting" => EnvironmentState.Starting,
            "Stopping" => EnvironmentState.ShuttingDown,
            _ => EnvironmentState.ErrorUnknown
        };
    }
    public static string Label(this EnvironmentState state) => state switch
    {
        EnvironmentState.Uninitialized => "UNINITIALIZED",
        EnvironmentState.OffUnverified => "OFF / UNVERIFIED",
        EnvironmentState.Starting => "STARTING",
        EnvironmentState.Running => "RUNNING",
        EnvironmentState.ShuttingDown => "SHUTTING_DOWN",
        _ => "ERROR / UNKNOWN"
    };
}
public static class Protocol
{
    public const int MaxRequestBytes = 4096;
    public static readonly JsonSerializerOptions Json = new()
    {
        PropertyNameCaseInsensitive = true,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
        Converters = { new JsonStringEnumConverter(allowIntegerValues: false) }
    };
    public static BrokerRequest Parse(ReadOnlySpan<byte> bytes)
    {
        if (bytes.Length is 0 or > MaxRequestBytes) throw new InvalidDataException("Invalid request size.");
        var request = JsonSerializer.Deserialize<BrokerRequest>(bytes, Json) ?? throw new InvalidDataException("Empty request.");
        if (!Enum.IsDefined(request.Operation)) throw new InvalidDataException("Invalid operation.");
        using var document = JsonDocument.Parse(bytes.ToArray());
        var properties = document.RootElement.EnumerateObject().ToArray();
        if (properties.Length != 1 || !properties[0].Name.Equals("Operation", StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Only Operation is accepted.");
        return request;
    }
}
public static class Ownership
{
    public static bool Matches(Guid registered, Guid actual, string expectedMarker, string actualMarker) =>
        registered != Guid.Empty && registered == actual && expectedMarker.Length >= 32 && expectedMarker == actualMarker;
}
public static class ManagedPaths
{
    public static string Root => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "DevOS");
    public static string Install => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "DevOS");
    public static string Under(string root, string relative)
    {
        if (Path.IsPathRooted(relative) || relative.Contains(':') || relative.Split('\\', '/').Any(s => s is ".." or "."))
            throw new InvalidDataException("Invalid managed path.");
        var canonical = Path.GetFullPath(Path.Combine(root, relative));
        if (!canonical.StartsWith(Path.GetFullPath(root).TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Path outside managed directory.");
        RejectReparsePoints(canonical);
        return canonical;
    }
    public static void RejectReparsePoints(string path)
    {
        for (var current = Path.GetFullPath(path); current != null; current = Path.GetDirectoryName(current))
            if ((File.Exists(current) || Directory.Exists(current)) && (File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidDataException("Reparse points are not allowed.");
    }
}
