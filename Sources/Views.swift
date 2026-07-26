import ServiceManagement
import SwiftUI

struct MenuContentView: View {
    let store: UsageStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 8)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(store.services) { usage in
                    ServiceSectionView(usage: usage)
                }
            }
            Divider().padding(.vertical, 8)
            footer
        }
        .padding(14)
        .frame(width: 300)
    }

    private var header: some View {
        HStack {
            Text("AI Usage")
                .font(.headline)
            Spacer()
            if store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            } else if let updated = store.lastUpdated {
                Text(updated, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .font(.caption)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh now")
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
    }
}

struct ServiceSectionView: View {
    let usage: ServiceUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(usage.service.color)
                    .frame(width: 8, height: 8)
                Text(usage.service.rawValue)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let plan = usage.planLabel {
                    Text(plan)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }

            if let error = usage.error {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(usage.windows) { window in
                    UsageWindowRow(window: window)
                }
            }
        }
    }
}

struct UsageWindowRow: View {
    let window: UsageWindow

    private var barColor: Color {
        switch window.usedPercent {
        case 80...: return .red
        case 50..<80: return .orange
        default: return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(window.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .leading)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.quaternary)
                        Capsule()
                            .fill(barColor.gradient)
                            .frame(width: max(3, geo.size.width * min(window.usedPercent, 100) / 100))
                    }
                }
                .frame(height: 6)
                Text("\(Int(window.usedPercent.rounded()))%")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .frame(width: 34, alignment: .trailing)
            }
            HStack {
                Spacer().frame(width: 64)
                if let detail = window.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text(resetText(for: window.resetsAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
