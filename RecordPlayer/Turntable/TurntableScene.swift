import AppKit
import RealityKit
import TurntableCore

enum TurntableSceneError: Error {
    case modelMissing
    case partMissing(String)
}

/// The 3D turntable: the body is loaded from `Turntable.usdz`; the record, lights, ground and camera are built in code.
/// Heights are metres above the top of the plinth.
@MainActor
final class TurntableScene {
    let root = Entity()
    let camera = PerspectiveCamera()

    /// The tonearm's swing as drawn right now. It trails the model's target.
    private(set) var currentSwing: Float

    private let geometry: TurntableGeometry
    private let theme: TurntableTheme
    private var spinning = Entity()
    private var arm = Entity()
    private var platter = PlatterMotion()
    /// 0 = needle on the record, 1 = arm raised.
    private var lift: Float = 1
    private var buttons: [TurntableControl: Entity] = [:]
    private var buttonRest: [TurntableControl: SIMD3<Float>] = [:]
    /// The record turns with the platter but is built in code, so it has its own upright frame.
    private let record = Entity()
    /// The model keeps Blender's z-up axes inside its parts; these are their orientations as loaded.
    private var spinBase = simd_quatf(angle: 0, axis: [0, 1, 0])
    private var armBase = simd_quatf(angle: 0, axis: [0, 1, 0])
    private var buttonTravel: [TurntableControl: Float] = [:]
    private var strobeLamp = Entity()
    private let strobeLight = Entity()
    private var strobeIsOn = false

    static let verticalFOV: Float = 20 * .pi / 180
    /// Half-size of what must stay in view: the turntable plus a little air.
    static let contentHalfExtent = SIMD2<Float>(0.250, 0.200)

    private enum Height {
        static let platterTop: Float = 0.022
        static let recordTop: Float = 0.024
        static let armPlaying: Float = 0.040
        static let armLift: Float = 0.010
    }

    init(geometry: TurntableGeometry, theme: TurntableTheme) async throws {
        self.geometry = geometry
        self.theme = theme
        self.currentSwing = geometry.restSwing

        buildGround()
        try await loadModel()
        try await buildRecord()
        buildLights()
        try await applyEnvironment()

        camera.camera.fieldOfViewInDegrees = Self.verticalFOV * 180 / .pi
        camera.camera.near = 0.05
        camera.camera.far = 20
        root.addChild(camera)
        place(camera: TopDownCamera(target: .zero, height: 1.6, verticalFOV: Self.verticalFOV))
        applyLightReceiver(to: root)
        setStrobe(on: false)
        poseArm()
    }

