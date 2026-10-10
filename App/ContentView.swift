import SwiftUI

struct ContentView: View {
    @State private var isAuthenticated = BringStore.shared.isAuthenticated

    var body: some View {
        Group {
            if isAuthenticated {
                ListPickerView(onLogout: { isAuthenticated = false })
            } else {
                LoginView(onLoginSuccess: { isAuthenticated = true })
            }
        }
        .padding(24)
    }
}

#Preview {
    ContentView()
}
