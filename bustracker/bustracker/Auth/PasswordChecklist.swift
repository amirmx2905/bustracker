import SwiftUI

struct PasswordChecklist: View {
    let password: String
    let confirmPassword: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row(text: "At least 6 characters", satisfied: lengthOK)
            row(text: "Passwords match", satisfied: matchOK)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appInput.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.appBorder.opacity(0.7), lineWidth: 1)
        }
    }

    private var lengthOK: Bool { password.count >= 6 }
    private var matchOK: Bool { !password.isEmpty && password == confirmPassword }

    private func row(text: String, satisfied: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: satisfied ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(satisfied ? Color.neonBlue : Color.appSecondary.opacity(0.5))
            Text(text)
                .font(.footnote)
                .foregroundStyle(satisfied ? .white : Color.appSecondary)
            Spacer()
        }
    }
}
