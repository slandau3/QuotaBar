import SwiftUI

@main
struct QuotaBarApp: App {
    @State private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(store: store)
                .task {
                    await store.startAutoRefresh()
                }
        } label: {
            MenuBarIcon(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarIcon: View {
    let store: UsageStore
    @Environment(\.colorScheme) private var colorScheme

    private var trackColor: Color {
        colorScheme == .dark ? .white.opacity(0.85) : .black.opacity(0.7)
    }

    private var renderedImage: NSImage? {
        let renderer = ImageRenderer(content:
            HStack(spacing: 4) {
                ForEach(Service.allCases, id: \.self) { service in
                    RingView(percent: store.ringPercent(for: service), color: service.color, track: trackColor)
                }
            }
            .padding(.horizontal, 3)
            .frame(height: 18)
        )
        renderer.scale = 2.0
        return renderer.nsImage
    }

    var body: some View {
        if let image = renderedImage {
            Image(nsImage: image)
        } else {
            Image(systemName: "circle.grid.3x3")
        }
    }
}

struct RingView: View {
    let percent: Double?
    let color: Color
    let track: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(track, lineWidth: 2)
            if let percent {
                Circle()
                    .trim(from: 0, to: min(percent, 100) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: 13, height: 13)
    }
}
