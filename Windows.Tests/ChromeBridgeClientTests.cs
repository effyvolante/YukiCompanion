using System;
using System.Net;
using System.Net.Http;
using System.Net.Http.Json;
using System.Threading;
using System.Threading.Tasks;
using Xunit;

namespace YukiCompanion.Windows.Tests;

public sealed class ChromeBridgeClientTests
{
    [Fact]
    public async Task QueuesCommandAndCompletesResponse()
    {
        using var bridge = new YukiCompanion.Windows.ChromeBridgeClient(39174);
        using var http = new HttpClient { BaseAddress = new Uri("http://127.0.0.1:39174") };
        var received = new TaskCompletionSource<string>();
        bridge.ReplyReceived += received.SetResult;
        var send = bridge.SendAsync("hello");
        using var commandRequest = new HttpRequestMessage(HttpMethod.Get, "/commands");
        commandRequest.Headers.Add("X-Yuki-Bridge-Token", bridge.SessionToken);
        using var commandResponse = await http.SendAsync(commandRequest);
        var command = await commandResponse.Content.ReadFromJsonAsync<BridgeCommand>();
        Assert.Equal("send_message", command!.Type);
        Assert.Equal("hello", command.Text);
        var response = await http.PostAsJsonAsync("/events", new { type = "response_complete", id = command.Id, text = "Hi!" }, new CancellationTokenSource(2000).Token, bridge.SessionToken);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("Hi!", await received.Task.WaitAsync(TimeSpan.FromSeconds(2)));
        await send;
    }

    [Fact]
    public async Task RejectsEventsWithoutSessionToken()
    {
        using var bridge = new YukiCompanion.Windows.ChromeBridgeClient(39175);
        using var http = new HttpClient { BaseAddress = new Uri("http://127.0.0.1:39175") };
        var response = await http.PostAsJsonAsync("/events", new { type = "error", id = "fake", message = "fake" });
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    private sealed record BridgeCommand(string? Type, string? Id, string? Text);
}

internal static class HttpClientExtensions
{
    public static Task<HttpResponseMessage> PostAsJsonAsync(this HttpClient client, string uri, object value, CancellationToken token, string sessionToken) =>
        client.PostAsync(uri, JsonContent.Create(value), token, sessionToken);
    private static async Task<HttpResponseMessage> PostAsync(this HttpClient client, string uri, HttpContent content, CancellationToken token, string sessionToken)
    { using var request = new HttpRequestMessage(HttpMethod.Post, uri) { Content = content }; request.Headers.Add("X-Yuki-Bridge-Token", sessionToken); return await client.SendAsync(request, token); }
}