    /// Loaded entities do not reliably inherit the image-based light, so every one gets it.
    private func applyLightReceiver(to entity: Entity) {
        entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: root))
        for child in entity.children { applyLightReceiver(to: child) }
    }

    /// The camera that fits the turntable into a view, left of a column `trailingInset` points wide.
    static func camera(for size: CGSize, trailingInset: CGFloat = 0) -> TopDownCamera {
        let inset = min(trailingInset, size.width / 2)
        let height = TopDownCamera.height(
            toFit: contentHalfExtent,
            in: CGSize(width: size.width - inset, height: size.height),
            verticalFOV: verticalFOV
        )
        // Shift the view right so the turntable sits in the space left of the inset.
        let metresPerPoint = size.height > 0 ? 2 * height * tan(verticalFOV / 2) / Float(size.height) : 0
        return TopDownCamera(
            target: [Float(inset) / 2 * metresPerPoint, 0],
            height: height,
            verticalFOV: verticalFOV
        )
    }

    // MARK: Frame updates

    func place(camera top: TopDownCamera) {
        camera.look(
            at: [top.target.x, 0, top.target.y],
            from: [top.target.x, top.height, top.target.y],
            upVector: [0, 0, -1],
            relativeTo: nil
        )
    }

    func update(deltaTime: Float, model: TurntableModel) {
        let dt = min(deltaTime, 0.1)

        let follow: Float = model.isDragging ? 28 : 7
        currentSwing += (model.targetSwing - currentSwing) * (1 - exp(-dt * follow))

        let arrived = abs(model.targetSwing - currentSwing) < 0.004
        let liftTarget: Float = (model.isNeedleDown && arrived) ? 0 : 1
        lift += (liftTarget - lift) * (1 - exp(-dt * 9))
        poseArm()

        for (control, entity) in buttons {
            let target: Float = model.pressedControl == control ? 1 : 0
            let travel = (buttonTravel[control] ?? 0) + (target - (buttonTravel[control] ?? 0)) * (1 - exp(-dt * 30))
            buttonTravel[control] = travel
            if let rest = buttonRest[control] {
                entity.setPosition(rest - [0, travel * 0.002, 0], relativeTo: root)
            }
        }
        if model.wantsSpin != strobeIsOn { setStrobe(on: model.wantsSpin) }

        platter.advance(by: dt, spinning: model.wantsSpin)
        // Records turn clockwise seen from above, which is a negative rotation about +y.
        let turn = simd_quatf(angle: -platter.angle, axis: [0, 1, 0])
        spinning.setOrientation(turn * spinBase, relativeTo: root)
        record.orientation = turn
    }

    private func poseArm() {
        arm.setPosition([geometry.pivot.x, Height.armPlaying + lift * Height.armLift, geometry.pivot.y], relativeTo: root)
        let yaw = simd_quatf(angle: geometry.yaw(swing: currentSwing), axis: [0, 1, 0])
        arm.setOrientation(yaw * armBase, relativeTo: root)
    }

    // MARK: Building

    private func buildGround() {
        let ground = ModelEntity(
            mesh: .generatePlane(width: 8, depth: 8),
            materials: [material(theme.ground)]
        )
        ground.position.y = -0.02
        root.addChild(ground)
    }

    private func loadModel() async throws {
        guard let url = Bundle.main.url(forResource: "Turntable", withExtension: "usdz") else {
            throw TurntableSceneError.modelMissing
        }
        let model = try await Entity(contentsOf: url)
        root.addChild(model)

        func part(_ name: String) throws -> Entity {
            guard let entity = model.findEntity(named: name) else { throw TurntableSceneError.partMissing(name) }
            return entity
        }
        spinning = try part("Spin")
        arm = try part("Arm")
        strobeLamp = try part("StrobeLamp")
        let names: [TurntableControl: String] = [
            .startStop: "BtnStart", .previous: "BtnPrev", .next: "BtnNext",
        ]
        for (control, name) in names {
            let button = try part(name)
            buttons[control] = button
            buttonRest[control] = button.position(relativeTo: root)
        }
        spinBase = spinning.orientation(relativeTo: root)
        armBase = arm.orientation(relativeTo: root)
        record.position = [geometry.spindle.x, 0, geometry.spindle.y]
        root.addChild(record)

        strobeLight.components.set(PointLightComponent(
            color: NSColor(red: 0.25, green: 0.45, blue: 1, alpha: 1),
            intensity: theme.strobeLight,
            attenuationRadius: 0.15
        ))
        strobeLight.position = [-0.186, 0.012, 0.105]
        root.addChild(strobeLight)
    }

    private func setStrobe(on: Bool) {
        strobeIsOn = on
        strobeLight.isEnabled = on
        var lamp = PhysicallyBasedMaterial()
        let blue = NSColor(red: 0.25, green: 0.45, blue: 1, alpha: 1)
        if on {
            lamp.baseColor = .init(tint: blue)
            lamp.emissiveColor = .init(color: blue)
            lamp.emissiveIntensity = 4
        } else {
            lamp.baseColor = .init(tint: NSColor(red: 0.03, green: 0.05, blue: 0.14, alpha: 1))
            lamp.roughness = 0.3
        }
        func apply(_ entity: Entity) {
            if let model = entity as? ModelEntity {
                model.model?.materials = Array(repeating: lamp, count: max(1, model.model?.materials.count ?? 1))
            }
            entity.children.forEach(apply)
        }
        apply(strobeLamp)
    }

    private func buildRecord() async throws {
        let radius = geometry.recordRadius
        let labelRadius: Float = 0.05

        record.addChild(cylinder(radius: radius, from: Height.platterTop, to: Height.recordTop, theme.vinyl))

        let grooves = try await TextureResource(
            image: TurntableTextures.vinyl(
                base: theme.vinyl.white,
                leadInFraction: CGFloat(geometry.leadInRadius / radius),
                leadOutFraction: CGFloat(geometry.leadOutRadius / radius),
                trackStarts: [0.19, 0.37, 0.58, 0.80]
            ),
            options: .init(semantic: .color)
        )
        var vinyl = material(theme.vinyl)
        vinyl.specular = 0.15
        vinyl.baseColor = .init(tint: .white, texture: .init(grooves))
        let surface = ModelEntity(mesh: try TurntableMeshes.disc(radius: radius), materials: [vinyl])
        surface.position.y = Height.recordTop + 0.0002
        record.addChild(surface)

        let labelTexture = try await TextureResource(
            image: TurntableTextures.placeholderLabel(),
            options: .init(semantic: .color)
        )
        var paper = PhysicallyBasedMaterial()
        paper.baseColor = .init(tint: .white, texture: .init(labelTexture))
        paper.roughness = 0.7
        paper.metallic = 0.0
        paper.emissiveColor = .init(color: .white, texture: .init(labelTexture))
        paper.emissiveIntensity = theme.labelGlow
        let label = ModelEntity(mesh: try TurntableMeshes.disc(radius: labelRadius), materials: [paper])
        label.position.y = Height.recordTop + 0.0004
        record.addChild(label)

        // The light streaks do not turn with the record.
        let sheenTexture = try await TextureResource(
            image: TurntableTextures.sheen(
                strength: theme.sheen,
                innerFraction: CGFloat(labelRadius / radius),
                angle: 0.9
            ),
            options: .init(semantic: .color)
        )
        var sheen = UnlitMaterial()
        sheen.color = .init(tint: .white, texture: .init(sheenTexture))
        sheen.blending = .transparent(opacity: 1.0)
        let streaks = ModelEntity(mesh: try TurntableMeshes.disc(radius: radius), materials: [sheen])
        streaks.position = [geometry.spindle.x, Height.recordTop + 0.0006, geometry.spindle.y]
        streaks.components.set(ShadowOpt.none)
        root.addChild(streaks)
    }

    private func buildLights() {
        let key = Entity()
        key.components.set(DirectionalLightComponent(color: .white, intensity: theme.keyLight))
        key.components.set(DirectionalLightComponent.Shadow(maximumDistance: 3, depthBias: 2))
        key.look(at: .zero, from: [-0.5, 1.4, -0.45], relativeTo: nil)
        root.addChild(key)

        let spot = Entity()
        spot.components.set(SpotLightComponent(
            color: .white,
            intensity: theme.spotLight,
            innerAngleInDegrees: 18,
            outerAngleInDegrees: 46,
            attenuationRadius: 6
        ))
        spot.look(
            at: [geometry.spindle.x, 0, geometry.spindle.y],
            from: [geometry.spindle.x, 1.3, geometry.spindle.y],
            upVector: [0, 0, -1],
            relativeTo: nil
        )
        root.addChild(spot)
    }

    private func applyEnvironment() async throws {
        let environment = try await EnvironmentResource(
            equirectangular: TurntableTextures.studioEnvironment()
        )
        root.components.set(ImageBasedLightComponent(
            source: .single(environment),
            intensityExponent: log2(max(theme.environment, 0.001))
        ))
        root.components.set(ImageBasedLightReceiverComponent(imageBasedLight: root))
    }

    // MARK: Parts

    private func material(_ finish: TurntableTheme.Finish) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: NSColor(white: finish.white, alpha: 1))
        material.roughness = .init(floatLiteral: finish.roughness)
        material.metallic = .init(floatLiteral: finish.metallic)
        return material
    }

    /// An upright cylinder between two heights.
    private func cylinder(
        radius: Float, from bottom: Float, to top: Float, _ finish: TurntableTheme.Finish
    ) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateCylinder(height: top - bottom, radius: radius),
            materials: [material(finish)]
        )
        entity.position.y = (bottom + top) / 2
        return entity
    }
}

private enum ShadowOpt {
    /// Overlays that must not cast a shadow.
    static var none: DynamicLightShadowComponent { DynamicLightShadowComponent(castsShadow: false) }
}