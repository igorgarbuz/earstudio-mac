import SwiftUI
import EarStudioAssets

public struct DeviceImage: View {
    public init() {}
    public var body: some View {
        // The same unchanged Android product photo used in the README.
        // Attribution and licensing are recorded in Docs/Provenance.md.
        Image(EarStudioAssets.productImageName, bundle: EarStudioAssets.bundle)
            .resizable()
            .scaledToFit()
            .accessibilityLabel("EarStudio ES100 product photo")
    }
}

