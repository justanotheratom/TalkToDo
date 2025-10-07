import SwiftUI

/// Available font choices for the app
public enum AppFont: String, CaseIterable, Codable {
    case system = "System"
    case bradley = "Bradley Hand"
    case marker = "Marker Felt"
    case snell = "Snell Roundhand"
    case noteworthy = "Noteworthy"
    case chalkduster = "Chalkduster"
    case chalkboard = "Chalkboard SE"
    case comic = "Comic Sans MS"
    case americanTypewriter = "American Typewriter"
    case brushScript = "Brush Script MT"
    case arialRounded = "Arial Rounded MT Bold"
    case sfRounded = "SF Pro Rounded"

    public var displayName: String {
        rawValue
    }

    /// SwiftUI Font with appropriate sizing
    public func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch self {
        case .system:
            return .system(size: size, weight: weight)
        case .bradley:
            return .custom("Bradley Hand", size: size)
        case .marker:
            return .custom("Marker Felt", size: size)
        case .snell:
            return .custom("Snell Roundhand", size: size)
        case .noteworthy:
            return .custom("Noteworthy", size: size)
        case .chalkduster:
            return .custom("Chalkduster", size: size)
        case .chalkboard:
            return .custom("Chalkboard SE", size: size)
        case .comic:
            return .custom("Comic Sans MS", size: size)
        case .americanTypewriter:
            return .custom("American Typewriter", size: size)
        case .brushScript:
            return .custom("Brush Script MT", size: size)
        case .arialRounded:
            return .custom("Arial Rounded MT Bold", size: size)
        case .sfRounded:
            return .custom("SF Pro Rounded", size: size)
        }
    }

    /// Default semantic fonts
    public var body: Font {
        font(size: 17)
    }

    public var subheadline: Font {
        font(size: 15)
    }

    public var caption: Font {
        font(size: 12)
    }
}

/// Global font preference storage
public class FontPreference: ObservableObject {
    @Published public var selectedFont: AppFont {
        didSet {
            UserDefaults.standard.set(selectedFont.rawValue, forKey: "selectedFont")
        }
    }

    public init() {
        if let stored = UserDefaults.standard.string(forKey: "selectedFont"),
           let font = AppFont(rawValue: stored) {
            self.selectedFont = font
        } else {
            self.selectedFont = .system
        }
    }
}

// FontPreference is an ObservableObject and should be injected via .environmentObject() modifier
// Views should access it via @EnvironmentObject property wrapper
