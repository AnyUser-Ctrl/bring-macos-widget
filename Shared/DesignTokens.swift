// tokens:start — generiert aus design/tokens.json, nicht von Hand editieren
import SwiftUI

enum DesignTokens {
    // Colors (aus Assets.xcassets, Light/Dark nativ)
    static let bg = Color("bg", bundle: .main)
    static let fg = Color("fg", bundle: .main)
    static let muted = Color("muted", bundle: .main)
    static let accent = Color("accent", bundle: .main)
    static let accentBorder = Color("accentBorder", bundle: .main)
    static let surfaceRaised = Color("surfaceRaised", bundle: .main)
    static let success = Color("success", bundle: .main)
    static let onAccent = Color("onAccent", bundle: .main)
    static let widgetSurface = Color("widgetSurface", bundle: .main)
    static let widgetSurfaceRaised = Color("widgetSurfaceRaised", bundle: .main)
    // space
    static let spaceXs: CGFloat = 4
    static let spaceSm: CGFloat = 6
    static let spaceMd: CGFloat = 12
    static let spaceLg: CGFloat = 24
    // radius
    static let radiusSm: CGFloat = 8
    static let radiusMd: CGFloat = 12
    static let radiusLg: CGFloat = 16
    // icon
    static let iconSm: CGFloat = 16
    static let iconMd: CGFloat = 20
    static let iconLg: CGFloat = 24
}
// tokens:end


