import Foundation
import simd

/// Supported pattern arrangement types for assembly components (BL-ASM-08, #169).
public enum AssemblyPatternType: String, Sendable, Codable, Equatable, Hashable, CaseIterable {
    case linear
    case circular
    case featureDriven
}

/// Parameters defining a linear, circular, or feature-driven assembly component pattern.
public struct AssemblyPatternParams: Sendable, Codable, Equatable, Hashable {
    public var sourceInstanceId: UUID
    public var patternType: AssemblyPatternType
    public var count: Int
    public var linearSpacing: Float
    public var linearDirection: SIMD3<Float>
    public var isSymmetric: Bool
    public var axisOrigin: SIMD3<Float>
    public var axisDirection: SIMD3<Float>
    public var totalAngle: Float
    public var isFullCircle: Bool
    public var featurePatternId: UUID?
    public var skippedIndices: Set<Int>

    public init(
        sourceInstanceId: UUID,
        patternType: AssemblyPatternType = .linear,
        count: Int = 2,
        linearSpacing: Float = 20.0,
        linearDirection: SIMD3<Float> = SIMD3<Float>(1, 0, 0),
        isSymmetric: Bool = false,
        axisOrigin: SIMD3<Float> = .zero,
        axisDirection: SIMD3<Float> = SIMD3<Float>(0, 0, 1),
        totalAngle: Float = 360.0,
        isFullCircle: Bool = true,
        featurePatternId: UUID? = nil,
        skippedIndices: Set<Int> = []
    ) {
        self.sourceInstanceId = sourceInstanceId
        self.patternType = patternType
        self.count = count
        self.linearSpacing = linearSpacing
        self.linearDirection = linearDirection
        self.isSymmetric = isSymmetric
        self.axisOrigin = axisOrigin
        self.axisDirection = axisDirection
        self.totalAngle = totalAngle
        self.isFullCircle = isFullCircle
        self.featurePatternId = featurePatternId
        self.skippedIndices = skippedIndices
    }
}

/// Orientation mode for mirrored assembly components (BL-ASM-08, #169).
public enum ComponentMirrorMode: String, Sendable, Codable, Equatable, Hashable, CaseIterable {
    case symmetricReorient
    case oppositeHand
}

/// Parameters defining an assembly component mirror operation.
public struct AssemblyMirrorParams: Sendable, Codable, Equatable, Hashable {
    public var sourceInstanceId: UUID
    public var planeNormal: SIMD3<Float>
    public var planeOrigin: SIMD3<Float>
    public var keepOriginal: Bool
    public var mirrorMode: ComponentMirrorMode
    public var planeReference: Reference?

    public init(
        sourceInstanceId: UUID,
        planeNormal: SIMD3<Float> = SIMD3<Float>(1, 0, 0),
        planeOrigin: SIMD3<Float> = .zero,
        keepOriginal: Bool = true,
        mirrorMode: ComponentMirrorMode = .symmetricReorient,
        planeReference: Reference? = nil
    ) {
        self.sourceInstanceId = sourceInstanceId
        self.planeNormal = planeNormal
        self.planeOrigin = planeOrigin
        self.keepOriginal = keepOriginal
        self.mirrorMode = mirrorMode
        self.planeReference = planeReference
    }
}

/// Identifiable record of an assembly component pattern feature (BL-ASM-08, #169).
public struct ComponentPattern: Identifiable, Sendable, Codable, Equatable, Hashable {
    public var id: UUID
    public var name: String
    public var sourceInstanceId: UUID
    public var replicaInstanceIds: [UUID]
    public var params: AssemblyPatternParams

    public init(
        id: UUID = UUID(),
        name: String,
        sourceInstanceId: UUID,
        replicaInstanceIds: [UUID] = [],
        params: AssemblyPatternParams
    ) {
        self.id = id
        self.name = name
        self.sourceInstanceId = sourceInstanceId
        self.replicaInstanceIds = replicaInstanceIds
        self.params = params
    }
}

/// Identifiable record of an assembly component mirror feature (BL-ASM-08, #169).
public struct ComponentMirror: Identifiable, Sendable, Codable, Equatable, Hashable {
    public var id: UUID
    public var name: String
    public var sourceInstanceId: UUID
    public var replicaInstanceIds: [UUID]
    public var params: AssemblyMirrorParams

    public init(
        id: UUID = UUID(),
        name: String,
        sourceInstanceId: UUID,
        replicaInstanceIds: [UUID] = [],
        params: AssemblyMirrorParams
    ) {
        self.id = id
        self.name = name
        self.sourceInstanceId = sourceInstanceId
        self.replicaInstanceIds = replicaInstanceIds
        self.params = params
    }
}
