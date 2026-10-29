using System.Text;
using System.Text.Json;

namespace Shou.Windows.Core.Tests;

public sealed class DesktopUpdateTests
{
    private static byte[] Release(string tag = "v0.18.0", string architecture = "x64", string? download = null,
        bool draft = false, bool prerelease = false, string? page = null, bool installer = false, int copies = 1) => JsonSerializer.SerializeToUtf8Bytes(new
        {
            tag_name = tag, draft, prerelease, html_url = page ?? "https://github.com/limecloud/shou/releases/tag/" + tag,
            body = "更新说明 <script>plain text</script>", assets = Enumerable.Repeat(new { name = $"Shou-{tag[1..]}-windows-{architecture}" + (installer ? "-Setup.exe" : ".zip"),
                browser_download_url = download ?? $"https://github.com/limecloud/shou/releases/download/{tag}/Shou-{tag[1..]}-windows-{architecture}" + (installer ? "-Setup.exe" : ".zip"), size = 1234 }, copies)
        });

    [Theory]
    [InlineData("0.17.0", true)]
    [InlineData("0.9.0", true)]
    [InlineData("0.18.0", false)]
    [InlineData("0.19.0", false)]
    public void ComparesStableNumericVersionsWithoutOfferingDowngrades(string current, bool newer)
    {
        var result = DesktopUpdate.Parse(Release(), current, "x64");
        Assert.Equal(newer, result.IsNewer);
        Assert.Equal("0.18.0", result.Version);
        Assert.Contains("<script>plain text</script>", result.Notes);
    }

    [Fact]
    public void SelectsOnlyTheExactArchitectureAndRepositoryAsset()
    {
        Assert.EndsWith("arm64.zip", DesktopUpdate.Parse(Release(architecture: "arm64"), "0.17.0", "arm64").DownloadUrl.AbsoluteUri);
        Assert.Throws<ShouException>(() => DesktopUpdate.Parse(Release(), "0.17.0", "arm64"));
        Assert.Throws<ShouException>(() => DesktopUpdate.Parse(Release(download: "https://evil.example/update.zip"), "0.17.0", "x64"));
        Assert.Throws<ShouException>(() => DesktopUpdate.Parse(Release(page: "https://github.com/other/shou/releases/tag/v0.18.0"), "0.17.0", "x64"));
    }

    [Theory]
    [InlineData("x64")]
    [InlineData("arm64")]
    public void InstalledAppsSelectOnlyTheirExactInstaller(string architecture)
    {
        var release = Release(architecture: architecture, installer: true);
        Assert.EndsWith($"windows-{architecture}-Setup.exe", DesktopUpdate.Parse(release, "0.17.0", architecture, installed: true).DownloadUrl.AbsoluteUri);
        Assert.Throws<ShouException>(() => DesktopUpdate.Parse(release, "0.17.0", architecture));
        Assert.Throws<ShouException>(() => DesktopUpdate.Parse(Release(architecture: architecture), "0.17.0", architecture, installed: true));
        Assert.Throws<ShouException>(() => DesktopUpdate.Parse(release, "0.17.0", architecture == "x64" ? "arm64" : "x64", installed: true));
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void RejectsDuplicateAndUntrustedDownloadsForEitherInstallation(bool installed)
    {
        Assert.Throws<ShouException>(() => DesktopUpdate.Parse(Release(installer: installed, copies: 2), "0.17.0", "x64", installed));
        Assert.Throws<ShouException>(() => DesktopUpdate.Parse(Release(installer: installed, download: "https://evil.example/update.exe"), "0.17.0", "x64", installed));
        using var trusted = JsonDocument.Parse(Release(installer: installed));
        using var untrusted = JsonDocument.Parse(Release(installer: installed, download: "https://evil.example/update.exe"));
        var release = trusted.RootElement.EnumerateObject().ToDictionary(property => property.Name, property => property.Value.Clone());
        release["assets"] = JsonSerializer.SerializeToElement(new[] { trusted.RootElement.GetProperty("assets")[0], untrusted.RootElement.GetProperty("assets")[0] });
        Assert.Throws<ShouException>(() => DesktopUpdate.Parse(JsonSerializer.SerializeToUtf8Bytes(release), "0.17.0", "x64", installed));
    }

    [Fact]
    public void RejectsPreviewMalformedOversizeAndUnsupportedMetadata()
    {
        foreach (var bytes in new[] { Release(draft: true), Release(prerelease: true), Release("v0.18.0-beta"), Release("v00.18.0"),
            Encoding.UTF8.GetBytes("{}"), new byte[DesktopUpdate.MaximumMetadataBytes + 1] })
            Assert.Throws<ShouException>(() => DesktopUpdate.Parse(bytes, "0.17.0", "x64"));
        Assert.Throws<ShouException>(() => DesktopUpdate.Parse(Release(), "development", "x64"));
        Assert.Throws<ShouException>(() => DesktopUpdate.Parse(Release(), "0.17.0", "x86"));
    }
}
