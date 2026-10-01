import GrimoireEditor
import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Text("This grimoire is empty. Bind a folder to begin.")
                    .brandFont(.chrome)
                    .foregroundStyle(Color.brand(\.subtext))
                Label("Bind a folder", systemImage: "plus")
                    .brandFont(.chrome)
                    .foregroundStyle(Color.brand(\.overlay1))
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.brand(\.sidebar))
            .navigationSplitViewColumnWidth(min: 200, ideal: 250)
        } detail: {
            Text("A blank page. Type / to cast a block.")
                .brandFont(.body)
                .foregroundStyle(Color.brand(\.overlay1))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.brand(\.page))
        }
        .tint(Color.brand(\.magic))
        .frame(minWidth: 640, minHeight: 400)
    }
}

#Preview {
    ContentView()
}
