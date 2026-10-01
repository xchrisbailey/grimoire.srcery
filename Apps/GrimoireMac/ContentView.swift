import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            List {}
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            Text("A blank page. Type / to cast a block.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 640, minHeight: 400)
    }
}

#Preview {
    ContentView()
}
