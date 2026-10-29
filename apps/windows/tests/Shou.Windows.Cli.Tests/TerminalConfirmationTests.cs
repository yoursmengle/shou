using System.Collections.Immutable;
using System.Runtime.InteropServices;
using Shou.Windows.Cli;
using Shou.Windows.Core;
using Shou.Windows.Platform;

namespace Shou.Windows.Cli.Tests;

public sealed class TerminalConfirmationTests
{
    private static readonly string PlanId = "plan_" + new string('1', 32);
    private static CleanupReview Review(CleanupAction action = CleanupAction.Permanent) => new(PlanId, "sha256:" + new string('2', 64), action,
        DateTimeOffset.UtcNow + TimeSpan.FromMinutes(1), [new("item_" + new string('3', 32), WindowsPath.Parse("C:/Users/Dev/项目 with spaces/target"), "dev.cache", "high", 8192, 2)]);

    private static CleanupPlan Prepared()
    {
        var review = Review(); var item = review.Items[0];
        var entry = new FileEntry(item.Path, new(1, new string('4', 32), "S-1-5-21-1"), EntryKind.Directory, 0, 8192,
            DateTimeOffset.UnixEpoch, DateTimeOffset.UnixEpoch);
        return new(2, review.PlanId, [], new(), "configuration", review.Digest, DateTimeOffset.UtcNow, review.ExpiresAt,
            review.Action, [new(item.ItemId, "scan", "candidate", item.RuleId, "1.0.0", "target", item.Path,
                [entry], [], review.Digest, item.AllocatedBytes, 0, item.Risk)], review.Digest);
    }

    private static CleanupReview Review(CleanupPlan plan) => new(plan.Id, plan.Digest, plan.Action, plan.ExpiresAt,
        plan.Items.Select(item => new CleanupReviewItem(item.Id, item.Path, item.RuleId, item.Risk, item.AllocatedBytes, item.Manifest.Length)).ToImmutableArray());

    [Fact]
    public async Task BoundPlanConfirmsItsExactReview()
    {
        var plan = Prepared(); var prompts = 0;
        var confirmation = new TerminalCleanupConfirmation((_, _) => { prompts++; return Task.FromResult<string?>("PURGE " + PlanId); }, "en", plan);
        Assert.True(await confirmation.RequestAsync(Review(plan), default));
        Assert.Equal(1, prompts);
    }

    [Theory]
    [InlineData("plan")][InlineData("digest")][InlineData("action")][InlineData("expiry")]
    [InlineData("storage")][InlineData("path")][InlineData("manifest")]
    public async Task ReplacedPlanCannotReachTheTerminalPrompt(string field)
    {
        var plan = Prepared(); var review = Review(plan); var item = review.Items[0]; var prompts = 0;
        review = field switch
        {
            "plan" => review with { PlanId = "plan_" + new string('5', 32) },
            "digest" => review with { Digest = "sha256:" + new string('5', 64) },
            "action" => review with { Action = CleanupAction.Trash },
            "expiry" => review with { ExpiresAt = review.ExpiresAt.AddSeconds(1) },
            "storage" => review with { Items = [item with { RuleId = "shou.storage-selection" }] },
            "path" => review with { Items = [item with { Path = item.Path.Append("other") }] },
            _ => review with { Items = [item with { ManifestEntries = item.ManifestEntries + 1 }] }
        };
        var confirmation = new TerminalCleanupConfirmation((_, _) => { prompts++; return Task.FromResult<string?>("PURGE " + PlanId); }, "en", plan);
        Assert.Equal("plan_stale", (await Assert.ThrowsAsync<ShouException>(() => confirmation.RequestAsync(review, default))).Code);
        Assert.Equal(0, prompts);
    }

    [Theory]
    [InlineData(CleanupAction.Permanent, "PURGE ", true)]
    [InlineData(CleanupAction.Trash, "TRASH ", true)]
    [InlineData(CleanupAction.Permanent, "TRASH ", false)]
    [InlineData(CleanupAction.Trash, "PURGE ", false)]
    [InlineData(CleanupAction.Permanent, "purge ", false)]
    public async Task ConfirmationRequiresTheCurrentPlanAndExactActionPhrase(CleanupAction action, string prefix, bool expected)
    {
        string? displayed = null;
        var confirmation = new TerminalCleanupConfirmation((message, _) => { displayed = message; return Task.FromResult<string?>(prefix + PlanId); }, "en");
        Assert.Equal(expected, await confirmation.RequestAsync(Review(action), default));
        Assert.NotNull(displayed);
        Assert.Contains(PlanId, displayed);
        Assert.Contains("sha256:" + new string('2', 64), displayed);
        Assert.Contains("项目 with spaces", displayed);
        Assert.Contains("8192", displayed);
        Assert.Contains("high", displayed);
        Assert.Equal(action == CleanupAction.Permanent, displayed.Contains("Permanent deletion cannot be undone.", StringComparison.Ordinal));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("yes")]
    [InlineData("PURGE plan_old")]
    [InlineData("PURGE")]
    public async Task MissingOrUnrelatedInputDoesNotConfirm(string? response)
    {
        var confirmation = new TerminalCleanupConfirmation((_, _) => Task.FromResult(response), "en");
        Assert.False(await confirmation.RequestAsync(Review(), default));
    }

