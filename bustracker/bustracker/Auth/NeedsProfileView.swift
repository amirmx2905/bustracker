import SwiftUI

struct NeedsProfileView: View {
    var body: some View {
        ProfileEditorView(mode: .complete(defaultRole: .parent), showsSignOut: true)
    }
}
