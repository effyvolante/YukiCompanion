using System.Net;
using System.Text;
using System.Text.Json;

namespace YukiCompanion.Windows;

public sealed class ChromeBridgeClient : IDisposable
{
    private readonly HttpListener listener = new();
    private readonly Queue<object> commands = new();
    private readonly Dictionary<string, TaskCompletionSource<BridgeEvent>> pending = new();
    private readonly object gate = new();
    public event Action<string>? ReplyReceived;
    public event Action<string>? ErrorReceived;

    public ChromeBridgeClient()
    {
        listener.Prefixes.Add("http://127.0.0.1:39173/"); listener.Start(); _ = ServeAsync();
    }
    public async Task SendAsync(string text, CancellationToken token = default)
    {
        var id = Guid.NewGuid().ToString();
        var completion = new TaskCompletionSource<BridgeEvent>(TaskCreationOptions.RunContinuationsAsynchronously);
        lock (gate) { pending[id] = completion; commands.Enqueue(new { type = "send_message", id, text }); }
        try { var result = await completion.Task.WaitAsync(TimeSpan.FromMinutes(2), token); if (result.Type == "response_complete") ReplyReceived?.Invoke(result.Text ?? ""); else ErrorReceived?.Invoke(result.Message ?? "Chrome bridge error."); }
        catch (OperationCanceledException) { ErrorReceived?.Invoke("The Chrome request was cancelled."); }
        catch (TimeoutException) { ErrorReceived?.Invoke("Chrome did not return a response."); }
        finally { lock (gate) { pending.Remove(id); } }
    }
    private async Task ServeAsync()
    {
        while (listener.IsListening) { try { var context = await listener.GetContextAsync(); _ = HandleAsync(context); } catch (HttpListenerException) { break; } }
    }
    private async Task HandleAsync(HttpListenerContext context)
    {
        context.Response.Headers["Access-Control-Allow-Origin"] = "*"; context.Response.Headers["Access-Control-Allow-Headers"] = "content-type";
        object? result = null;
        if (context.Request.HttpMethod == "OPTIONS") context.Response.StatusCode = 204;
        else if (context.Request.HttpMethod == "GET" && context.Request.Url?.AbsolutePath == "/commands") { lock (gate) result = commands.Count > 0 ? commands.Dequeue() : new { type = "idle" }; }
        else if (context.Request.HttpMethod == "POST" && context.Request.Url?.AbsolutePath == "/events")
        {
            using var reader = new StreamReader(context.Request.InputStream, Encoding.UTF8); var value = JsonSerializer.Deserialize<BridgeEvent>(await reader.ReadToEndAsync());
            if (value?.Id is not null && value.Type is ("response_complete" or "error")) lock (gate) { if (pending.TryGetValue(value.Id, out var waiter)) waiter.TrySetResult(value); }
            result = new { ok = true };
        }
        else { context.Response.StatusCode = 404; result = new { error = "not found" }; }
        var bytes = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(result ?? new { })); context.Response.ContentType = "application/json"; context.Response.ContentLength64 = bytes.Length; await context.Response.OutputStream.WriteAsync(bytes); context.Response.Close();
    }
    public void Dispose() { if (listener.IsListening) listener.Stop(); listener.Close(); }
    private sealed record BridgeEvent(string? Type, string? Id, string? Text, string? Message);
}
