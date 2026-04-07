// StatusBarView.swift
// CPU: PC全体の使用率とアプリの使用率、メモリ: 全体容量とアプリ使用量と%

import SwiftUI
import Darwin

struct StatusBarView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var appCpuUsage: Double = 0
    @State private var systemCpuUsage: Double = 0
    @State private var appMemory: UInt64 = 0
    @State private var totalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
    @State private var timer: Timer?
    @State private var recordingElapsed: TimeInterval = 0

    /// 録音中かどうか
    private var isAnyCapturing: Bool {
        viewModel.isCapturingSystemAudio || viewModel.isRecordingScreen
    }

    var body: some View {
        HStack(spacing: 16) {
            // 左寄せ: プログレスバー＋メッセージ or 録音時間
            if isAnyCapturing {
                Circle().fill(.red).frame(width: 6, height: 6)
                Text(String(format: "録音中 %02d:%02d", Int(recordingElapsed) / 60, Int(recordingElapsed) % 60))
                    .font(.caption2).monospacedDigit().foregroundStyle(.red)
            } else if let message = viewModel.statusMessage {
                if let progress = viewModel.statusProgress {
                    ProgressView(value: progress)
                        .frame(width: 120)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(message)
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "cpu").font(.caption2).foregroundStyle(.secondary)
                Text(String(format: "CPU: アプリ %.1f%% / 全体 %.0f%%", appCpuUsage, systemCpuUsage))
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                Image(systemName: "memorychip").font(.caption2).foregroundStyle(.secondary)
                let appMB = Double(appMemory) / 1_048_576
                let totalGB = Double(totalMemory) / 1_073_741_824
                let pct = totalMemory > 0 ? Double(appMemory) / Double(totalMemory) * 100 : 0
                Text(String(format: "メモリ: %.0f MB / %.1f GB (%.1f%%)", appMB, totalGB, pct))
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .onAppear { startMonitoring() }
        .onDisappear { timer?.invalidate(); timer = nil }
        .onChange(of: isAnyCapturing) { _, capturing in
            if capturing { recordingElapsed = 0 }
        }
    }

    private func startMonitoring() {
        updateStats()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in updateStats() }
        }
    }

    private func updateStats() {
        appCpuUsage = Self.getProcessCPUUsage()
        systemCpuUsage = Self.getSystemCPUUsage()
        appMemory = Self.getProcessMemoryUsage()
        if isAnyCapturing { recordingElapsed += 2.0 }
    }

    // MARK: - アプリの CPU 使用率

    static func getProcessCPUUsage() -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        guard result == KERN_SUCCESS, let threads = threadList else { return 0 }

        var totalCPU: Double = 0
        for i in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var infoCount = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
            let kr = withUnsafeMutablePointer(to: &info) { ptr in
                ptr.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) { intPtr in
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), intPtr, &infoCount)
                }
            }
            if kr == KERN_SUCCESS && info.flags & TH_FLAGS_IDLE == 0 {
                totalCPU += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
            }
        }
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_t>.size))
        return totalCPU
    }

    // MARK: - PC 全体の CPU 使用率

    static func getSystemCPUUsage() -> Double {
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0
        var numCPUs: natural_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUs, &cpuInfo, &numCPUInfo)
        guard result == KERN_SUCCESS, let info = cpuInfo else { return 0 }

        var totalUser: Int32 = 0, totalSystem: Int32 = 0, totalIdle: Int32 = 0
        for i in 0..<Int(numCPUs) {
            let offset = Int(CPU_STATE_MAX) * i
            totalUser += info[offset + Int(CPU_STATE_USER)]
            totalSystem += info[offset + Int(CPU_STATE_SYSTEM)]
            totalIdle += info[offset + Int(CPU_STATE_IDLE)]
        }
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.size))

        let total = Double(totalUser + totalSystem + totalIdle)
        return total > 0 ? Double(totalUser + totalSystem) / total * 100.0 : 0
    }

    // MARK: - アプリのメモリ使用量

    static func getProcessMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPtr, &count)
            }
        }
        return kr == KERN_SUCCESS ? info.resident_size : 0
    }
}
