//
//  Created by Michael Houlder on 2026-03-04.
//

import SwiftUI

/// PNG-based mascot placeholder.
/// Uses the asset: "GTMascot" (GTMascot.png in Assets.xcassets)
struct MascotHero: View {
    var height: CGFloat = 300

    var body: some View {
        Image("GTMascot")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .background(Color.clear)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

