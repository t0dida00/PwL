import CoreGraphics
import Foundation

/// Every Seek It scene is drawn on this fixed canvas and scaled to fit, so object
/// positions (and the art in `SeekItSceneArt`) line up on every device.
enum SeekItCanvas {
    static let width: CGFloat = 1800
    static let height: CGFloat = 800
    static let size = CGSize(width: width, height: height)
}

/// Where an object can sit in a scene.
enum SeekItSurface: Hashable {
    case shelf, table, floor, wall, sky, water
}

/// A place objects can go, in canvas points. `standing` regions are a baseline
/// (objects sit on `rect.maxY`); others are areas objects float inside.
/// `depth` shrinks objects that are farther away or higher up.
struct SeekItRegion {
    let surface: SeekItSurface
    let rect: CGRect
    var depth: CGFloat = 1
    var standing = true

    static func shelf(_ x0: CGFloat, _ x1: CGFloat, baseline: CGFloat, surface: SeekItSurface = .shelf, depth: CGFloat) -> Self {
        SeekItRegion(surface: surface, rect: CGRect(x: x0, y: baseline - 1, width: x1 - x0, height: 1), depth: depth)
    }

    static func area(_ surface: SeekItSurface, _ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, depth: CGFloat, standing: Bool = false) -> Self {
        SeekItRegion(surface: surface, rect: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0), depth: depth, standing: standing)
    }
}

/// A findable thing. `lookAlike` names another item's emoji that is easy to confuse with it.
struct SeekItItem: Hashable {
    let emoji: String
    let name: String
    let surfaces: Set<SeekItSurface>
    var lookAlike: String?

    init(_ emoji: String, _ name: String, _ surfaces: Set<SeekItSurface>, like lookAlike: String? = nil) {
        self.emoji = emoji
        self.name = name
        self.surfaces = surfaces
        self.lookAlike = lookAlike
    }
}

/// One step of the Seek It journey: a match plays all six rooms in order. Every level is
/// equally hard — 50 different objects in mixed sizes, heavily overlapped, tilted and buried
/// in mess, with look-alikes and foreground leaves / curtains — only the room changes.
struct SeekItLevel: Hashable, Codable {
    static let count = 6
    static let all = (1...count).map(SeekItLevel.init)
    /// Room for each level.
    static let rooms: [SeekItSceneID] = [.kitchen, .livingRoom, .garden, .beach, .attic, .office]
    /// Objects to find in every room.
    static let targetsPerRoom = 10
    /// Objects drawn in every room — all different, no duplicates.
    static let objectsPerRoom = 50

    let number: Int

    init(_ number: Int) {
        self.number = min(max(number, 1), Self.count)
    }

    var scene: SeekItSceneID { Self.rooms[number - 1] }
    var isLast: Bool { number == Self.count }
    var next: SeekItLevel? { isLast ? nil : SeekItLevel(number + 1) }

    var objectCount: Int { Self.objectsPerRoom }
    var targetCount: Int { Self.targetsPerRoom }
    /// Hints per player per room.
    var hints: Int { 2 }
    /// Base object size in canvas points (before region depth and spread).
    var baseSize: ClosedRange<CGFloat> { 62...84 }
    /// Each object is scaled by a random factor in this range, so sizes vary a lot —
    /// a target can be tiny next to a big decoy.
    var sizeSpread: ClosedRange<CGFloat> { 0.45...1.6 }
    var maxRotation: Double { 60 }
    /// Minimum distance between objects, as a fraction of their combined radii.
    /// Well under 1, so objects overlap — but never sit fully on top of each other.
    var spacing: CGFloat { 0.2 }
    /// Chance a new object is dropped onto an existing pile instead of a free spot.
    var pileChance: Double { 0.45 }
    /// Bits of drawn mess (papers, leaves, crumbs) laid *over* the objects.
    var frontMess: Int { 24 }
    /// Tap radius multiplier around a target.
    var tolerance: CGFloat { 1.05 }
    /// Targets are spread out: at least this far apart (canvas points), so finds are
    /// scattered over the whole room instead of bunched together.
    var targetSpacing: CGFloat { 220 }
    /// Foreground leaves / curtains partly hide objects.
    var hasOccluders: Bool { true }
}

