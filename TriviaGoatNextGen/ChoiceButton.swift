import SwiftUI

struct ChoiceButton: View {
    let text: String
    let isSelected: Bool
    let isCorrect: Bool
    let isWrong: Bool
    let action: () -> Void

    private var borderColor: Color {
        if isCorrect { return .green }
        if isWrong { return .red }
        return isSelected ? .orange : Color.white.opacity(0.25)
    }

    private var backgroundColor: Color {
        if isCorrect { return Color.green.opacity(0.15) }
        if isWrong { return Color.red.opacity(0.15) }
        return isSelected ? Color.orange.opacity(0.15) : Color.black.opacity(0.25)
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(text)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // State indicator circle
                ZStack {
                    Circle()
                        .stroke(borderColor, lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected || isCorrect || isWrong {
                        Circle()
                            .fill(borderColor)
                            .frame(width: 12, height: 12)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(borderColor, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .disabled(isCorrect || isWrong)
    }

    private var accessibilityLabel: String {
        var base = text
        if isCorrect { base += ", correct" }
        else if isWrong { base += ", incorrect" }
        else if isSelected { base += ", selected" }
        return base
    }
}

#Preview("ChoiceButton States") {
    VStack(spacing: 12) {
        ChoiceButton(text: "Neutral choice", isSelected: false, isCorrect: false, isWrong: false, action: {})
        ChoiceButton(text: "Selected choice", isSelected: true, isCorrect: false, isWrong: false, action: {})
        ChoiceButton(text: "Correct choice", isSelected: false, isCorrect: true, isWrong: false, action: {})
        ChoiceButton(text: "Wrong choice", isSelected: true, isCorrect: false, isWrong: true, action: {})
    }
    .padding()
    .background(Color.black)
}
