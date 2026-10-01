import GrimoireEditor
import SwiftUI

/// Placeholder so the shared packages keep compiling for iOS (#17).
@main
struct GrimoireiOSApp: App {
    init() {
        BrandFont.register()
    }

    var body: some Scene {
        WindowGroup {
            Text("A blank page. Type / to cast a block.")
                .brandFont(.body)
                .foregroundStyle(Color.brand(\.overlay1))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.brand(\.page))
        }
    }
}
