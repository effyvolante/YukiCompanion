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
        var command = await commandResponse.Content.ReadFromJsonAsync<BridgeCommand>(new System.Text.Json.JsonSerializerOptions { PropertyNameCaseInsensitive = true });
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

    [Fact]
    public async Task ExposesSessionAndRejectsUnauthorizedCommands()
    {
        using var bridge = new YukiCompanion.Windows.ChromeBridgeClient(39176);
        using var http = new HttpClient { BaseAddress = new Uri("http://127.0.0.1:39176") };
        var session = await http.GetFromJsonAsync<Session>("/session");
        Assert.Equal(bridge.SessionToken, session!.Token);
        var response = await http.GetAsync("/commands");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task ServesQueuedContextImage()
    {
        using var bridge = new YukiCompanion.Windows.ChromeBridgeClient(39177);
        using var http = new HttpClient { BaseAddress = new Uri("http://127.0.0.1:39177") };
        var send = bridge.SendAsync("look", new byte[] { 1, 2, 3, 4 });
        using var request = new HttpRequestMessage(HttpMethod.Get, "/commands");
        request.Headers.Add("X-Yuki-Bridge-Token", bridge.SessionToken);
        var commandResponse = await http.SendAsync(request);
        var command = await commandResponse.Content.ReadFromJsonAsync<BridgeCommand>();
        Assert.NotNull(command!.ContextID);
        using var contextRequest = new HttpRequestMessage(HttpMethod.Get, $"/context/{command.ContextID}");
        contextRequest.Headers.Add("X-Yuki-Bridge-Token", bridge.SessionToken);
        var contextResponse = await http.SendAsync(contextRequest);
        Assert.Equal(new byte[] { 1, 2, 3, 4 }, await contextResponse.Content.ReadAsByteArrayAsync());
        using var eventRequest = new HttpRequestMessage(HttpMethod.Post, "/events") { Content = JsonContent.Create(new { type = "response_complete", id = command.Id, text = "done" }) };
        eventRequest.Headers.Add("X-Yuki-Bridge-Token", bridge.SessionToken);
        await http.SendAsync(eventRequest);
        await send;
    }

    [Fact]
    public async Task DeliversMultipleConsecutiveMessages()
    {
        using var bridge = new YukiCompanion.Windows.ChromeBridgeClient(39178);
        using var http = new HttpClient { BaseAddress = new Uri("http://127.0.0.1:39178") };
        var replies = new System.Collections.Concurrent.ConcurrentBag<string>();
        bridge.ReplyReceived += replies.Add;
        var first = bridge.SendAsync("one");
        var second = bridge.SendAsync("two");
        var commands = new List<BridgeCommand>();
        for (var index = 0; index < 2; index++)
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, "/commands");
            request.Headers.Add("X-Yuki-Bridge-Token", bridge.SessionToken);
            var response = await http.SendAsync(request);
            commands.Add((await response.Content.ReadFromJsonAsync<BridgeCommand>())!);
        }
        foreach (var command in commands)
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, "/events") { Content = JsonContent.Create(new { type = "response_complete", id = command.Id, text = $"reply-{command.Text}" }) };
            request.Headers.Add("X-Yuki-Bridge-Token", bridge.SessionToken);
            await http.SendAsync(request);
        }
        await Task.WhenAll(first, second);
        Assert.Equal(new[] { "reply-one", "reply-two" }, replies.OrderBy(value => value));
    }

    private sealed record BridgeCommand(string? Type, string? Id, string? Text, string? ContextID);
    private sealed record Session(string? Token);
}

internal static class HttpClientExtensions
{
    public static Task<HttpResponseMessage> PostAsJsonAsync(this HttpClient client, string uri, object value, CancellationToken token, string sessionToken) =>
        client.PostAsync(uri, JsonContent.Create(value), token, sessionToken);
    private static async Task<HttpResponseMessage> PostAsync(this HttpClient client, string uri, HttpContent content, CancellationToken token, string sessionToken)
    { using var request = new HttpRequestMessage(HttpMethod.Post, uri) { Content = content }; request.Headers.Add("X-Yuki-Bridge-Token", sessionToken); return await client.SendAsync(request, token); }
}
