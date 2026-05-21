import PhosphorSwift

public enum FunctionalIcon: String, CaseIterable, Hashable, Sendable {
    case activity
    case appWindow
    case archive
    case arrowBendUpRight
    case arrowClockwise
    case arrowCounterClockwise
    case arrowDown
    case arrowRight
    case arrowUp
    case arrowUpRight
    case arrowsClockwise
    case arrowsDownUp
    case arrowsOut
    case battery
    case bridge
    case browser
    case buildings
    case calendar
    case caretDown
    case caretLeft
    case caretRight
    case caretUp
    case chartBar
    case chartLine
    case chat
    case check
    case checkCircle
    case checkSquare
    case checklist
    case circleDashed
    case clipboard
    case clock
    case code
    case codeBlock
    case command
    case copy
    case cpu
    case currency
    case cursorText
    case database
    case desktop
    case download
    case drop
    case ellipsisCircle
    case eye
    case eyeSlash
    case eyedropper
    case file
    case fileImage
    case fileMagnifyingGlass
    case fileText
    case filter
    case folder
    case folderGear
    case function
    case gear
    case gitBranch
    case globe
    case hardDrive
    case headphones
    case heart
    case hexagon
    case home
    case hourglass
    case image
    case key
    case lamp
    case leaf
    case lineList
    case lightbulb
    case lock
    case lockOpen
    case lockShield
    case magnifyingGlass
    case memory
    case microphone
    case minusCircle
    case monitor
    case moon
    case music
    case network
    case number
    case packageBox
    case paperPlane
    case pause
    case pauseCircle
    case person
    case play
    case placeholder
    case plus
    case plusCircle
    case plusSquare
    case power
    case puzzlePiece
    case question
    case quotes
    case record
    case rectangleStack
    case reply
    case road
    case safari
    case scope
    case sealCheck
    case shield
    case shieldCheck
    case shieldWarning
    case shoppingCart
    case sidebar
    case sliders
    case sparkle
    case speaker
    case square
    case squaresFour
    case stack
    case stop
    case storefront
    case sun
    case switcher
    case terminal
    case textBubble
    case textCursor
    case thermometer
    case timer
    case trash
    case tray
    case trayDownload
    case trophy
    case tree
    case upload
    case video
    case wand
    case warning
    case warningCircle
    case waveform
    case wifiSlash
    case wrench
    case x
    case xCircle
    case xOctagon

    public var phosphorRawValue: String {
        phosphor.rawValue
    }

    var phosphor: Ph {
        switch self {
        case .activity: .pulse
        case .appWindow: .appWindow
        case .archive: .archive
        case .arrowBendUpRight: .arrowBendUpRight
        case .arrowClockwise: .arrowClockwise
        case .arrowCounterClockwise: .arrowCounterClockwise
        case .arrowDown: .arrowDown
        case .arrowRight: .arrowRight
        case .arrowUp: .arrowUp
        case .arrowUpRight: .arrowUpRight
        case .arrowsClockwise: .arrowsClockwise
        case .arrowsDownUp: .arrowsDownUp
        case .arrowsOut: .arrowsOut
        case .battery: .batteryHigh
        case .bridge: .bridge
        case .browser, .safari: .browser
        case .buildings: .buildings
        case .calendar: .calendar
        case .caretDown: .caretDown
        case .caretLeft: .caretLeft
        case .caretRight: .caretRight
        case .caretUp: .caretUp
        case .chartBar: .chartBar
        case .chartLine: .chartLine
        case .chat, .textBubble: .chatText
        case .check: .check
        case .checkCircle: .checkCircle
        case .checkSquare: .checkSquare
        case .checklist: .listChecks
        case .circleDashed: .circleDashed
        case .clipboard: .clipboardText
        case .clock: .clock
        case .code: .code
        case .codeBlock: .codeBlock
        case .command: .command
        case .copy: .copy
        case .cpu: .cpu
        case .currency: .currencyCircleDollar
        case .cursorText, .textCursor: .cursorText
        case .database: .database
        case .desktop: .desktop
        case .download: .downloadSimple
        case .drop: .drop
        case .ellipsisCircle: .dotsThreeCircle
        case .eye: .eye
        case .eyeSlash: .eyeSlash
        case .eyedropper: .eyedropper
        case .file: .file
        case .fileImage: .fileImage
        case .fileMagnifyingGlass: .fileMagnifyingGlass
        case .fileText: .fileText
        case .filter: .funnel
        case .folder, .folderGear: .folder
        case .function: .function
        case .gear: .gearSix
        case .gitBranch: .gitBranch
        case .globe: .globe
        case .hardDrive: .hardDrive
        case .headphones: .headphones
        case .heart: .heart
        case .hexagon: .hexagon
        case .home: .house
        case .hourglass: .hourglass
        case .image: .image
        case .key: .key
        case .lamp: .lamp
        case .leaf: .leaf
        case .lineList: .list
        case .lightbulb: .lightbulb
        case .lock: .lock
        case .lockOpen: .lockOpen
        case .lockShield, .shield: .shield
        case .magnifyingGlass: .magnifyingGlass
        case .memory: .memory
        case .microphone: .microphone
        case .minusCircle: .minusCircle
        case .monitor: .monitor
        case .moon: .moonStars
        case .music: .musicNote
        case .network: .network
        case .number: .numberSquareOne
        case .packageBox: .package
        case .paperPlane: .paperPlaneTilt
        case .pause: .pause
        case .pauseCircle: .pauseCircle
        case .person: .userCircle
        case .placeholder: .placeholder
        case .play: .play
        case .plus: .plus
        case .plusCircle: .plusCircle
        case .plusSquare: .plusSquare
        case .power: .power
        case .puzzlePiece: .puzzlePiece
        case .question: .questionMark
        case .quotes: .quotes
        case .record: .record
        case .rectangleStack: .cards
        case .reply: .arrowBendUpLeft
        case .road: .roadHorizon
        case .scope: .selection
        case .sealCheck: .sealCheck
        case .shieldCheck: .shieldCheck
        case .shieldWarning: .shieldWarning
        case .shoppingCart: .shoppingCart
        case .sidebar: .sidebar
        case .sliders: .slidersHorizontal
        case .sparkle: .sparkle
        case .speaker: .speakerHigh
        case .square: .square
        case .squaresFour: .squaresFour
        case .stack: .stack
        case .stop: .stop
        case .storefront: .storefront
        case .sun: .sun
        case .switcher: .swap
        case .terminal: .terminal
        case .thermometer: .thermometer
        case .timer: .timer
        case .trash: .trash
        case .tray: .tray
        case .trayDownload: .trayArrowDown
        case .trophy: .trophy
        case .tree: .tree
        case .upload: .uploadSimple
        case .video: .videoCamera
        case .wand: .magicWand
        case .warning: .warning
        case .warningCircle: .warningCircle
        case .waveform: .waveform
        case .wifiSlash: .wifiSlash
        case .wrench: .wrench
        case .x: .x
        case .xCircle, .xOctagon: .xCircle
        }
    }
}