enum SeekItSceneID: String, CaseIterable, Codable {
    case kitchen, livingRoom, attic, beach, garden, office

    var scene: SeekItScene { SeekItScene.catalog[self]! }
}

/// A themed scene: its regions and its pool of findable items. The matching art lives
/// in `SeekItSceneArt` and uses the same canvas coordinates.
struct SeekItScene {
    let id: SeekItSceneID
    let title: String
    let regions: [SeekItRegion]
    let pool: [SeekItItem]

    static let catalog: [SeekItSceneID: SeekItScene] = Dictionary(
        uniqueKeysWithValues: [kitchen, livingRoom, attic, beach, garden, office].map { ($0.id, $0) }
    )

    /// Odds and ends that fill every room up to 50 objects. Each appears at most once per
    /// room, and never if the room's own pool already has it — rooms have no duplicates.
    static let clutter: [(String, String)] = [
        ("📎", "Paper clip"), ("🧷", "Safety pin"), ("🔘", "Button"), ("🪡", "Needle"), ("🖍️", "Crayon"),
        ("✏️", "Pencil"), ("🧩", "Puzzle piece"), ("🎲", "Die"), ("🧶", "Yarn"), ("🍬", "Candy"),
        ("🔩", "Bolt"), ("⚙️", "Gear"), ("🪛", "Screwdriver"), ("🎀", "Ribbon"), ("🪶", "Feather"),
        ("🍂", "Leaves"), ("🥜", "Peanuts"), ("🧽", "Sponge"), ("🪙", "Coin"), ("📌", "Pushpin"),
        ("🔋", "Battery"), ("💾", "Floppy disk"), ("💿", "CD"), ("📼", "Tape"), ("🧮", "Abacus"),
        ("🪄", "Magic wand"), ("🎯", "Dartboard"), ("🏓", "Paddle"), ("🔔", "Bell"), ("🧱", "Brick"),
        ("🪵", "Log"), ("🧻", "Paper roll"), ("🧼", "Soap"), ("🪥", "Toothbrush"), ("🍭", "Lollipop"),
        ("🥨", "Pretzel"), ("🥯", "Bagel"), ("🧸", "Teddy bear"), ("🪀", "Yo-yo"), ("🎈", "Balloon"),
        ("🪁", "Kite"), ("🧦", "Socks"), ("🖇️", "Clips"), ("🪢", "Knot"), ("🥎", "Softball"),
        ("🏸", "Shuttlecock"), ("🪇", "Maracas"), ("🪈", "Flute"),
    ]
}

// MARK: - Scenes (coordinates match SeekItSceneArt)

