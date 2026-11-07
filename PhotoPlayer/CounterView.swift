import SwiftUI

struct CounterView: View {
    // This key and the standard defaults domain must survive app updates.
    @AppStorage("manualCounter.v1") private var count = 0

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "不明"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("PhotoPlayer")
                    .font(.largeTitle.bold())

                Text("ビルド \(buildNumber)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("buildNumber")

                VStack(spacing: 8) {
                    Text("保存済みカウンター")
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
                    Label("1 増やす", systemImage: "plus")
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
