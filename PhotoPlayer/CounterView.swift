import SwiftUI

struct CounterView: View {
    // This key and the standard defaults domain must survive app updates.
    @AppStorage("manualCounter.v1") private var count = 0

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("PhotoPlayer")
                    .font(.largeTitle.bold())

                Text("Build \(buildNumber)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("buildNumber")

                VStack(spacing: 8) {
                    Text("Saved counter")
                        .font(.headline)
                    Text(String(count))
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .accessibilityIdentifier("counterValue")
                }

                Button {
                    if count < Int.max {
                        count += 1
                    }
                } label: {
                    Label("Increment", systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(count == Int.max)
                .accessibilityIdentifier("incrementButton")
            }
            .frame(maxWidth: 480)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }
}