    [Fact]
    public async Task LocalePromptUsesSharedResourcesAndCannotRunTerminalEscapeSequences()
    {
        var review = Review();
        review = review with { Items = review.Items.SetItem(0, review.Items[0] with { RuleId = "test\u001b[2J" }) };
        var confirmation = new TerminalCleanupConfirmation((message, _) =>
        {
            Assert.Contains("请核对", message);
            Assert.Contains("无法撤销", message);
            Assert.DoesNotContain('\u001b', message);
            Assert.Contains("\\u001B", message);
            return Task.FromResult<string?>("PURGE " + PlanId);
        }, "zh-CN");
        Assert.True(await confirmation.RequestAsync(review, default));
    }

    [Fact]
    public async Task ACorrectPhraseCannotConfirmAfterCallerCancellation()
    {
        using var cancellation = new CancellationTokenSource();
        var confirmation = new TerminalCleanupConfirmation((_, _) =>
        {
            cancellation.Cancel();
            return Task.FromResult<string?>("PURGE " + PlanId);
        }, "en");
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => confirmation.RequestAsync(Review(), cancellation.Token));
    }

    [Fact]
    public async Task NoInteractiveTerminalDoesNotFallBackToPipedApproval()
    {
        var confirmation = new TerminalCleanupConfirmation((_, _) => throw new ShouException("confirmation_required", "fixture has no TTY"), "en");
        Assert.Equal("confirmation_required", (await Assert.ThrowsAsync<ShouException>(() => confirmation.RequestAsync(Review(), default))).Code);
    }

    [Fact]
    public async Task OversizedInputCannotSupplyConfirmation()
    {
        var confirmation = new TerminalCleanupConfirmation((_, _) => Task.FromResult<string?>("PURGE " + PlanId + new string(' ', 257)), "en");
        Assert.False(await confirmation.RequestAsync(Review(), default));
    }

    [Fact]
    public void CandidateSelectionIsExplicitRepeatedBoundedAndDoesNotSelectEverything()
    {
        var scan = "scan_" + new string('1', 32);
        var first = "candidate_" + new string('2', 32);
        var second = "candidate_" + new string('3', 32);
        var request = CommandDiscovery.Parse(["plan", "create", "--scan-id", scan, "--candidate", first, "--candidate", second, "--mode", "permanent"]);
        request.Validate();
        Assert.Equal(new[] { first, second }, request.All("candidate"));
        Assert.Equal(CleanupAction.Permanent, request.Action);
        Assert.Throws<ShouException>(() => CommandDiscovery.Parse(["plan", "create", "--scan-id", scan]));
        request = CommandDiscovery.Parse(["plan", "create", "--scan-id", scan, "--candidate", first]);
        Assert.Equal(CleanupAction.Trash, request.Action);
        var repeated = CommandDiscovery.Parse(["plan", "create", "--scan-id", scan, "--candidate", first, "--candidate", first]);
        Assert.Throws<ShouException>(() => repeated.Validate());
    }

    [Fact]
    public void DiscoveryAdvertisesOnlyNativeX64RuleCleanup()
    {
        var available = NativeWindowsSupport.IsSupported && RuntimeInformation.ProcessArchitecture == Architecture.X64;
        var spec = Assert.Single(CommandDiscovery.Matching("plan execute"));
        Assert.Equal(available, spec.Available);
        Assert.Equal(available ? null : "native_windows_x64_required", spec.UnavailableReason);
        Assert.Equal(available, CliServices.MutationAvailable);
        Assert.Equal(!CliServices.MutationAvailable, CommandDiscovery.Help("plan execute").Contains("Unavailable", StringComparison.Ordinal));
        Assert.False(CliServices.ApplicationUninstallAvailable);
        Assert.False(CliServices.StartupControlAvailable);
    }
}
