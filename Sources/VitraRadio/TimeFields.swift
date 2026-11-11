import SwiftUI

struct TimeNumberField: View {
    @Environment(\.appPalette) private var palette
    @Binding var value: Int
    @Binding var valid: Bool
    let range: ClosedRange<Int>
    let title: String
    @State private var text: String
    @FocusState private var focused: Bool
    init(value: Binding<Int>, valid: Binding<Bool>, range: ClosedRange<Int>, title: String) {
        _value = value; _valid = valid; self.range = range; self.title = title
        _text = State(initialValue: String(format: "%02d", value.wrappedValue))
    }
    var body: some View {
        HStack(spacing: 3) {
            stepButton("minus", delta: -1)
            TextField("00", text: $text).textFieldStyle(.plain).multilineTextAlignment(.center)
                .font(.system(size: 20, weight: .medium, design: .monospaced)).frame(width: 31).focused($focused)
                .accessibilityLabel(title)
            stepButton("plus", delta: 1)
        }.padding(.horizontal, 4).padding(.vertical, 9)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(!valid ? .orange : focused ? palette.accent.opacity(0.7) : palette.line))
            .onChange(of: text) { input in
                guard !input.isEmpty, input.count <= 2, input.utf8.allSatisfy({ (48...57).contains($0) }), let number = Int(input), range.contains(number) else { valid = false; return }
                valid = true
                if value != number { value = number }
            }
            .onChange(of: value) { number in if !focused { text = String(format: "%02d", number) } }
            .onChange(of: focused) { active in if !active && valid { text = String(format: "%02d", value) } }
    }
    private func stepButton(_ symbol: String, delta: Int) -> some View {
        Button {
            let count = range.upperBound - range.lowerBound + 1
            let base = Int(text).flatMap { range.contains($0) ? $0 : nil } ?? value
            value = (base - range.lowerBound + delta + count) % count + range.lowerBound
            text = String(format: "%02d", value); valid = true
        } label: { Image(systemName: symbol).font(.system(size: 9, weight: .semibold)).foregroundStyle(palette.muted).frame(width: 23, height: 27).contentShape(Rectangle()) }
            .buttonStyle(.plain).help("\(delta < 0 ? "Diminuir" : "Aumentar") \(title.lowercased())")
    }
}
