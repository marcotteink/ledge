import AppKit

enum ShelfPosition: String, CaseIterable {
    case leftTop = "left-top"
    case leftMiddle = "left-middle"
    case leftBottom = "left-bottom"
    case rightTop = "right-top"
    case rightMiddle = "right-middle"
    case rightBottom = "right-bottom"
    case mousePointer = "mouse"

    static var current: ShelfPosition {
        get {
            ShelfPosition(rawValue: UserDefaults.standard.string(forKey: "ShelfPosition") ?? "") ?? .rightMiddle
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "ShelfPosition")
        }
    }

    var title: String {
        switch self {
        case .leftTop: return "Left Edge, Top"
        case .leftMiddle: return "Left Edge, Middle"
        case .leftBottom: return "Left Edge, Bottom"
        case .rightTop: return "Right Edge, Top"
        case .rightMiddle: return "Right Edge, Middle"
        case .rightBottom: return "Right Edge, Bottom"
        case .mousePointer: return "At Mouse Pointer"
        }
    }
}

enum ShelfSize: String, CaseIterable {
    case small, medium, large

    static var current: ShelfSize {
        get {
            ShelfSize(rawValue: UserDefaults.standard.string(forKey: "ShelfSize") ?? "") ?? .medium
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "ShelfSize")
        }
    }

    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    var width: CGFloat {
        switch self {
        case .small: return 190
        case .medium: return 230
        case .large: return 284
        }
    }

    var rowHeight: CGFloat {
        switch self {
        case .small: return 46
        case .medium: return 56
        case .large: return 68
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .small: return 26
        case .medium: return 32
        case .large: return 42
        }
    }
}
