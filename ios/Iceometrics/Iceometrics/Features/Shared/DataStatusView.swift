import SwiftUI

struct DataStatusView: View {
    let state: LoadState
    let origin: SnapshotOrigin?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
            Text(label)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private var label: String {
        switch state {
        case .idle:
            "Ready"
        case .loading:
            "Refreshing…"
        case .empty:
            "No games available"
        case .failed(let message):
            message
        case .loaded:
            switch origin {
            case .fixture:
                "Starter fixture data — not live"
            case .network:
                "Live data"
            case .cache:
                "Last-known-good cached data"
            case nil:
                "Loaded"
            }
        }
    }

    private var symbol: String {
        switch state {
        case .failed:
            "exclamationmark.triangle.fill"
        case .loading:
            "arrow.triangle.2.circlepath"
        case .empty:
            "tray"
        case .idle, .loaded:
            switch origin {
            case .network:
                "network"
            case .cache:
                "externaldrive"
            case .fixture, nil:
                "doc.text"
            }
        }
    }
}
