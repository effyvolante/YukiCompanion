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
    private readonly Queue<object> commands = new();
    private readonly Dictionary<string, byte[]> contexts = new();
    private readonly Dictionary<string, TaskCompletionSource<BridgeEvent>> pending = new();
    private readonly object gate = new();
    private readonly string token = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
    public event Action<string>? ReplyReceived;
    public event Action? ReplySubmitted;
    public event Action<string>? ReplyUpdated;
    public event Action<string>? ErrorReceived;

    public string SessionToken => token;
    public ChromeBridgeClient(int port = 39173)
    {
        listener.Prefixes.Add($"http://127.0.0.1:{port}/"); listener.Start(); _ = ServeAsync();
    }
    public async Task SendAsync(string text, byte[]? contextImage = null, string? chatUrl = null, CancellationToken cancellationToken = default)
    {
        var id = Guid.NewGuid().ToString();
        var contextId = contextImage is null ? null : Guid.NewGuid().ToString();
        var completion = new TaskCompletionSource<BridgeEvent>(TaskCreationOptions.RunContinuationsAsynchronously);
        lock (gate)
        {
            pending[id] = completion;
            if (contextId is not null) contexts[contextId] = contextImage!;
            commands.Enqueue(new { type = "send_message", id, text, contextID = contextId, token, chatURL = chatUrl });
        }
        try { var result = await completion.Task.WaitAsync(TimeSpan.FromMinutes(2), cancellationToken); if (result.Type == "response_complete") ReplyReceived?.Invoke(result.Text ?? ""); else ErrorReceived?.Invoke(result.Message ?? "Chrome bridge error."); }
        catch (OperationCanceledException) { ErrorReceived?.Invoke("The Chrome request was cancelled."); }
        catch (TimeoutException) { ErrorReceived?.Invoke("Chrome did not return a response."); }
        finally { lock (gate) { pending.Remove(id); if (contextId is not null) contexts.Remove(contextId); } }
    }
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
        else if (context.Request.HttpMethod == "GET" && context.Request.Url?.AbsolutePath == "/commands" && Authorized(context)) { lock (gate) result = commands.Count > 0 ? commands.Dequeue() : new { type = "idle" }; }
        else if (context.Request.HttpMethod == "POST" && context.Request.Url?.AbsolutePath == "/events" && Authorized(context))
        {
            using var reader = new StreamReader(context.Request.InputStream, Encoding.UTF8); var value = JsonSerializer.Deserialize<BridgeEvent>(await reader.ReadToEndAsync(), JsonOptions);
            if (value?.Id is not null)
            {
                if (value.Type == "status" && string.Equals(value.State, "submitted", StringComparison.OrdinalIgnoreCase)) ReplySubmitted?.Invoke();
                if (value.Type == "response_update") ReplyUpdated?.Invoke(value.Text ?? "");
                if (value.Type is ("response_complete" or "error")) lock (gate) { if (pending.TryGetValue(value.Id, out var waiter)) waiter.TrySetResult(value); }
            }
            result = new { ok = true };
        }
        else { context.Response.StatusCode = (context.Request.Url?.AbsolutePath is "/commands" or "/events" || context.Request.Url?.AbsolutePath.StartsWith("/context/", StringComparison.Ordinal) == true) ? 401 : 404; result = new { error = "not found" }; }
        var bytes = binary ?? Encoding.UTF8.GetBytes(JsonSerializer.Serialize(result ?? new { }));
        context.Response.ContentType = binary is null ? "application/json" : "image/png";
        context.Response.ContentLength64 = bytes.Length; await context.Response.OutputStream.WriteAsync(bytes); context.Response.Close();
    }
    private bool Authorized(HttpListenerContext context) => context.Request.Headers["X-Yuki-Bridge-Token"] == token;
    public void Dispose() { if (listener.IsListening) listener.Stop(); listener.Close(); }
    private sealed record BridgeEvent(string? Type, string? Id, string? Text, string? Message, string? State);
}