extension SeekItScene {
    static let kitchen = SeekItScene(
        id: .kitchen,
        title: "Cozy Kitchen",
        regions: [
            .shelf(100, 660, baseline: 200, depth: 0.72),
            .shelf(1140, 1700, baseline: 200, depth: 0.72),
            .area(.wall, 130, 330, 660, 470, depth: 0.8),
            .area(.wall, 1140, 330, 1680, 470, depth: 0.8),
            .shelf(40, 740, baseline: 522, surface: .table, depth: 0.9),
            .shelf(1060, 1760, baseline: 522, surface: .table, depth: 0.9),
            .area(.floor, 40, 712, 1760, 792, depth: 1, standing: true),
        ],
        pool: [
            SeekItItem("🍎", "Apple", [.shelf, .table]),
            SeekItItem("🍅", "Tomato", [.shelf, .table], like: "🍎"),
            SeekItItem("🍋", "Lemon", [.shelf, .table]),
            SeekItItem("🍌", "Banana", [.shelf, .table]),
            SeekItItem("🍇", "Grapes", [.shelf, .table]),
            SeekItItem("🍓", "Strawberry", [.shelf, .table]),
            SeekItItem("🍒", "Cherries", [.shelf, .table], like: "🍓"),
            SeekItItem("🍞", "Bread", [.shelf, .table]),
            SeekItItem("🥐", "Croissant", [.shelf, .table]),
            SeekItItem("🧀", "Cheese", [.shelf, .table]),
            SeekItItem("🧈", "Butter", [.shelf, .table], like: "🧀"),
            SeekItItem("🥚", "Egg", [.shelf, .table]),
            SeekItItem("🥛", "Milk", [.shelf, .table]),
            SeekItItem("🧂", "Salt", [.shelf, .table]),
            SeekItItem("🍯", "Honey", [.shelf, .table]),
            SeekItItem("🫙", "Jar", [.shelf, .table], like: "🍯"),
            SeekItItem("🫖", "Teapot", [.shelf, .table]),
            SeekItItem("☕️", "Coffee", [.shelf, .table]),
            SeekItItem("🍵", "Green tea", [.shelf, .table], like: "☕️"),
            SeekItItem("🥕", "Carrot", [.table]),
            SeekItItem("🌶️", "Chili", [.table, .wall]),
            SeekItItem("🧄", "Garlic", [.table, .wall]),
            SeekItItem("🧅", "Onion", [.table], like: "🧄"),
            SeekItItem("🍪", "Cookie", [.shelf, .table]),
            SeekItItem("🧁", "Cupcake", [.shelf, .table]),
            SeekItItem("🥫", "Can", [.shelf]),
            SeekItItem("🍳", "Frying pan", [.wall, .table]),
            SeekItItem("🥄", "Spoon", [.wall]),
            SeekItItem("🔪", "Knife", [.wall]),
            SeekItItem("🍴", "Fork", [.wall], like: "🥄"),
            SeekItItem("🥢", "Chopsticks", [.wall]),
            SeekItItem("⏰", "Alarm clock", [.wall, .shelf]),
            SeekItItem("🧽", "Sponge", [.table]),
            SeekItItem("🧹", "Broom", [.floor]),
            SeekItItem("🪣", "Bucket", [.floor]),
            SeekItItem("🧺", "Basket", [.floor]),
            SeekItItem("🐈", "Cat", [.floor]),
            SeekItItem("🗑️", "Bin", [.floor]),
        ]
    )

    static let livingRoom = SeekItScene(
        id: .livingRoom,
        title: "Living Room",
        regions: [
            .shelf(80, 440, baseline: 200, depth: 0.68),
            .shelf(80, 440, baseline: 330, depth: 0.7),
            .shelf(80, 440, baseline: 460, depth: 0.74),
            .area(.wall, 1250, 60, 1760, 210, depth: 0.7),
            .area(.wall, 520, 70, 640, 320, depth: 0.7),
            .shelf(690, 1110, baseline: 505, surface: .table, depth: 0.82),
            .shelf(720, 1080, baseline: 640, surface: .table, depth: 0.92),
            .shelf(1310, 1730, baseline: 470, surface: .table, depth: 0.82),
            .area(.floor, 40, 700, 1760, 792, depth: 1, standing: true),
        ],
        pool: [
            SeekItItem("📚", "Books", [.shelf, .table]),
            SeekItItem("📖", "Open book", [.shelf, .table], like: "📚"),
            SeekItItem("🕯️", "Candle", [.shelf, .table]),
            SeekItItem("🪴", "Plant", [.floor, .table, .shelf]),
            SeekItItem("🖼️", "Painting", [.wall]),
            SeekItItem("⏰", "Alarm clock", [.shelf, .table]),
            SeekItItem("🕰️", "Mantel clock", [.shelf, .table], like: "⏰"),
            SeekItItem("🎮", "Controller", [.table, .floor]),
            SeekItItem("🕹️", "Joystick", [.table, .floor], like: "🎮"),
            SeekItItem("📱", "Phone", [.table, .shelf]),
            SeekItItem("☎️", "Telephone", [.table, .shelf]),
            SeekItItem("💡", "Light bulb", [.shelf, .table]),
            SeekItItem("🔦", "Flashlight", [.shelf, .table]),
            SeekItItem("🧸", "Teddy bear", [.table, .floor, .shelf]),
            SeekItItem("🎁", "Gift", [.floor, .table]),
            SeekItItem("🎈", "Balloon", [.wall]),
            SeekItItem("🧶", "Yarn", [.table, .floor]),
            SeekItItem("🪀", "Yo-yo", [.shelf, .table]),
            SeekItItem("🎲", "Die", [.table, .shelf]),
            SeekItItem("🧩", "Puzzle piece", [.table, .floor]),
            SeekItItem("♟️", "Chess pawn", [.table, .shelf]),
            SeekItItem("🎧", "Headphones", [.table, .shelf]),
            SeekItItem("📷", "Camera", [.shelf, .table]),
            SeekItItem("📻", "Radio", [.shelf, .table]),
            SeekItItem("🍿", "Popcorn", [.table]),
            SeekItItem("🍫", "Chocolate", [.table]),
            SeekItItem("🍬", "Candy", [.table, .floor], like: "🍫"),
            SeekItItem("🧦", "Socks", [.floor]),
            SeekItItem("👟", "Sneaker", [.floor]),
            SeekItItem("🐕", "Dog", [.floor]),
            SeekItItem("🪁", "Kite", [.wall]),
            SeekItItem("🎸", "Guitar", [.floor]),
            SeekItItem("🎻", "Violin", [.floor], like: "🎸"),
            SeekItItem("🌹", "Rose", [.table, .shelf]),
            SeekItItem("💐", "Bouquet", [.table, .shelf], like: "🌹"),
            SeekItItem("🔑", "Key", [.table, .shelf]),
            SeekItItem("🗝️", "Old key", [.table, .shelf], like: "🔑"),
        ]
    )

