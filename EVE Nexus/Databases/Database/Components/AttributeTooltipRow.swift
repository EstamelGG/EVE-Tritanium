import SwiftUI

private struct AttributeTooltipAnchor: PreferenceKey {
    static let defaultValue: Anchor<CGPoint>? = nil

    static func reduce(value: inout Anchor<CGPoint>?, nextValue: () -> Anchor<CGPoint>?) {
        value = nextValue() ?? value
    }
}

struct AttributeTooltipTitle: View {
    let title: String
    let hasTooltip: Bool

    var body: some View {
        if hasTooltip {
            HStack(spacing: 0) {
                Text(title)
                Color.clear
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
                    .anchorPreference(key: AttributeTooltipAnchor.self, value: .center) { $0 }
            }
        } else {
            Text(title)
        }
    }
}

struct AttributeTooltipRow<Content: View>: View {
    let title: String
    let attributeID: Int?
    @ViewBuilder let content: (AttributeTooltipTitle) -> Content

    var body: some View {
        let tooltip = attributeID.flatMap { SDEMemoryStore.dogmaAttribute(for: $0)?.tooltipDescription }
        content(AttributeTooltipTitle(title: title, hasTooltip: tooltip != nil))
            // Keep the info button outside the NavigationLink used by some attribute rows.
            .overlayPreferenceValue(AttributeTooltipAnchor.self) { anchor in
                if let anchor, let tooltip {
                    GeometryReader { geometry in
                        AttributeTooltipButton(title: title, description: tooltip)
                            .position(geometry[anchor])
                    }
                }
            }
    }
}

private struct AttributeTooltipButton: View {
    let title: String
    let description: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "info.circle")
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(
            String.localizedStringWithFormat(
                NSLocalizedString("Item_Attribute_Description_Format", comment: ""),
                title
            )
        )
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                ScrollView {
                    Text(RichTextProcessor.plainText(from: description))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(NSLocalizedString("Common_Done", comment: "")) {
                            isPresented = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}
