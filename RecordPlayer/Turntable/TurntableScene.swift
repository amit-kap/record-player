import AppKit
import ImageIO
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
    private var ground = ModelEntity()
    /// The studio the deck mirrors.
    private let studio = Entity()
    /// The dimmer studio that only the table mirrors.
    private let groundStudio = Entity()
    /// The deck's body as loaded.
    private var deck = Entity()
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
    /// The speed-check dots on the platter rim, one ring per row.
    private var strobeRings: [ModelEntity] = []
    /// Seconds the scene has run, for the lamp's flashes.
    private var strobeClock: Double = 0

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
        self.label = LabelDisc(mesh: labelMesh, finish: theme.label)
        self.incomingLabel = LabelDisc(mesh: labelMesh, finish: theme.label)

        buildGround()
        try await loadModel()
        try await buildRecord()
        try buildStrobe()
        buildReflection()
        buildLights()
        try await applyEnvironment()

        camera.camera.fieldOfViewInDegrees = Self.verticalFOV * 180 / .pi
        camera.camera.near = 0.05
        camera.camera.far = 20
        root.addChild(camera)
        place(sceneCamera)
        applyLightReceiver(to: root)
        ground.components.set(ImageBasedLightReceiverComponent(imageBasedLight: groundStudio))
        setStrobe(on: false)
        poseArm()
    }

    /// Loaded entities do not reliably inherit the image-based light, so every one gets it.
    private func applyLightReceiver(to entity: Entity) {
        entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: studio))
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

    /// The strobe lamp flashes many times a second, so the dots are seen where each flash catches them. A row
    /// whose dots advance exactly one spacing per flash stands still; the other rows creep. With the lamp off the
    /// dots simply turn with the platter.
    private func poseStrobeDots(deltaTime dt: Float) {
        strobeClock += Double(dt)
        let sinceFlash = strobeIsOn
            ? Float(strobeClock.truncatingRemainder(dividingBy: 1 / Double(spec.strobeFlashRate))) : 0
        let seen = platter.angle - platter.speed * sinceFlash
        for (row, ring) in zip(spec.strobeRows, strobeRings) {
            // A ring of dots looks the same after one spacing, so only the remainder is turned.
            let spacing = 2 * Float.pi / Float(row.count)
            ring.orientation = simd_quatf(angle: -seen.truncatingRemainder(dividingBy: spacing), axis: [0, 1, 0])
        }
    }

    private func buildStrobe() throws {
        // The model's own dots are one part and cannot creep row by row, so the rows are drawn here instead.
        root.findEntity(named: spec.strobeDotsPart)?.isEnabled = false
        let band = spec.strobeBand
        let slope = (band.inner.y - band.outer.y) / (band.outer.x - band.inner.x)
        for row in spec.strobeRows {
            let ring = ModelEntity(
                mesh: try TurntableMeshes.dotRing(
                    radius: row.radius, count: row.count, dotRadius: row.dotRadius, slope: slope
                ),
                materials: [material(theme.strobeDots)]
            )
            ring.position = [geometry.spindle.x, row.height + 0.00015, geometry.spindle.y]
            ring.components.set(ShadowOpt.none)
            root.addChild(ring)
            strobeRings.append(ring)
        }
    }

    /// The table mirrors the deck. The renderer cannot reflect objects, so a copy of the body stands upside down
    /// under the table. Only the plinth's sides and feet are ever seen in it, so the copy does not move.
    private func buildReflection() {
        let copy = deck.clone(recursive: true)
        let mirror = Entity()
        mirror.scale = [1, -1, 1]
        mirror.position.y = 2 * spec.groundHeight
        mirror.addChild(copy)
        func prepare(_ entity: Entity) {
            entity.components.set(ShadowOpt.none)
            // Turning the copy upside down turns its faces inside out, so the other side of each is drawn.
            if let model = entity as? ModelEntity, let materials = model.model?.materials {
                model.model?.materials = materials.map { material in
                    guard var flipped = material as? PhysicallyBasedMaterial else { return material }
                    flipped.faceCulling = .front
                    return flipped
                }
            }
            entity.children.forEach(prepare)
        }
        prepare(mirror)
        root.addChild(mirror)
    }

    private func poseArm() {
        arm.setPosition([geometry.pivot.x, spec.armPlayingHeight + lift * spec.armLiftTravel, geometry.pivot.y], relativeTo: root)
        let yaw = simd_quatf(angle: geometry.yaw(swing: currentSwing), axis: [0, 1, 0])
        arm.setOrientation(yaw * armBase, relativeTo: root)
    }

    // MARK: Building

    private func buildGround() {
        var metal = material(theme.surface.finish)
        metal.anisotropyLevel = .init(floatLiteral: theme.surface.brushed)
        // The table is partly see-through, so the upside-down copy of the deck under it shows as a reflection.
        // A see-through metal keeps its full shine, so the lamps and the studio still mirror in it.
        metal.blending = .transparent(opacity: .init(floatLiteral: 1 - theme.surface.mirror))
        ground = ModelEntity(mesh: .generatePlane(width: 8, depth: 8), materials: [metal])
        ground.position.y = spec.groundHeight
        ground.components.set(ShadowOpt.none)
        root.addChild(ground)
    }

    private func loadModel() async throws {
        guard let url = Bundle.main.url(forResource: spec.modelFile, withExtension: "usdz") else {
            throw TurntableSceneError.modelMissing
        }
        let model = try await Entity(contentsOf: url)
        root.addChild(model)
        deck = model

        func part(_ name: String) throws -> Entity {
            guard let entity = model.findEntity(named: name) else { throw TurntableSceneError.partMissing(name) }
            return entity
        }
        spinning = try part(spec.spinPart)
        arm = try part(spec.armPart)
        strobeLamp = try part(spec.strobeLampPart)
        for (control, shape) in spec.controls {
            let button = try part(shape.partName)
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

        var edge = material(theme.vinyl)
        edge.roughness = .init(floatLiteral: theme.vinylSmooth)
        let body = ModelEntity(
            mesh: .generateCylinder(height: spec.recordTop - spec.platterTop, radius: radius), materials: [edge]
        )
        body.position.y = (spec.platterTop + spec.recordTop) / 2
        record.addChild(body)

        let leadIn = CGFloat(geometry.leadInRadius / radius)
        let leadOut = CGFloat(geometry.leadOutRadius / radius)
        let gaps = trackStarts.dropFirst().map { CGFloat($0) }
        let grooves = try await TextureResource(
            image: TurntableTextures.vinyl(
                base: theme.vinyl.white, leadInFraction: leadIn, leadOutFraction: leadOut, trackStarts: gaps
            ),
            options: .init(semantic: .color)
        )
        let roughness = try await TextureResource(
            image: TurntableTextures.vinylRoughness(
                grooves: CGFloat(theme.vinyl.roughness), smooth: CGFloat(theme.vinylSmooth),
                leadInFraction: leadIn, leadOutFraction: leadOut, trackStarts: gaps
            ),
            options: .init(semantic: .raw)
        )
        // The grooves run around the record, so they smear a lamp's reflection into a streak across them. The
        // streak comes from the lamps and the studio, so it stays put while the record turns and moves with the camera.
        var vinyl = PhysicallyBasedMaterial()
        vinyl.baseColor = .init(tint: .white, texture: .init(grooves))
        vinyl.roughness = .init(scale: 1, texture: .init(roughness))
        vinyl.metallic = 0.0
        vinyl.anisotropyLevel = .init(floatLiteral: theme.vinylStreak)
        let surface = ModelEntity(
            mesh: try TurntableMeshes.ring(inner: labelRadius * 0.9, outer: radius), materials: [vinyl]
        )
        surface.position.y = spec.recordTop + 0.0002
        record.addChild(surface)

        label.show(placeholderLabel)
        label.entity.position.y = spec.recordTop + 0.0004
        record.addChild(label.entity)
        incomingLabel.entity.position.y = spec.recordTop + 0.0005
        incomingLabel.entity.components.set(ShadowOpt.none)
        incomingLabel.entity.isEnabled = false
        record.addChild(incomingLabel.entity)
    }

    private func buildLights() {
        let target = SIMD3<Float>(0, 0, 0.02)
        // A real lamp has a size, which is what makes shadow edges soft. A spot here is a point, so the key is
        // several spots spread over the lamp's face, each with its own shadow.
        let toDeck = simd_normalize(target - theme.key.position)
        let across = simd_normalize(simd_cross(toDeck, [0, 1, 0]))
        let up = simd_cross(across, toDeck)
        let count = max(1, theme.keySamples)
        for i in 0..<count {
            var offset = SIMD3<Float>.zero
            if i > 0 {
                let angle = Float(i - 1) / Float(count - 1) * 2 * .pi
                offset = (across * cos(angle) + up * sin(angle)) * theme.keySize
            }
            var lamp = theme.key
            lamp.position += offset
            lamp.intensity /= Float(count)
            root.addChild(spot(lamp, at: target, shadow: true))
        }
        root.addChild(spot(theme.rim, at: [geometry.spindle.x, 0, geometry.spindle.y], shadow: false))
    }

    private func spot(_ lamp: TurntableTheme.Lamp, at target: SIMD3<Float>, shadow: Bool) -> Entity {
        let entity = Entity()
        entity.components.set(SpotLightComponent(
            color: NSColor(
                red: CGFloat(lamp.color.x), green: CGFloat(lamp.color.y), blue: CGFloat(lamp.color.z), alpha: 1
            ),
            intensity: lamp.intensity,
            innerAngleInDegrees: lamp.innerAngle,
            outerAngleInDegrees: lamp.outerAngle,
            attenuationRadius: 8
        ))
        if shadow { entity.components.set(SpotLightComponent.Shadow()) }
        entity.look(at: target, from: lamp.position, relativeTo: nil)
        return entity
    }

    private func applyEnvironment() async throws {
        // Read as floats, so lamps brighter than white keep their strength.
        guard let url = Bundle.main.url(forResource: theme.studio, withExtension: "hdr"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(
                  source, 0, [kCGImageSourceShouldAllowFloat: true] as CFDictionary
              ) else {
            throw TurntableSceneError.partMissing(theme.studio)
        }
        let environment = try await EnvironmentResource(
            equirectangular: TurntableTextures.turned(
                image, turn: theme.studioTurn, tilt: theme.studioTilt, lampLevel: theme.studioLampLevel
            )
        )
        func light(_ entity: Entity, strength: Float) {
            entity.components.set(ImageBasedLightComponent(
                source: .single(environment), intensityExponent: log2(max(strength, 0.001))
            ))
            root.addChild(entity)
        }
        light(studio, strength: theme.environment)
        light(groundStudio, strength: theme.environment * theme.surface.studio)
    }

    // MARK: Parts

    private func material(_ finish: TurntableTheme.Finish) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: NSColor(white: finish.white, alpha: 1))
        material.roughness = .init(floatLiteral: finish.roughness)
        material.metallic = .init(floatLiteral: finish.metallic)
        return material
    }
}

/// A record label: printed paper, lit and shadowed by the scene like everything else on the deck.
@MainActor
private final class LabelDisc {
    let entity: ModelEntity
    private let finish: TurntableTheme.Finish

    init(mesh: MeshResource, finish: TurntableTheme.Finish) {
        entity = ModelEntity(mesh: mesh)
        self.finish = finish
    }

    func show(_ texture: TextureResource) {
        var print = PhysicallyBasedMaterial()
        print.baseColor = .init(tint: NSColor(white: finish.white, alpha: 1), texture: .init(texture))
        print.roughness = .init(floatLiteral: finish.roughness)
        print.metallic = .init(floatLiteral: finish.metallic)
        entity.model?.materials = [print]
    }
}

private enum ShadowOpt {
    /// Overlays that must not cast a shadow.
    static var none: DynamicLightShadowComponent { DynamicLightShadowComponent(castsShadow: false) }
}