    static let attic = SeekItScene(
        id: .attic,
        title: "Grandma's Attic",
        regions: [
            .shelf(140, 580, baseline: 300, depth: 0.7),
            .shelf(140, 500, baseline: 480, surface: .table, depth: 0.82),
            .shelf(770, 1030, baseline: 420, surface: .table, depth: 0.78),
            .shelf(1270, 1630, baseline: 500, surface: .table, depth: 0.84),
            .area(.wall, 1150, 150, 1700, 380, depth: 0.72),
            .area(.wall, 620, 90, 760, 330, depth: 0.7),
            .area(.floor, 40, 690, 1760, 792, depth: 1, standing: true),
        ],
        pool: [
            SeekItItem("🕯️", "Candle", [.shelf, .table]),
            SeekItItem("🏮", "Lantern", [.shelf, .table, .wall]),
            SeekItItem("🪔", "Oil lamp", [.shelf, .table], like: "🏮"),
            SeekItItem("📦", "Box", [.floor, .table]),
            SeekItItem("🧳", "Suitcase", [.floor]),
            SeekItItem("👒", "Sun hat", [.table, .wall]),
            SeekItItem("🎩", "Top hat", [.table, .shelf], like: "👒"),
            SeekItItem("🧣", "Scarf", [.table, .wall]),
            SeekItItem("🧤", "Gloves", [.table, .shelf]),
            SeekItItem("👓", "Glasses", [.shelf, .table]),
            SeekItItem("🕶️", "Sunglasses", [.shelf, .table], like: "👓"),
            SeekItItem("📜", "Scroll", [.shelf, .table]),
            SeekItItem("🗺️", "Map", [.wall]),
            SeekItItem("🖼️", "Old photo", [.wall]),
            SeekItItem("🪞", "Mirror", [.wall]),
            SeekItItem("⌛️", "Hourglass", [.shelf, .table]),
            SeekItItem("⏳", "Sand timer", [.shelf, .table], like: "⌛️"),
            SeekItItem("🔭", "Telescope", [.floor, .table]),
            SeekItItem("🪆", "Nesting doll", [.shelf, .table]),
            SeekItItem("🧸", "Teddy bear", [.table, .floor]),
            SeekItItem("🗝️", "Old key", [.shelf, .table, .wall]),
            SeekItItem("🔒", "Padlock", [.table, .shelf]),
            SeekItItem("🕸️", "Cobweb", [.wall]),
            SeekItItem("🦇", "Bat", [.wall]),
            SeekItItem("🕷️", "Spider", [.wall], like: "🦇"),
            SeekItItem("🐁", "Mouse", [.floor]),
            SeekItItem("📻", "Old radio", [.shelf, .table]),
            SeekItItem("📷", "Camera", [.shelf, .table]),
            SeekItItem("☂️", "Umbrella", [.floor]),
            SeekItItem("👢", "Boot", [.floor]),
            SeekItItem("🧵", "Thread", [.shelf, .table]),
            SeekItItem("🎞️", "Film", [.shelf, .wall]),
            SeekItItem("💍", "Ring", [.table, .shelf]),
            SeekItItem("👑", "Crown", [.table, .shelf]),
            SeekItItem("🎻", "Violin", [.floor]),
            SeekItItem("🪀", "Yo-yo", [.shelf, .table]),
        ]
    )

