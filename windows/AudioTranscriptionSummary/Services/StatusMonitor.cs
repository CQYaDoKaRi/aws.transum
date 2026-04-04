using System;
using System.Diagnostics;

namespace AudioTranscriptionSummary.Services;

public class StatusMonitor
{
    private DateTime _lastUpdateTime;
    private TimeSpan _lastProcessorTime;
    private bool _initialized;

    public double AppCpuPercent { get; private set; }
    public double SystemCpuPercent { get; private set; }
    public long AppMemoryBytes { get; private set; }
    public long TotalMemoryBytes { get; private set; }

    public void Update()
    {
        var process = Process.GetCurrentProcess();

        // App memory
        AppMemoryBytes = Environment.WorkingSet;

        // Total memory from GC info
        var gcInfo = GC.GetGCMemoryInfo();
        TotalMemoryBytes = gcInfo.TotalAvailableMemoryBytes;

        // App CPU percent
        var currentTime = DateTime.UtcNow;
        var currentProcessorTime = process.TotalProcessorTime;

        if (_initialized)
        {
            var elapsed = (currentTime - _lastUpdateTime).TotalMilliseconds;
            if (elapsed > 0)
            {
                var cpuUsed = (currentProcessorTime - _lastProcessorTime).TotalMilliseconds;
                AppCpuPercent = Math.Round(cpuUsed / (elapsed * Environment.ProcessorCount) * 100, 1);
                AppCpuPercent = Math.Clamp(AppCpuPercent, 0, 100);
            }
        }

        _lastUpdateTime = currentTime;
        _lastProcessorTime = currentProcessorTime;
        _initialized = true;

        // System CPU - approximate using process info (full system CPU requires P/Invoke or PerformanceCounter)
        SystemCpuPercent = AppCpuPercent;
    }
}
