using System.Net;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace YukiCompanion.Windows;

public sealed class ChromeBridgeClient : IDisposable
{
    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNameCaseInsensitive = true };
    private readonly HttpListener listener = new();
    private readonly List<QueuedCommand> commands = new();
    private readonly Dictionary<string, byte[]> contexts = new();
    private readonly Dictionary<string, PendingRequest> pending = new();
    private readonly object gate = new();
    private readonly System.Threading.Timer connectionTimer;
    private DateTimeOffset? lastBridgeStatus;
    private readonly string token = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
    public event Action<string, string>? ReplyReceived;
    public event Action<string>? ReplySubmitted;
    public event Action<string, string>? ReplyUpdated;
    public event Action<string, string>? PhaseChanged;
    public event Action<string, string>? ErrorReceived;
    public event Action<string>? ConnectionStateChanged;

    public string SessionToken => token;
    public ChromeBridgeClient(int port = 39173)
    {
        listener.Prefixes.Add($"http://127.0.0.1:{port}/"); listener.Start(); _ = ServeAsync();
        connectionTimer = new System.Threading.Timer(_ => CheckConnectionHealth(), null, TimeSpan.FromSeconds(3), TimeSpan.FromSeconds(3));
    }
    public void Reconnect()
    {
        lock (gate) commands.Add(new QueuedCommand(new { type = "reconnect", token }, null));
        ConnectionStateChanged?.Invoke("connecting");
    }
    public Task SendAsync(string text, byte[]? contextImage = null, CancellationToken cancellationToken = default) =>
        SendAsync(Guid.NewGuid().ToString(), text, contextImage, cancellationToken);

    public async Task SendAsync(string id, string text, byte[]? contextImage = null, CancellationToken cancellationToken = default)
    {
        var contextId = contextImage is null ? null : Guid.NewGuid().ToString();
        var request = new PendingRequest();
        lock (gate)
        {
            pending[id] = request;
            if (contextId is not null) contexts[contextId] = contextImage!;
            commands.Add(new QueuedCommand(new { type = "send_message", id, text, contextID = contextId, token }, id));
        }
        PhaseChanged?.Invoke(id, "queued");
        try
        {
            var result = await WaitForCompletionAsync(request, cancellationToken);
            if (result.Type == "response_complete") ReplyReceived?.Invoke(id, result.Text ?? "");
            else ErrorReceived?.Invoke(id, result.Message ?? "Chrome bridge error.");
        }
        catch (OperationCanceledException) { ErrorReceived?.Invoke(id, "The Chrome request was cancelled."); }
        catch (TimeoutException) { ErrorReceived?.Invoke(id, TimeoutMessage(request.Phase)); }
        finally { lock (gate) { pending.Remove(id); commands.RemoveAll(value => value.MessageId == id); if (contextId is not null) contexts.Remove(contextId); } }
    }
    private static async Task<BridgeEvent> WaitForCompletionAsync(PendingRequest request, CancellationToken cancellationToken)
    {
        while (true)
        {
            var timeout = request.Phase switch { "queued" => TimeSpan.FromSeconds(30), "delivered" => TimeSpan.FromSeconds(45), "submitted" => TimeSpan.FromSeconds(150), "responding" => TimeSpan.FromSeconds(300), _ => TimeSpan.FromSeconds(30) };
            var remaining = timeout - (DateTimeOffset.UtcNow - request.LastActivity);
            if (remaining <= TimeSpan.Zero) throw new TimeoutException();
            var delay = Task.Delay(TimeSpan.FromSeconds(Math.Min(1, remaining.TotalSeconds)), cancellationToken);
            if (await Task.WhenAny(request.Completion.Task, delay) == request.Completion.Task) return await request.Completion.Task;
        }
    }
    private static string TimeoutMessage(string phase) => phase switch
    {
        "queued" => "Yuki couldn’t reach the browser extension. Open the bound ChatGPT tab, then choose Reconnect ChatGPT.",
        "delivered" => "ChatGPT received the message but did not confirm submission.",
        "submitted" => "ChatGPT accepted the message but did not begin a response.",
        "responding" => "ChatGPT stopped updating its response.",
        _ => "Yuki’s browser connection stopped unexpectedly."
    };
    private async Task ServeAsync()
    {
        while (listener.IsListening) { try { var context = await listener.GetContextAsync(); _ = HandleAsync(context); } catch (HttpListenerException) { break; } catch (ObjectDisposedException) { break; } }
    }
    private async Task HandleAsync(HttpListenerContext context)
    {
        context.Response.Headers["Access-Control-Allow-Origin"] = "*";
        context.Response.Headers["Access-Control-Allow-Headers"] = "content-type, x-yuki-bridge-token";
        context.Response.Headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS";
        object? result = null;
        byte[]? binary = null;
        if (context.Request.HttpMethod == "OPTIONS") context.Response.StatusCode = 204;
        else if (context.Request.HttpMethod == "GET" && context.Request.Url?.AbsolutePath == "/session") result = new { token };
        else if (context.Request.HttpMethod == "GET" && context.Request.Url?.AbsolutePath.StartsWith("/context/", StringComparison.Ordinal) == true && Authorized(context))
        {
            var contextId = Uri.UnescapeDataString(context.Request.Url.AbsolutePath[9..]);
            lock (gate) { contexts.TryGetValue(contextId, out binary); }
            if (binary is null) { context.Response.StatusCode = 404; result = new { error = "context not found" }; }
        }
        else if (context.Request.HttpMethod == "GET" && context.Request.Url?.AbsolutePath == "/commands" && Authorized(context))
        {
            lock (gate)
            {
                var now = DateTimeOffset.UtcNow;
                var command = commands.FirstOrDefault(value => value.LeasedAt is null || now - value.LeasedAt >= TimeSpan.FromSeconds(10));
                if (command is null) result = new { type = "idle" };
                else { command.LeasedAt = now; result = command.Payload; if (command.MessageId is null) commands.Remove(command); }
            }
        }
        else if (context.Request.HttpMethod == "POST" && context.Request.Url?.AbsolutePath == "/events" && Authorized(context))
        {
            using var reader = new StreamReader(context.Request.InputStream, Encoding.UTF8); var value = JsonSerializer.Deserialize<BridgeEvent>(await reader.ReadToEndAsync(), JsonOptions);
            if (value?.Type == "bridge_status" && value.State is not null) { lastBridgeStatus = DateTimeOffset.UtcNow; ConnectionStateChanged?.Invoke(value.State); }
            else if (value?.Id is not null)
            {
                if (value.Type == "status" && value.State is not null)
                {
                    PhaseChanged?.Invoke(value.Id, value.State);
                    Touch(value.Id, value.State);
                    if (string.Equals(value.State, "submitted", StringComparison.OrdinalIgnoreCase)) { Acknowledge(value.Id); ReplySubmitted?.Invoke(value.Id); }
                }
                if (value.Type == "response_update") { Touch(value.Id, "responding"); PhaseChanged?.Invoke(value.Id, "responding"); ReplyUpdated?.Invoke(value.Id, value.Text ?? ""); }
                if (value.Type is ("response_complete" or "error")) lock (gate) { commands.RemoveAll(item => item.MessageId == value.Id); if (pending.TryGetValue(value.Id, out var waiter)) waiter.Completion.TrySetResult(value); }
            }
            result = new { ok = true };
        }
        else { context.Response.StatusCode = (context.Request.Url?.AbsolutePath is "/commands" or "/events" || context.Request.Url?.AbsolutePath.StartsWith("/context/", StringComparison.Ordinal) == true) ? 401 : 404; result = new { error = "not found" }; }
        var bytes = binary ?? Encoding.UTF8.GetBytes(JsonSerializer.Serialize(result ?? new { }));
        context.Response.ContentType = binary is null ? "application/json" : "image/png";
        context.Response.ContentLength64 = bytes.Length; await context.Response.OutputStream.WriteAsync(bytes); context.Response.Close();
    }
    private bool Authorized(HttpListenerContext context) => context.Request.Headers["X-Yuki-Bridge-Token"] == token;
    private void CheckConnectionHealth() { if (lastBridgeStatus is { } last && DateTimeOffset.UtcNow - last > TimeSpan.FromSeconds(45)) ConnectionStateChanged?.Invoke("disconnected"); }
    private void Touch(string id, string phase) { lock (gate) { if (pending.TryGetValue(id, out var request)) { request.Phase = phase; request.LastActivity = DateTimeOffset.UtcNow; } } }
    private void Acknowledge(string id) { lock (gate) commands.RemoveAll(value => value.MessageId == id); }
    public void Dispose() { connectionTimer.Dispose(); if (listener.IsListening) listener.Stop(); listener.Close(); }
    private sealed class PendingRequest
    {
        public TaskCompletionSource<BridgeEvent> Completion { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public string Phase { get; set; } = "queued";
        public DateTimeOffset LastActivity { get; set; } = DateTimeOffset.UtcNow;
    }
    private sealed class QueuedCommand(object payload, string? messageId)
    {
        public object Payload { get; } = payload;
        public string? MessageId { get; } = messageId;
        public DateTimeOffset? LeasedAt { get; set; }
    }
    private sealed record BridgeEvent(string? Type, string? Id, string? Text, string? Message, string? State);
}