    static let beach = SeekItScene(
        id: .beach,
        title: "Beach Day",
        regions: [
            .area(.sky, 80, 40, 1720, 300, depth: 0.62),
            .area(.water, 80, 405, 1720, 500, depth: 0.62),
            .area(.floor, 60, 560, 1740, 640, depth: 0.8, standing: true),
            .area(.floor, 60, 690, 1740, 792, depth: 1, standing: true),
        ],
        pool: [
            SeekItItem("🪁", "Kite", [.sky]),
            SeekItItem("🎈", "Balloon", [.sky]),
            SeekItItem("🐦", "Bird", [.sky]),
            SeekItItem("🕊️", "Dove", [.sky], like: "🐦"),
            SeekItItem("🦋", "Butterfly", [.sky]),
            SeekItItem("✈️", "Plane", [.sky]),
            SeekItItem("🚁", "Helicopter", [.sky], like: "✈️"),
            SeekItItem("🪂", "Parachute", [.sky]),
            SeekItItem("⛵️", "Sailboat", [.water]),
            SeekItItem("🚤", "Speedboat", [.water], like: "⛵️"),
            SeekItItem("🛶", "Canoe", [.water]),
            SeekItItem("🐬", "Dolphin", [.water]),
            SeekItItem("🦈", "Shark", [.water], like: "🐬"),
            SeekItItem("🐳", "Whale", [.water]),
            SeekItItem("🐠", "Tropical fish", [.water]),
            SeekItItem("🐟", "Fish", [.water], like: "🐠"),
            SeekItItem("🦆", "Duck", [.water]),
            SeekItItem("🛟", "Ring buoy", [.water, .floor]),
            SeekItItem("🐚", "Shell", [.floor]),
            SeekItItem("🦀", "Crab", [.floor]),
            SeekItItem("🦞", "Lobster", [.floor], like: "🦀"),
            SeekItItem("🪸", "Coral", [.floor]),
            SeekItItem("🏐", "Volleyball", [.floor]),
            SeekItItem("⚽️", "Football", [.floor], like: "🏐"),
            SeekItItem("🩴", "Flip-flop", [.floor]),
            SeekItItem("🕶️", "Sunglasses", [.floor]),
            SeekItItem("🧴", "Sunscreen", [.floor]),
            SeekItItem("🍉", "Watermelon", [.floor]),
            SeekItItem("🍹", "Drink", [.floor]),
            SeekItItem("🍦", "Ice cream", [.floor]),
            SeekItItem("🍧", "Shaved ice", [.floor], like: "🍦"),
            SeekItItem("🪣", "Bucket", [.floor]),
            SeekItItem("🐢", "Turtle", [.floor, .water]),
            SeekItItem("🎒", "Backpack", [.floor]),
            SeekItItem("👒", "Sun hat", [.floor]),
            SeekItItem("📷", "Camera", [.floor]),
        ]
    )

