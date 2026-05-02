import SwiftUI

// MARK: - Brand Colors

extension Color {
    static let neonBlue    = Color(red: 0,     green: 0.659, blue: 1.0)   // #00A8FF
    static let appBg       = Color(red: 0.031, green: 0.051, blue: 0.086) // #080D16
    static let appCard     = Color(red: 0.059, green: 0.098, blue: 0.157) // #0F1928
    static let appInput    = Color(red: 0.086, green: 0.129, blue: 0.220) // #162138
    static let appBorder   = Color(red: 0.118, green: 0.200, blue: 0.333) // #1E3355
    static let appSecondary = Color(red: 0.580, green: 0.639, blue: 0.722) // #94A3B8
}

// MARK: - Glow

extension View {
    func neonGlow(color: Color = .neonBlue, inner: Double = 8, outer: Double = 20) -> some View {
        self
            .shadow(color: color.opacity(0.7), radius: inner)
            .shadow(color: color.opacity(0.3), radius: outer)
    }
}

// MARK: - Input Field Modifier

struct NeonInputModifier: ViewModifier {
    let focused: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.appInput)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        focused ? Color.neonBlue : Color.appBorder,
                        lineWidth: focused ? 1.5 : 1
                    )
            }
            .shadow(color: focused ? Color.neonBlue.opacity(0.25) : .clear, radius: 10)
            .animation(.easeInOut(duration: 0.2), value: focused)
    }
}

extension View {
    func neonInput(focused: Bool = false) -> some View {
        modifier(NeonInputModifier(focused: focused))
    }
}

// MARK: - Section Label

struct FormSectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(Color.appSecondary)
            .tracking(1.2)
    }
}

// MARK: - Inline Error / Warning

struct InlineMessage: View {
    let message: String
    let color: Color
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(message)
                .font(.footnote)
                .foregroundStyle(color)
            Spacer()
        }
        .padding(12)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(color.opacity(0.25), lineWidth: 1)
        }
    }
}

// MARK: - Primary Button Style

struct NeonPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.neonBlue)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: Color.neonBlue.opacity(configuration.isPressed ? 0.2 : 0.5), radius: configuration.isPressed ? 4 : 14)
            .shadow(color: Color.neonBlue.opacity(configuration.isPressed ? 0.1 : 0.2), radius: configuration.isPressed ? 8 : 28)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Secondary (Outline) Button Style

struct NeonOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .fontWeight(.medium)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.neonBlue.opacity(configuration.isPressed ? 0.15 : 0.08))
            .foregroundStyle(Color.neonBlue)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.neonBlue.opacity(0.6), lineWidth: 1.5)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
