import simd
import TurntableCore

/// A physical button on the plinth.
enum TurntableControl: CaseIterable, Sendable {
    case startStop, previous, next
}

/// A camera angle the user can switch to.
enum TurntableCameraView: String, CaseIterable, Sendable {
    case top, side, tonearm

    var title: String {
        switch self {
        case .top: "Top"
        case .side: "Side"
        case .tonearm: "Tonearm"
        }
    }
}

/// Where the camera sits for one view, in terms a person can adjust: angles in degrees, sizes in metres.
struct CameraPose: Sendable, Codable, Equatable {
    /// Which side the camera looks from: 0 is the front, 90 the right, 180 the back.
    var yaw: Float
    /// How high the camera is: 0 is level with the deck, 90 straight above.
    var elevation: Float
    /// Turns the picture about the line of sight.
    var roll: Float = 0
    /// Half width and half height that stay visible around what the camera looks at.
    var halfExtent: SIMD2<Float>
    /// What the camera looks at: a point on the deck, or an offset from the needle when it follows it.
    var offset: SIMD3<Float> = .zero
    /// The view stays centred on the needle as the arm moves.
    var followsStylus = false
    /// Depth-of-field blur away from what the camera looks at, 0 for none.
    var blur: Float = 0

    var framing: CameraFraming {
        let y = yaw * .pi / 180, e = elevation * .pi / 180, r = roll * .pi / 180
        let direction = SIMD3<Float>(sin(y) * cos(e), sin(e), cos(y) * cos(e))
        // Straight "up the picture" for this direction; it stays defined when looking straight down.
        let upright = SIMD3<Float>(-sin(y) * sin(e), cos(e), -cos(y) * sin(e))
        let up = upright * cos(r) + simd_cross(direction, upright) * sin(r)
        return CameraFraming(target: offset, direction: direction, up: up, halfExtent: halfExtent)
    }
}

/// Everything that is specific to one record player model. A new deck is a model file plus one of these;
/// no other code knows which deck it is drawing.
/// Positions are metres on the table plane (x right, y toward the viewer); heights are metres above the plinth top.
struct TurntableSpec: Sendable, Identifiable {
    struct Control: Sendable {
        /// Centre on the table plane.
        var centre: SIMD2<Float>
        /// Half width and half depth.
        var halfSize: SIMD2<Float>
        /// The part in the model file that travels when the button is pressed.
        var partName: String
    }

    /// One ring of speed-check dots on the platter rim.
    struct StrobeRow: Sendable {
        /// Distance of the dots from the spindle, and their height.
        var radius: Float
        var height: Float
        /// How many dots the ring has. The ring looks frozen when one dot spacing passes per lamp flash.
        var count: Int
        var dotRadius: Float
    }

    var id: String
    var name: String
    /// The `.usdz` in the app's resources, without its extension.
    var modelFile: String
    var geometry: TurntableGeometry
    var controls: [TurntableControl: Control]

    // Parts of the model file that move or light up.
    var spinPart: String
    var armPart: String
    var strobeLampPart: String
    var strobeDotsPart: String
    var strobeLightPosition: SIMD3<Float>
    var strobeRows: [StrobeRow]
    /// Flashes of the strobe lamp per second: twice the mains frequency.
    var strobeFlashRate: Float
    /// The sloped band of the rim that carries the dots: inner and outer radius, and their heights.
    var strobeBand: (inner: SIMD2<Float>, outer: SIMD2<Float>)

    /// Height of the surface the deck stands on, below its feet.
    var groundHeight: Float
    /// Half width and half depth of the plinth, for the soft shadow under it.
    var plinthHalfSize: SIMD2<Float>
    var platterTop: Float
    var recordTop: Float
    var labelRadius: Float
    /// Height of the arm's pivot frame with the needle in the groove, and how far it rises when lifted.
    var armPlayingHeight: Float
    var armLiftTravel: Float