    static let garden = SeekItScene(
        id: .garden,
        title: "Secret Garden",
        regions: [
            .area(.sky, 80, 30, 1720, 180, depth: 0.6),
            .area(.wall, 80, 240, 1720, 400, depth: 0.68),
            .shelf(790, 1010, baseline: 440, surface: .table, depth: 0.74),
            .area(.floor, 60, 470, 1740, 600, depth: 0.82, standing: true),
            .area(.floor, 60, 650, 1160, 792, depth: 1, standing: true),
            .area(.table, 1230, 620, 1630, 712, depth: 0.96, standing: true),
        ],
        pool: [
            SeekItItem("🌷", "Tulip", [.floor, .wall]),
            SeekItItem("🌹", "Rose", [.floor, .wall]),
            SeekItItem("🌻", "Sunflower", [.floor]),
            SeekItItem("🌼", "Daisy", [.floor, .wall]),
            SeekItItem("🌸", "Cherry blossom", [.wall, .floor], like: "🌼"),
            SeekItItem("🍄", "Mushroom", [.floor]),
            SeekItItem("🐝", "Bee", [.sky, .wall]),
            SeekItItem("🐞", "Ladybug", [.wall, .floor]),
            SeekItItem("🦋", "Butterfly", [.sky, .wall]),
            SeekItItem("🐛", "Caterpillar", [.wall, .floor]),
            SeekItItem("🐌", "Snail", [.floor]),
            SeekItItem("🐸", "Frog", [.floor, .table]),
            SeekItItem("🐿️", "Chipmunk", [.floor]),
            SeekItItem("🦔", "Hedgehog", [.floor], like: "🐿️"),
            SeekItItem("🐇", "Rabbit", [.floor]),
            SeekItItem("🐦", "Bird", [.sky, .wall]),
            SeekItItem("🦜", "Parrot", [.wall], like: "🐦"),
            SeekItItem("🪺", "Nest", [.wall]),
            SeekItItem("🍓", "Strawberry", [.table, .floor]),
            SeekItItem("🍒", "Cherries", [.table], like: "🍓"),
            SeekItItem("🍎", "Apple", [.table, .floor]),
            SeekItItem("🍐", "Pear", [.table], like: "🍎"),
            SeekItItem("🧺", "Picnic basket", [.table, .floor]),
            SeekItItem("🫖", "Teapot", [.table]),
            SeekItItem("☕️", "Tea cup", [.table]),
            SeekItItem("🥪", "Sandwich", [.table]),
            SeekItItem("🧁", "Cupcake", [.table]),
            SeekItItem("🪴", "Flower pot", [.floor]),
            SeekItItem("🌵", "Cactus", [.floor], like: "🪴"),
            SeekItItem("🪨", "Rock", [.floor]),
            SeekItItem("🍀", "Four-leaf clover", [.floor]),
            SeekItItem("☘️", "Shamrock", [.floor], like: "🍀"),
            SeekItItem("🧤", "Gloves", [.floor, .table]),
            SeekItItem("🦆", "Duck", [.table]),
            SeekItItem("🐠", "Goldfish", [.table]),
            SeekItItem("🪣", "Watering can", [.floor]),
        ]
    )

