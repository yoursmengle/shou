using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using Shou.Windows.Core;

namespace Shou.Windows.Platform.Tests;

public sealed class WindowsDesktopUpdatesTests
{
    private sealed class Handler(Func<HttpResponseMessage> response) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Assert.Equal("https://api.github.com/repos/limecloud/shou/releases/latest", request.RequestUri!.AbsoluteUri);
            Assert.Null(request.Headers.Authorization);
            Assert.False(request.Headers.Contains("Cookie"));
            Assert.Equal(HttpMethod.Get, request.Method);
            token.ThrowIfCancellationRequested();
            return Task.FromResult(response());
        }
    }

    [Theory]
    [InlineData(302, "application/json", 100)]
    [InlineData(403, "application/json", 100)]
    [InlineData(200, "text/html", 100)]
    [InlineData(200, "application/json", 1048577)]
    public async Task RejectsRedirectsErrorsWrongTypesAndOversize(int status, string type, int length)
    {
        var source = new WindowsDesktopUpdates(() => new Handler(() =>
        {
            var response = new HttpResponseMessage((HttpStatusCode)status) { Content = new ByteArrayContent(new byte[length]) };
            response.Content.Headers.ContentType = new MediaTypeHeaderValue(type);
            return response;
        }));
        await Assert.ThrowsAsync<ShouException>(() => source.CheckAsync("0.17.0", "x64", default));
    }

    [Theory]
    [InlineData(false, "x64")]
    [InlineData(true, "x64")]
    [InlineData(true, "arm64")]
    public async Task ReturnsValidatedReleaseAndHonorsCancellation(bool installed, string architecture)
    {
        var filename = $"Shou-0.18.0-windows-{architecture}" + (installed ? "-Setup.exe" : ".zip");
        var bytes = JsonSerializer.SerializeToUtf8Bytes(new { tag_name = "v0.18.0", draft = false, prerelease = false,
            html_url = "https://github.com/limecloud/shou/releases/tag/v0.18.0", body = "notes",
            assets = new[] { new { name = filename, size = 100,
                browser_download_url = "https://github.com/limecloud/shou/releases/download/v0.18.0/" + filename } } });
        var source = new WindowsDesktopUpdates(() => new Handler(() => new(HttpStatusCode.OK)
        { Content = new ByteArrayContent(bytes) { Headers = { ContentType = new MediaTypeHeaderValue("application/json") } } }));
        var update = await source.CheckAsync("0.17.0", architecture, default, installed);
        Assert.True(update.IsNewer);
        Assert.EndsWith(filename, update.DownloadUrl.AbsoluteUri);
        await Assert.ThrowsAsync<ShouException>(() => source.CheckAsync("0.17.0", architecture == "x64" ? "arm64" : "x64", default, installed));
        using var cancellation = new CancellationTokenSource(); cancellation.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => source.CheckAsync("0.17.0", architecture, cancellation.Token, installed));
    }
}