    /// Height at which a press is read as being on the arm, and on a button.
    var armGrabHeight: Float
    var buttonHeight: Float
    /// How close to the arm, on the table plane, a press must be to grab it.
    var armGrabDistance: Float

    var views: [TurntableCameraView: CameraPose]

    /// The button under a point on the table plane.
    func control(at point: SIMD2<Float>) -> TurntableControl? {
        TurntableControl.allCases.first { contains(point, in: $0) }
    }

    func contains(_ point: SIMD2<Float>, in control: TurntableControl) -> Bool {
        guard let shape = controls[control] else { return false }
        let offset = simd_abs(point - shape.centre)
        return offset.x <= shape.halfSize.x + 0.003 && offset.y <= shape.halfSize.y + 0.003
    }

    func pose(for view: TurntableCameraView) -> CameraPose {
        views[view] ?? views[.top] ?? CameraPose(yaw: 0, elevation: 90, halfExtent: [0.25, 0.2])
    }
}

extension TurntableSpec {
    /// Every deck the app knows. The first is the default.
    static let all: [TurntableSpec] = [.atLP140XP]

    /// Modelled on the Audio-Technica AT-LP140XP (`Models/turntable.py`), without branding.
    static let atLP140XP = TurntableSpec(
        id: "at-lp140xp",
        name: "Direct drive",
        modelFile: "Turntable",
        geometry: .standard,
        controls: [
            .startStop: Control(centre: [-0.199, 0.147], halfSize: [0.016, 0.016], partName: "BtnStart"),
            .previous: Control(centre: [-0.1585, 0.160], halfSize: [0.012, 0.006], partName: "BtnPrev"),
            .next: Control(centre: [-0.1335, 0.160], halfSize: [0.012, 0.006], partName: "BtnNext"),
        ],
        spinPart: "Spin",
        armPart: "Arm",
        strobeLampPart: "StrobeLamp",
        strobeDotsPart: "StrobeDots",
        strobeLightPosition: [-0.186, 0.012, 0.105],
        // 180 dots pass the lamp 100 times a second at exactly 33⅓ rpm; the other rows are for other speeds
        // and mains frequencies, so at 33⅓ they creep.
        strobeRows: [
            StrobeRow(radius: 0.1640, height: 0.01910, count: 180, dotRadius: 0.00135),
            StrobeRow(radius: 0.1603, height: 0.01947, count: 176, dotRadius: 0.00125),
            StrobeRow(radius: 0.1568, height: 0.01982, count: 172, dotRadius: 0.00115),
            StrobeRow(radius: 0.1535, height: 0.02015, count: 168, dotRadius: 0.00105),
        ],
        strobeFlashRate: 100,
        strobeBand: (inner: [0.1522, 0.01998], outer: [0.1653, 0.01852]),
        groundHeight: -0.090,
        plinthHalfSize: [0.226, 0.176],
        platterTop: 0.022,
        recordTop: 0.024,
        labelRadius: 0.05,
        armPlayingHeight: 0.040,
        armLiftTravel: 0.010,
        armGrabHeight: 0.035,
        buttonHeight: 0.008,
        armGrabDistance: 0.040,  // the tube bows up to 34 mm off the pivot-to-stylus line
        views: [
            .top: CameraPose(yaw: 0, elevation: 90, halfExtent: [0.230, 0.180]),
            // The product three-quarter shot (ref/AT-LP140XP/side-view.png), feet included.
            .side: CameraPose(yaw: 25, elevation: 45, halfExtent: [0.290, 0.225], offset: [0, -0.045, 0]),
            // A close-up that rides with the headshell (ref/AT-LP140XP/tonearm.png): from the right and above,
            // so the arm runs across the frame and the record falls away out of focus.
            .tonearm: CameraPose(
                yaw: 90, elevation: 54.4, halfExtent: [0.090, 0.056], offset: [0, 0.008, 0],
                followsStylus: true, blur: 1
            ),
        ]
    )
}