    static let office = SeekItScene(
        id: .office,
        title: "Detective Office",
        regions: [
            .area(.wall, 150, 95, 600, 310, depth: 0.66),
            .shelf(700, 1150, baseline: 260, depth: 0.68),
            .shelf(1270, 1680, baseline: 392, depth: 0.74),
            .shelf(90, 330, baseline: 360, surface: .table, depth: 0.78),
            .shelf(470, 1330, baseline: 472, surface: .table, depth: 0.86),
            .area(.floor, 40, 712, 1760, 792, depth: 1, standing: true),
        ],
        pool: [
            SeekItItem("🔍", "Magnifier", [.table, .shelf]),
            SeekItItem("🔎", "Right magnifier", [.table, .shelf], like: "🔍"),
            SeekItItem("🔑", "Key", [.table, .shelf]),
            SeekItItem("🗝️", "Old key", [.table, .shelf], like: "🔑"),
            SeekItItem("📁", "Folder", [.table, .shelf]),
            SeekItItem("📂", "Open folder", [.table, .shelf], like: "📁"),
            SeekItItem("🖋️", "Fountain pen", [.table]),
            SeekItItem("✒️", "Nib", [.table], like: "🖋️"),
            SeekItItem("📝", "Notes", [.wall, .table]),
            SeekItItem("📰", "Newspaper", [.table, .floor]),
            SeekItItem("📷", "Camera", [.table, .shelf]),
            SeekItItem("☎️", "Telephone", [.table]),
            SeekItItem("🕵️", "Detective", [.wall]),
            SeekItItem("👣", "Footprints", [.floor]),
            SeekItItem("🧪", "Test tube", [.shelf, .table]),
            SeekItItem("💊", "Pill", [.table, .shelf]),
            SeekItItem("🔦", "Flashlight", [.table, .shelf]),
            SeekItItem("💼", "Briefcase", [.floor]),
            SeekItItem("🎩", "Hat", [.shelf, .table]),
            SeekItItem("🧥", "Coat", [.floor]),
            SeekItItem("🧤", "Gloves", [.table, .shelf]),
            SeekItItem("🕰️", "Clock", [.shelf]),
            SeekItItem("🗺️", "Map", [.wall]),
            SeekItItem("📌", "Pushpin", [.wall]),
            SeekItItem("🖼️", "Photo", [.wall]),
            SeekItItem("💡", "Light bulb", [.shelf, .table]),
            SeekItItem("🧾", "Receipt", [.wall, .table]),
            SeekItItem("✉️", "Envelope", [.table, .wall]),
            SeekItItem("🍩", "Donut", [.table]),
            SeekItItem("☕️", "Coffee", [.table, .shelf]),
            SeekItItem("💍", "Ring", [.table, .shelf]),
            SeekItItem("💎", "Gem", [.table, .shelf], like: "💍"),
            SeekItItem("🧲", "Magnet", [.table, .shelf]),
            SeekItItem("🐈‍⬛", "Black cat", [.floor]),
            SeekItItem("⌚️", "Watch", [.table, .shelf]),
            SeekItItem("🪴", "Plant", [.floor, .shelf]),
        ]
    )
}

// MARK: - Layout

/// One object drawn in the scene. `id` is its index in the layout.
struct SeekItPlacement: Hashable {
    let id: Int
    let emoji: String
    let name: String
    /// Center, in canvas points.
    let center: CGPoint
    /// Glyph size, in canvas points.
    let size: CGFloat
    let rotation: Double
    let isTarget: Bool
    /// Sits on a surface (gets a contact shadow) rather than floating / hanging.
    let standing: Bool
}

struct SeekItLayout {
    /// Back-to-front drawing order (sorted by depth on screen).
    let placements: [SeekItPlacement]
    /// Target ids in list order.
    let targets: [Int]

    func placement(_ id: Int) -> SeekItPlacement? {
        placements.first { $0.id == id }
    }

