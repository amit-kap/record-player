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

    private let spec: TurntableSpec
    private var geometry: TurntableGeometry { spec.geometry }
    private let theme: TurntableTheme
    /// Where the gaps between tracks are drawn on the record, 0...1 between the first and last groove.
    private let trackStarts: [Float]
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
    /// The ring of strobe dots on the platter rim, and where it sat when loaded.
    private var strobeDots: Entity?
    private var strobeDotsBase = matrix_identity_float4x4
    /// How far the dots appear to have turned. Under the strobe lamp they slow to a standstill at full speed.
    private var strobeDotsAngle: Float = 0

    /// The label as printed now, and a copy just above it that fades a new one in.
    private let label: LabelDisc
    private let incomingLabel: LabelDisc
    private var incomingTexture: TextureResource
    private let placeholderLabel: TextureResource
    /// The artwork the label shows or is changing to. Nil is the placeholder.
    private var labelArtwork: Artwork?
    /// Counts label changes, so a cover that finishes loading after a newer change is dropped.
    private var labelRequest = 0
    /// 0...1 while the incoming label fades in; nil when it is not showing.
    private var labelFade: Float?
    private var incomingArtworkID: String?
    /// The id of the artwork the label shows in full, nil for the placeholder. Debug checks read it.
    private(set) var shownArtworkID: String?
    /// Label textures ready to show, by artwork id, least recently used first. A cover that could not be loaded
    /// is kept as the placeholder.
    private var labelTextures: [(id: String, texture: TextureResource)] = []
    /// Label textures being built, by artwork id.
    private var labelLoads: [String: Task<TextureResource, Never>] = [:]
    /// How many label textures are kept: the tracks around the current one and a few just played.
    private static let labelCacheSize = 5
    /// Label images are this many pixels on a side: sharp in the close-up view, with mipmaps for the spin.
    private static let labelPixels = 2048
    /// How long one label takes to fade into the next, in seconds.
    private static let labelFadeTime: Float = 0.3

    static let verticalFOV: Float = 20 * .pi / 180
    /// How long a change of view takes, in seconds.
    private static let viewChangeTime: Float = 0.9

    /// The camera as placed right now. Presses are read through it.
    private(set) var sceneCamera: SceneCamera
    private var cameraView: TurntableCameraView = .top
    private var viewSize = CGSize(width: 1280, height: 800)
    private var viewChange: (from: SceneCamera, progress: Float)?

    init(spec: TurntableSpec, theme: TurntableTheme, trackStarts: [Float]) async throws {
        self.spec = spec
        self.theme = theme
        self.trackStarts = trackStarts
        self.currentSwing = spec.geometry.restSwing
        self.sceneCamera = SceneCamera.fitting(
            spec.pose(for: .top).framing, in: CGSize(width: 1280, height: 800), verticalFOV: Self.verticalFOV
        )
        let placeholder = try await TextureResource(
            image: TurntableTextures.placeholderLabel(), options: Self.labelTextureOptions
        )
        self.placeholderLabel = placeholder
        self.incomingTexture = placeholder
        let labelMesh = try TurntableMeshes.disc(radius: spec.labelRadius)
        self.label = LabelDisc(mesh: labelMesh, glow: theme.labelGlow)
        self.incomingLabel = LabelDisc(mesh: labelMesh, glow: theme.labelGlow)

        buildGround()
        try await loadModel()
        try await buildRecord()
        buildLights()
        try await applyEnvironment()

        camera.camera.fieldOfViewInDegrees = Self.verticalFOV * 180 / .pi
        camera.camera.near = 0.05
        camera.camera.far = 20
        root.addChild(camera)
        place(sceneCamera)
        applyLightReceiver(to: root)
        setStrobe(on: false)
        poseArm()
    }

    /// Loaded entities do not reliably inherit the image-based light, so every one gets it.
    private func applyLightReceiver(to entity: Entity) {
        entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: root))
        for child in entity.children { applyLightReceiver(to: child) }
    }

    // MARK: Camera

    /// Poses the user has adjusted; they replace the deck's own for those views.
    var adjustedPoses: [TurntableCameraView: CameraPose] = [:] {
        didSet { if viewChange == nil { place(fittedCamera()) } }
    }

    private var pose: CameraPose { adjustedPoses[cameraView] ?? spec.pose(for: cameraView) }

    /// Shows a view in a window of `size`. A change of view glides there; a change of size is immediate.
    func show(_ view: TurntableCameraView, in size: CGSize, animated: Bool = true) {
        if view != cameraView {
            viewChange = animated ? (sceneCamera, 0) : nil
            cameraView = view
        }
        viewSize = size
        if viewChange == nil { place(fittedCamera()) }
    }

    /// How strongly the current view blurs what is nearer or further than its target, 0...1. It fades with a
    /// change of view.
    private(set) var blur: Float = 0
    /// Distance from the camera to what it is looking at, in metres.
    var focusDistance: Float { simd_length(sceneCamera.position - sceneCamera.target) }

    private func fittedCamera() -> SceneCamera {
        let pose = pose
        var framing = pose.framing
        if pose.followsStylus {
            let tip = geometry.stylusPosition(swing: currentSwing)
            framing.target += [tip.x, spec.recordTop + lift * spec.armLiftTravel, tip.y]
        }
        return SceneCamera.fitting(framing, in: viewSize, verticalFOV: Self.verticalFOV)
    }

    private func place(_ placed: SceneCamera) {
        sceneCamera = placed
        camera.look(at: placed.target, from: placed.position, upVector: placed.up, relativeTo: nil)
    }

    private func advanceViewChange(by dt: Float) {
        let wanted = pose.blur
        blur += (wanted - blur) * (1 - exp(-dt * 5))
        guard var change = viewChange else {
            // A view that follows the needle moves with it every frame.
            place(fittedCamera())
            return
        }
        change.progress += dt / Self.viewChangeTime
        if change.progress >= 1 {
            viewChange = nil
            place(fittedCamera())
        } else {
            viewChange = change
            let t = change.progress
            let eased = t * t * (3 - 2 * t)
            place(.interpolate(from: change.from, to: fittedCamera(), progress: eased))
        }
    }

    // MARK: Frame updates

    func update(deltaTime: Float, model: TurntableModel) {
        let dt = min(deltaTime, 0.1)

        let follow: Float = model.isDragging ? 28 : 7
        currentSwing += (model.targetSwing - currentSwing) * (1 - exp(-dt * follow))

        let arrived = abs(model.targetSwing - currentSwing) < 0.004
        let liftTarget: Float = (model.isNeedleDown && arrived) ? 0 : 1
        lift += (liftTarget - lift) * (1 - exp(-dt * 9))
        poseArm()
        advanceViewChange(by: dt)
        model.advance(needleOnRecord: model.isNeedleDown && arrived && lift < 0.15)

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
        poseStrobeDots(deltaTime: dt)
        record.orientation = turn

        let artwork = model.nowPlayingArtwork
        if artwork != labelArtwork { changeLabel(to: artwork) }
        prewarmLabels(for: model)
        advanceLabelFade(by: dt)
    }

    // MARK: Label

    private static var labelTextureOptions: TextureResource.CreateOptions {
        TextureResource.CreateOptions(semantic: .color, mipmapsMode: .allocateAndGenerateAll)
    }

    /// Fades in the new cover: at once when its texture is ready, otherwise once it has loaded.
    /// Nil fades back to the placeholder.
    private func changeLabel(to artwork: Artwork?) {
        labelArtwork = artwork
        labelRequest += 1
        let request = labelRequest
        guard let artwork else {
            fadeLabel(to: placeholderLabel, id: nil)
            return
        }
        if let ready = readyLabel(for: artwork.id) {
            fadeLabel(to: ready, artwork: artwork)
            return
        }
        let load = loadLabel(artwork)
        Task {
            let texture = await load.value
            guard request == labelRequest else { return }
            fadeLabel(to: texture, artwork: artwork)
        }
    }

    /// A cover that could not be loaded leaves the placeholder.
    private func fadeLabel(to texture: TextureResource, artwork: Artwork) {
        fadeLabel(to: texture, id: texture === placeholderLabel ? nil : artwork.id)
    }

    /// Builds label textures ahead of time, one at a time: the current track's cover, then the next and the
    /// previous one, so a track change only has to fade.
    private func prewarmLabels(for model: TurntableModel) {
        guard labelLoads.isEmpty, let tracks = model.record?.tracks else { return }
        let neighbours = [model.currentTrack + 1, model.currentTrack - 1].filter(tracks.indices.contains)
        let wanted = [model.nowPlayingArtwork] + neighbours.map { tracks[$0].artwork ?? model.record?.artwork }
        for case let artwork? in wanted where !labelTextures.contains(where: { $0.id == artwork.id }) {
            _ = loadLabel(artwork)
            return
        }
    }

    /// The ready texture for an artwork id, marked as just used.
    private func readyLabel(for id: String) -> TextureResource? {
        guard let index = labelTextures.firstIndex(where: { $0.id == id }) else { return nil }
        let entry = labelTextures.remove(at: index)
        labelTextures.append(entry)
        return entry.texture
    }

    /// Builds the label texture for a cover and keeps it, or joins the build already running for it.
    private func loadLabel(_ artwork: Artwork) -> Task<TextureResource, Never> {
        if let running = labelLoads[artwork.id] { return running }
        let task = Task {
            var texture = placeholderLabel
            if let image = await Self.labelImage(for: artwork, pixels: Self.labelPixels),
               let built = try? await TextureResource(image: image, options: Self.labelTextureOptions) {
                texture = built
            }
            labelLoads[artwork.id] = nil
            labelTextures.removeAll { $0.id == artwork.id }
            labelTextures.append((artwork.id, texture))
            if labelTextures.count > Self.labelCacheSize { labelTextures.removeFirst() }
            return texture
        }
        labelLoads[artwork.id] = task
        return task
    }

    /// Decodes and crops the cover away from the main actor.
    private nonisolated static func labelImage(for artwork: Artwork, pixels: Int) async -> CGImage? {
        guard let cover = await artwork.image(pixels: pixels) else { return nil }
        return TurntableTextures.coverLabel(cover, size: pixels)
    }

    private func fadeLabel(to texture: TextureResource, id: String?) {
        // A fade still running is cut short: its label becomes the printed one.
        if labelFade != nil {
            label.show(incomingTexture)
            shownArtworkID = incomingArtworkID
        }
        incomingLabel.show(texture)
        incomingLabel.entity.components.set(OpacityComponent(opacity: 0))
        incomingLabel.entity.isEnabled = true
        incomingTexture = texture
        incomingArtworkID = id
        labelFade = 0
    }

    private func advanceLabelFade(by dt: Float) {
        guard var fade = labelFade else { return }
        fade = min(1, fade + dt / Self.labelFadeTime)
        if fade < 1 {
            labelFade = fade
            incomingLabel.entity.components.set(OpacityComponent(opacity: fade * fade * (3 - 2 * fade)))
            return
        }
        label.show(incomingTexture)
        incomingLabel.entity.isEnabled = false
        labelFade = nil
        shownArtworkID = incomingArtworkID
    }

    /// On a real deck the strobe lamp flashes in step with the dots, so at the right speed they look frozen.
    /// The dots turn with the platter at low speed and drift to a stop as it reaches 33⅓ rpm.
    private func poseStrobeDots(deltaTime dt: Float) {
        guard let strobeDots else { return }
        let ratio = min(1, platter.speed / PlatterMotion.fullSpeed)
        strobeDotsAngle += platter.speed * dt * (1 - ratio * ratio * ratio)
        strobeDotsAngle.formTruncatingRemainder(dividingBy: 2 * .pi)
        let centre = SIMD3<Float>(geometry.spindle.x, 0, geometry.spindle.y)
        var toCentre = matrix_identity_float4x4
        toCentre.columns.3 = SIMD4<Float>(-centre, 1)
        var back = matrix_identity_float4x4
        back.columns.3 = SIMD4<Float>(centre, 1)
        let turn = simd_float4x4(simd_quatf(angle: -strobeDotsAngle, axis: [0, 1, 0]))
        strobeDots.setTransformMatrix(back * turn * toCentre * strobeDotsBase, relativeTo: root)
    }

    private func poseArm() {
        arm.setPosition([geometry.pivot.x, spec.armPlayingHeight + lift * spec.armLiftTravel, geometry.pivot.y], relativeTo: root)
        let yaw = simd_quatf(angle: geometry.yaw(swing: currentSwing), axis: [0, 1, 0])
        arm.setOrientation(yaw * armBase, relativeTo: root)
    }

    // MARK: Building

    private func buildGround() {
        let ground = ModelEntity(
            mesh: .generatePlane(width: 8, depth: 8),
            materials: [material(theme.ground)]
        )
        ground.position.y = spec.groundHeight
        root.addChild(ground)
    }

    private func loadModel() async throws {
        guard let url = Bundle.main.url(forResource: spec.modelFile, withExtension: "usdz") else {
            throw TurntableSceneError.modelMissing
        }
        let model = try await Entity(contentsOf: url)
        root.addChild(model)

        func part(_ name: String) throws -> Entity {
            guard let entity = model.findEntity(named: name) else { throw TurntableSceneError.partMissing(name) }
            return entity
        }
        spinning = try part(spec.spinPart)
        arm = try part(spec.armPart)
        strobeLamp = try part(spec.strobeLampPart)
        strobeDots = model.findEntity(named: spec.strobeDotsPart)
        for (control, shape) in spec.controls {
            let button = try part(shape.partName)
            buttons[control] = button
            buttonRest[control] = button.position(relativeTo: root)
        }
        spinBase = spinning.orientation(relativeTo: root)
        strobeDotsBase = strobeDots?.transformMatrix(relativeTo: root) ?? matrix_identity_float4x4
        armBase = arm.orientation(relativeTo: root)
        record.position = [geometry.spindle.x, 0, geometry.spindle.y]
        root.addChild(record)

        strobeLight.components.set(PointLightComponent(
            color: NSColor(red: 0.25, green: 0.45, blue: 1, alpha: 1),
            intensity: theme.strobeLight,
            attenuationRadius: 0.15
        ))
        strobeLight.position = spec.strobeLightPosition
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
        let labelRadius = spec.labelRadius

        record.addChild(cylinder(radius: radius, from: spec.platterTop, to: spec.recordTop, theme.vinyl))

        let grooves = try await TextureResource(
            image: TurntableTextures.vinyl(
                base: theme.vinyl.white,
                leadInFraction: CGFloat(geometry.leadInRadius / radius),
                leadOutFraction: CGFloat(geometry.leadOutRadius / radius),
                trackStarts: trackStarts.dropFirst().map { CGFloat($0) }
            ),
            options: .init(semantic: .color)
        )
        var vinyl = material(theme.vinyl)
        vinyl.specular = 0.15
        vinyl.baseColor = .init(tint: .white, texture: .init(grooves))
        let surface = ModelEntity(mesh: try TurntableMeshes.disc(radius: radius), materials: [vinyl])
        surface.position.y = spec.recordTop + 0.0002
        record.addChild(surface)

        label.show(placeholderLabel)
        label.entity.position.y = spec.recordTop + 0.0004
        record.addChild(label.entity)
        incomingLabel.entity.position.y = spec.recordTop + 0.0005
        incomingLabel.entity.components.set(ShadowOpt.none)
        incomingLabel.entity.isEnabled = false
        record.addChild(incomingLabel.entity)

        // The light streaks do not turn with the record.
        let sheenTexture = try await TextureResource(
            image: TurntableTextures.sheen(
                strength: theme.sheen,
                innerFraction: CGFloat(labelRadius / radius),
                // The streak lies along the line from the spindle toward the key lamp.
                angle: CGFloat(atan2(
                    theme.keyPosition.z - geometry.spindle.y, theme.keyPosition.x - geometry.spindle.x
                ))
            ),
            options: .init(semantic: .color)
        )
        var sheen = UnlitMaterial()
        sheen.color = .init(tint: .white, texture: .init(sheenTexture))
        sheen.blending = .transparent(opacity: 1.0)
        let streaks = ModelEntity(mesh: try TurntableMeshes.disc(radius: radius), materials: [sheen])
        streaks.position = [geometry.spindle.x, spec.recordTop + 0.0006, geometry.spindle.y]
        streaks.components.set(ShadowOpt.none)
        root.addChild(streaks)
    }

    private func buildLights() {
        // The key: one lamp off to the back left. Everything else is there only to keep its shadows from going black.
        let key = Entity()
        let lamp = SpotLightComponent(
            color: .white,
            intensity: theme.keyLight,
            innerAngleInDegrees: theme.keyInnerAngle,
            outerAngleInDegrees: theme.keyOuterAngle,
            attenuationRadius: 8
        )
        key.components.set(lamp)
        key.components.set(SpotLightComponent.Shadow())
        key.look(at: [0, 0, 0.02], from: theme.keyPosition, relativeTo: nil)
        root.addChild(key)

        let fill = Entity()
        fill.components.set(SpotLightComponent(
            color: .white,
            intensity: theme.fillLight,
            innerAngleInDegrees: 18,
            outerAngleInDegrees: 46,
            attenuationRadius: 6
        ))
        fill.look(
            at: [geometry.spindle.x, 0, geometry.spindle.y],
            from: [geometry.spindle.x, 1.3, geometry.spindle.y],
            upVector: [0, 0, -1],
            relativeTo: nil
        )
        root.addChild(fill)
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

/// A record label: printed paper lit by the scene, under an unlit copy that lets the print glow a little by itself,
/// so the artwork stays vivid in a dark scene.
@MainActor
private final class LabelDisc {
    let entity = Entity()
    private let paper: ModelEntity
    private let glow: ModelEntity
    /// How much of the unlit copy shows through, 0...1.
    private let glowStrength: Float

    init(mesh: MeshResource, glow strength: Float) {
        paper = ModelEntity(mesh: mesh)
        glow = ModelEntity(mesh: mesh)
        glowStrength = strength
        glow.position.y = 0.00005
        glow.components.set(ShadowOpt.none)
        entity.addChild(paper)
        entity.addChild(glow)
    }

    func show(_ texture: TextureResource) {
        var print = PhysicallyBasedMaterial()
        print.baseColor = .init(tint: .white, texture: .init(texture))
        print.roughness = 0.7
        print.metallic = 0.0
        paper.model?.materials = [print]
        var light = UnlitMaterial()
        light.color = .init(tint: .white, texture: .init(texture))
        light.blending = .transparent(opacity: .init(floatLiteral: glowStrength))
        glow.model?.materials = [light]
    }
}

private enum ShadowOpt {
    /// Overlays that must not cast a shadow.
    static var none: DynamicLightShadowComponent { DynamicLightShadowComponent(castsShadow: false) }
}