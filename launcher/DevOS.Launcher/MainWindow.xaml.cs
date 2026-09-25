using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using DevOS.HyperV;

namespace DevOS.Launcher;

public partial class MainWindow : Window
{
    private Observation? observation;
    private bool busy;
    public MainWindow()
    {
        InitializeComponent();
        Loaded += async (_, _) => await RunAsync(async () =>
        {
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(40));
            var reply = await new PowerShellBackend().ExecuteAsync(Operation.Inspect, timeout.Token);
            if (reply.Observation?.Code == "HYPERV_QUERY_DENIED_OR_FAILED" &&
                File.Exists(ManagedPaths.Under(ManagedPaths.Install, "broker\\DevOS.Broker.exe")))
                return await BrokerClient.ExecuteAsync(Operation.Inspect);
            return reply;
        });
    }
    private async void Check_Click(object sender, RoutedEventArgs e) => await RunAsync(async () =>
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(40));
        return await new PowerShellBackend().ExecuteAsync(Operation.Inspect, timeout.Token);
    });
    private async void AdminCheck_Click(object sender, RoutedEventArgs e) => await RunAsync(() => BrokerClient.ExecuteAsync(Operation.Inspect));
    private async void Operation_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string tag } || !Enum.TryParse<Operation>(tag, out var operation)) return;
        var prompt = operation switch
        {
            Operation.Create => "Create one disposable VM and allocate a 48 GiB fixed disk? Encryption is not configured.",
            Operation.PrepareMedia => "Download Debian 13 installation media and verify its signed checksum?",
            Operation.ConnectInstallationNetwork => "Connect to ordinary NAT for installation? The guest may reach Windows and LAN services.",
            Operation.Shutdown => "Request graceful shutdown? Unsaved guest work may be lost.",
            _ => null
        };
        if (prompt != null && MessageBox.Show(this, prompt, "DevOS", MessageBoxButton.OKCancel) != MessageBoxResult.OK) return;
        await RunAsync(() => BrokerClient.ExecuteAsync(operation));
    }
    private async void Console_Click(object sender, RoutedEventArgs e)
    {
        await RunAsync(async () =>
        {
            var reply = await BrokerClient.ExecuteAsync(Operation.Inspect);
            if (!reply.Success || reply.Observation is not { Owned: true, Compliant: true } current || !Guid.TryParse(current.VmId, out var id))
                return new(false, "CONSOLE_REQUIRES_OWNED_COMPLIANT_VM", reply.Observation);
            var info = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "vmconnect.exe")) { UseShellExecute = false };
            info.ArgumentList.Add("localhost"); info.ArgumentList.Add("-G"); info.ArgumentList.Add(id.ToString());
            Process.Start(info)?.Dispose();
            return reply;
        });
    }
    private async Task RunAsync(Func<Task<BrokerReply>> operation)
    {
        if (busy) return;
        busy = true; Actions.IsEnabled = false; CheckActions.IsEnabled = false;
        Result.Text = "Operation in progress...";
        try
        {
            var reply = await operation();
            observation = reply.Observation;
            if (observation != null) Render(observation);
            else VmState.Text = EnvironmentState.ErrorUnknown.Label();
            Result.Text = Explain(reply.Success ? observation?.Code ?? reply.Code : reply.Code);
        }
        catch (Win32Exception ex) when (ex.NativeErrorCode == 1223) { Result.Text = "Administrator request cancelled. Check compatibility to refresh the VM state."; }
        catch { observation = null; VmState.Text = EnvironmentState.ErrorUnknown.Label(); Result.Text = "Operation failed or timed out. Check compatibility again; partial resources are preserved."; }
        finally { busy = false; Actions.IsEnabled = true; CheckActions.IsEnabled = true; }
    }
    private void Render(Observation o)
    {
        SystemInfo.Text = $"Windows: {o.Windows}\nHyper-V feature: {o.Feature}\nManagement module: {(o.Module ? "Available" : "Missing")}\nVMMS: {o.Vmms}\nHypervisor active: {o.HypervisorPresent}\nAvailable RAM: {o.AvailableMemoryMiB:N0} MiB\nAvailable storage: {o.AvailableStorageGiB:N0} GiB";
        VmState.Text = o.State.Label();
        VmDetails.Text = $"VM power: {o.Power} | Guest boot readiness: unknown\nNetwork: {o.Network}\nObserved: {o.ObservedAt.LocalDateTime:T}";
    }
    private static string Explain(string code) => code switch
    {
        "OK" => "",
        "BROKER_NOT_INSTALLED" => "Install the broker using scripts/Install-DevOS.ps1 before requesting administrator operations.",
        "HYPERV_MODULE_MISSING" => "Hyper-V PowerShell management module is missing. Hyper-V setup requires an explicit administrator action.",
        "VMMS_UNAVAILABLE" => "The Virtual Machine Management service is missing or not running.",
        "HYPERV_QUERY_DENIED_OR_FAILED" => "Hyper-V query could not complete. Use Check with Administrator Access.",
        "INSUFFICIENT_FREE_RAM" => "At least 5 GiB free RAM is required before creating or starting this 4 GiB VM.",
        "INSUFFICIENT_DISK_SPACE" => "At least 74 GiB free space is required for the fixed disk and host reserve.",
        "SHUTDOWN_TIMEOUT" => "Shutdown timed out. The VM may still be running; no forced power-off was performed.",
        _ => code.Replace('_', ' ')
    };
    protected override void OnClosing(CancelEventArgs e)
    {
        if (busy) { e.Cancel = true; Result.Text = "Wait for the current operation to finish before closing."; }
        base.OnClosing(e);
    }
}