    /// Builds the same room on every device for the same seed: themed items on the
    /// surfaces they belong to, then targets, then decoys and look-alikes per level.
    static func make(scene: SeekItScene, level: SeekItLevel, using rng: inout some RandomNumberGenerator) -> SeekItLayout {
        var placed: [(item: SeekItItem, isClutter: Bool, center: CGPoint, size: CGFloat, rotation: Double, standing: Bool, region: Int)] = []

        func tryPlace(_ item: SeekItItem, clutter: Bool) -> Bool {
            let regionIndices = scene.regions.indices.filter { item.surfaces.contains(scene.regions[$0].surface) }
            guard !regionIndices.isEmpty else { return false }
            for _ in 0..<80 {
                // Mostly drop onto an existing pile on an allowed surface, so things heap up.
                let piles = placed.filter { regionIndices.contains($0.region) }
                let pile = Double.random(in: 0..<1, using: &rng) < level.pileChance ? piles.randomElement(using: &rng) : nil
                let regionIndex = pile?.region ?? regionIndices.randomElement(using: &rng)!
                let region = scene.regions[regionIndex]
                var size = CGFloat.random(in: level.baseSize, using: &rng) * region.depth
                    * CGFloat.random(in: level.sizeSpread, using: &rng)
                if clutter { size *= 0.85 }
                var x = CGFloat.random(in: region.rect.minX...region.rect.maxX, using: &rng)
                var y: CGFloat
                if region.standing {
                    let baseline = region.rect.height > 2
                        ? CGFloat.random(in: region.rect.minY...region.rect.maxY, using: &rng)
                        : region.rect.maxY
                    y = baseline - size * 0.45
                } else {
                    y = CGFloat.random(in: region.rect.minY...region.rect.maxY, using: &rng)
                }
                if let pile {
                    // Next to / leaning on the pile: overlapping by up to about half.
                    let side: CGFloat = Bool.random(using: &rng) ? 1 : -1
                    x = pile.center.x + side * CGFloat.random(in: 0.35...0.7, using: &rng) * (pile.size + size) / 2
                    x = min(region.rect.maxX, max(region.rect.minX, x))
                    if region.standing {
                        // Piles stay on the surface (never climb), leaning up a little.
                        let bottom = region.rect.height > 2 ? min(region.rect.maxY, pile.center.y + pile.size * 0.45) : region.rect.maxY
                        y = bottom - size * CGFloat.random(in: 0.45...0.62, using: &rng)
                    } else {
                        y = pile.center.y + CGFloat.random(in: -0.4...0.4, using: &rng) * pile.size
                    }
                }
                let center = CGPoint(x: x, y: y)
                let fits = placed.allSatisfy { other in
                    hypot(other.center.x - center.x, other.center.y - center.y) >= (other.size + size) / 2 * level.spacing
                }
                guard fits else { continue }
                let rotation = Double.random(in: -level.maxRotation...level.maxRotation, using: &rng)
                placed.append((item, clutter, center, size, rotation, region.standing, regionIndex))
                return true
            }
            return false
        }

        // 1. Themed items, in a shuffled order, until the scene is full or the pool runs out.
        let themed = scene.pool.shuffled(using: &rng)
        for item in themed where placed.count < level.objectCount {
            _ = tryPlace(item, clutter: false)
        }

        // 2. Odds-and-ends decoys fill the room up to 50: each emoji at most once, and never
        //    one the room already has — rooms have no duplicates. They only lie on things.
        let present = Set(placed.map(\.item.emoji))
        let clutterSurfaces = Set(scene.regions.map(\.surface)).intersection([.shelf, .table, .floor])
        for (emoji, name) in SeekItScene.clutter.filter({ !present.contains($0.0) }).shuffled(using: &rng) where placed.count < level.objectCount {
            _ = tryPlace(SeekItItem(emoji, name, clutterSurfaces), clutter: true)
        }

        // 3. Targets, spread out over the whole room: each pick is random among objects at
        //    least `targetSpacing` from every target so far; if none are left, the farthest
        //    one is taken.
        var targetIndices: [Int] = []
        if let first = placed.indices.randomElement(using: &rng) { targetIndices.append(first) }
        while targetIndices.count < min(level.targetCount, placed.count) {
            let scored = placed.indices.filter { !targetIndices.contains($0) }.map { index in
                (index, targetIndices.map { hypot(placed[$0].center.x - placed[index].center.x, placed[$0].center.y - placed[index].center.y) }.min() ?? .infinity)
            }
            let farEnough = scored.filter { $0.1 >= level.targetSpacing }
            guard let pick = farEnough.randomElement(using: &rng) ?? scored.max(by: { $0.1 < $1.1 }) else { break }
            targetIndices.append(pick.0)
        }

        let placements = placed.enumerated().map { index, entry in
            SeekItPlacement(
                id: index,
                emoji: entry.item.emoji,
                name: entry.item.name,
                center: entry.center,
                size: entry.size,
                rotation: entry.rotation,
                isTarget: targetIndices.contains(index),
                standing: entry.standing
            )
        }
        // Lower on screen = closer = drawn later.
        let ordered = placements.sorted { ($0.center.y + $0.size / 2, $0.id) < ($1.center.y + $1.size / 2, $1.id) }
        return SeekItLayout(placements: ordered, targets: targetIndices)
    }
}
