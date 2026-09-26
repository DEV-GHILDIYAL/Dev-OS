using System.Diagnostics;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace DevOS.Jev;

public sealed record JevQuestion(string Type, string Instructions, string[]? Options = null);
public sealed record JevResult(string LikelyArea, double Confidence, bool RequiresDeeperReasoning, long LatencyMs, int InputBytes, bool UsedFallback);

public sealed class JevClient(HttpClient? http = null)
{
    private readonly HttpClient http = http ?? new() { Timeout = TimeSpan.FromSeconds(10) };
    public async Task<JevResult?> DiagnoseAsync(object state, CancellationToken token = default)
    {
        var key = Environment.GetEnvironmentVariable("JEV_API_KEY");
        if (string.IsNullOrWhiteSpace(key)) return null;
        var safe = JevRedactor.Redact(state);
        var payload = new { model = "jev-latest", state = safe, questions = new { area = new { type = "choice", instructions = "Which debugging area is most likely responsible?", criteria = new Dictionary<string, string> { ["application_code"] = "Application implementation", ["configuration"] = "Configuration", ["dependency"] = "Dependency", ["database"] = "Database", ["networking"] = "Networking", ["permissions"] = "Permissions", ["infrastructure"] = "Infrastructure", ["build"] = "Build", ["deployment"] = "Deployment", ["environment"] = "Environment", ["insufficient_information"] = "Insufficient information" } }, deeper = new { type = "noul", instructions = "Is deeper investigation needed before changing code?" } } };
        var bytes = JsonSerializer.SerializeToUtf8Bytes(payload);
        var watch = Stopwatch.StartNew();
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, "https://api.typesafe.ai/v1/systemone") { Content = JsonContent.Create(payload) };
            request.Headers.Authorization = new("Bearer", key);
            using var response = await http.SendAsync(request, token);
            if (!response.IsSuccessStatusCode) return null;
            var root = JsonNode.Parse(await response.Content.ReadAsStringAsync(token));
            var answer = root?["answers"]?["area"];
            var area = answer?["choice"]?.GetValue<string>() ?? answer?["value"]?.GetValue<string>();
            if (string.IsNullOrWhiteSpace(area)) return null;
            var confidence = answer?["confidence"]?.GetValue<double>() ?? 0;
            var deeper = root?["answers"]?["deeper"]?["noul"]?.GetValue<double>() >= 0.5;
            return new(area, confidence, deeper, watch.ElapsedMilliseconds, bytes.Length, false);
        }
        catch (HttpRequestException) { return null; }
        catch (OperationCanceledException) when (!token.IsCancellationRequested) { return null; }
        catch (JsonException) { return null; }
    }
}

public static class JevRedactor
{
    public static string Redact(object value) => Redact(JsonSerializer.Serialize(value));
    public static string Redact(string value)
    {
        value = System.Text.RegularExpressions.Regex.Replace(value, "(?i)(api[_-]?key|token|password|secret|private[_-]?key|connectionstring)\\s*[:=]\\s*[^,;\\s}]+", "$1=[REDACTED]");
        return value.Replace(Environment.GetEnvironmentVariable("JEV_API_KEY") ?? "", "[REDACTED]", StringComparison.Ordinal);
    }
}
