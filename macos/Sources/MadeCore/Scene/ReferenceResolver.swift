import Foundation

/// Specific reasons why resolving a feature input reference may fail (ADR-D2, ADR-D3).
public enum ReferenceResolutionError: Error, Sendable, Codable, Equatable, CustomStringConvertible {
    case targetFeatureNotFound(UUID)
    case targetFeatureSuppressed(UUID)
    case forwardReference(referencedFeatureId: UUID, currentFeatureId: UUID)
    case selfReference(UUID)
    case targetNotASketch(UUID)
    case sketchEntityNotFound(featureId: UUID, entityId: UUID)
    case bodyNotFound(SolidId)
    case topologicalSourceFeatureNotFound(UUID)
    case topologicalSourceFeatureSuppressed(UUID)
    case topologicalElementMissing(TopologicalReference)
    case typeMismatch(expected: String, actual: String)
    case missingTargetBody(featureId: UUID, operation: BodyOperation)
    case componentNotFound(UUID)

    public var description: String {
        switch self {
        case .targetFeatureNotFound(let id):
            return "Target feature '\(id.uuidString)' not found in document"
        case .targetFeatureSuppressed(let id):
            return "Target feature '\(id.uuidString)' is suppressed"
        case .forwardReference(let refId, let curId):
            return "Forward reference: feature '\(curId.uuidString)' cannot reference downstream feature '\(refId.uuidString)'"
        case .selfReference(let id):
            return "Self reference: feature '\(id.uuidString)' cannot reference itself"
        case .targetNotASketch(let id):
            return "Target feature '\(id.uuidString)' is not a sketch operation"
        case .sketchEntityNotFound(let featId, let entId):
            return "Sketch entity '\(entId.uuidString)' not found in sketch feature '\(featId.uuidString)'"
        case .bodyNotFound(let solidId):
            return "Solid body '\(solidId.rawValue)' not found in document"
        case .topologicalSourceFeatureNotFound(let id):
            return "Topological source feature '\(id.uuidString)' not found in document"
        case .topologicalSourceFeatureSuppressed(let id):
            return "Topological source feature '\(id.uuidString)' is suppressed"
        case .topologicalElementMissing(let ref):
            return "Topological element '\(ref.id.uuidString)' not found on source feature '\(ref.sourceFeatureId.uuidString)'"
        case .typeMismatch(let expected, let actual):
            return "Reference type mismatch: expected \(expected) but got \(actual)"
        case .missingTargetBody(let featureId, let operation):
            return "Feature '\(featureId)' with operation '\(operation.rawValue)' must specify a targetBodyId"
        case .componentNotFound(let id):
            return "Component instance '\(id.uuidString)' not found in assembly"
        }
    }
}

/// Resolved target entity in the active document model.
public enum ResolvedTarget: Sendable, Equatable {
    case feature(Feature)
    case sketchEntity(feature: Feature, entity: SketchEntity)
    case body(solidId: SolidId, feature: Feature?)
    case face(sourceFeature: Feature, reference: TopologicalReference)
    case edge(sourceFeature: Feature, reference: TopologicalReference)
    case vertex(sourceFeature: Feature, reference: TopologicalReference)
    case component(ComponentInstance)
}

/// Resolved pair of a reference query and its target entity.
public struct ResolvedReference: Sendable, Equatable {
    public var reference: Reference
    public var target: ResolvedTarget

    public init(reference: Reference, target: ResolvedTarget) {
        self.reference = reference
        self.target = target
    }
}

/// Engine-neutral resolver validating feature input references against the document timeline (ADR-D2, Invariant 4).
@MainActor
public enum ReferenceResolver {
    /// Resolves an input reference in the context of the referencing feature and document history.
    public static func resolve(
        reference: Reference,
        for referencingFeature: Feature?,
        in document: DocumentModel
    ) -> Result<ResolvedReference, ReferenceResolutionError> {
        let refIndex = referencingFeature.flatMap { feat in
            document.features.firstIndex(where: { $0.id == feat.id })
        }

        switch reference.target {
        case .feature(let targetId):
            if let referencingFeature, referencingFeature.id == targetId {
                return .failure(.selfReference(targetId))
            }
            guard let targetIndex = document.features.firstIndex(where: { $0.id == targetId }) else {
                return .failure(.targetFeatureNotFound(targetId))
            }
            if let refIndex, targetIndex > refIndex, let referencingFeature {
                return .failure(.forwardReference(referencedFeatureId: targetId, currentFeatureId: referencingFeature.id))
            }
            let targetFeature = document.features[targetIndex]
            if targetFeature.isSuppressed {
                return .failure(.targetFeatureSuppressed(targetId))
            }
            return .success(ResolvedReference(reference: reference, target: .feature(targetFeature)))

        case .sketchEntity(let featureId, let entityId):
            if let referencingFeature, referencingFeature.id == featureId {
                return .failure(.selfReference(featureId))
            }
            guard let targetIndex = document.features.firstIndex(where: { $0.id == featureId }) else {
                return .failure(.targetFeatureNotFound(featureId))
            }
            if let refIndex, targetIndex > refIndex, let referencingFeature {
                return .failure(.forwardReference(referencedFeatureId: featureId, currentFeatureId: referencingFeature.id))
            }
            let targetFeature = document.features[targetIndex]
            if targetFeature.isSuppressed {
                return .failure(.targetFeatureSuppressed(featureId))
            }
            guard case .sketch(let sketchData) = targetFeature.operation else {
                return .failure(.targetNotASketch(featureId))
            }
            guard let entity = sketchData.entities.first(where: { $0.id == entityId }) else {
                return .failure(.sketchEntityNotFound(featureId: featureId, entityId: entityId))
            }
            return .success(ResolvedReference(reference: reference, target: .sketchEntity(feature: targetFeature, entity: entity)))

        case .body(let solidId):
            if let refIndex {
                for i in 0..<refIndex {
                    let prior = document.features[i]
                    guard !prior.isSuppressed else { continue }
                    if case .deleteBody(let d) = prior.operation, d.targetBodyId == solidId {
                        return .failure(.bodyNotFound(solidId))
                    }
                    if case .combine(let c) = prior.operation, !c.keepTool, c.toolBodyId == solidId {
                        return .failure(.bodyNotFound(solidId))
                    }
                }
            }
            if let targetIndex = document.features.firstIndex(where: { $0.outputSolidId == solidId }) {
                let targetFeature = document.features[targetIndex]
                if let referencingFeature, referencingFeature.id == targetFeature.id {
                    return .failure(.selfReference(targetFeature.id))
                }
                if let refIndex, targetIndex > refIndex, let referencingFeature {
                    return .failure(.forwardReference(referencedFeatureId: targetFeature.id, currentFeatureId: referencingFeature.id))
                }
                if targetFeature.isSuppressed {
                    return .failure(.targetFeatureSuppressed(targetFeature.id))
                }
                return .success(ResolvedReference(reference: reference, target: .body(solidId: solidId, feature: targetFeature)))
            } else if document.objects.contains(where: { $0.id == solidId }) {
                return .success(ResolvedReference(reference: reference, target: .body(solidId: solidId, feature: nil)))
            } else {
                return .failure(.bodyNotFound(solidId))
            }

        case .face(let topRef):
            guard topRef.elementType == .face else {
                return .failure(.typeMismatch(expected: "face", actual: topRef.elementType.rawValue))
            }
            return resolveTopology(reference: reference, topRef: topRef, referencingFeature: referencingFeature, refIndex: refIndex, in: document) { sourceFeature in
                .face(sourceFeature: sourceFeature, reference: topRef)
            }

        case .edge(let topRef):
            guard topRef.elementType == .edge else {
                return .failure(.typeMismatch(expected: "edge", actual: topRef.elementType.rawValue))
            }
            return resolveTopology(reference: reference, topRef: topRef, referencingFeature: referencingFeature, refIndex: refIndex, in: document) { sourceFeature in
                .edge(sourceFeature: sourceFeature, reference: topRef)
            }

        case .vertex(let topRef):
            guard topRef.elementType == .vertex else {
                return .failure(.typeMismatch(expected: "vertex", actual: topRef.elementType.rawValue))
            }
            return resolveTopology(reference: reference, topRef: topRef, referencingFeature: referencingFeature, refIndex: refIndex, in: document) { sourceFeature in
                .vertex(sourceFeature: sourceFeature, reference: topRef)
            }

        case .component(let componentId):
            if let comp = document.componentInstances.first(where: { $0.id == componentId }) {
                return .success(ResolvedReference(reference: reference, target: .component(comp)))
            } else {
                return .failure(.componentNotFound(componentId))
            }
        }
    }

    private static func resolveTopology(
        reference: Reference,
        topRef: TopologicalReference,
        referencingFeature: Feature?,
        refIndex: Int?,
        in document: DocumentModel,
        makeTarget: (Feature) -> ResolvedTarget
    ) -> Result<ResolvedReference, ReferenceResolutionError> {
        let sourceId = topRef.sourceFeatureId
        if let referencingFeature, referencingFeature.id == sourceId {
            return .failure(.selfReference(sourceId))
        }
        guard let sourceIndex = document.features.firstIndex(where: { $0.id == sourceId }) else {
            return .failure(.topologicalSourceFeatureNotFound(sourceId))
        }
        if let refIndex, sourceIndex > refIndex, let referencingFeature {
            return .failure(.forwardReference(referencedFeatureId: sourceId, currentFeatureId: referencingFeature.id))
        }
        let sourceFeature = document.features[sourceIndex]
        if sourceFeature.isSuppressed {
            return .failure(.topologicalSourceFeatureSuppressed(sourceId))
        }

        if !sourceFeature.generatedTopology.isEmpty {
            let exists = sourceFeature.generatedTopology.values.contains { existing in
                existing.id == topRef.id ||
                (existing.elementType == topRef.elementType &&
                 !existing.historyPath.isEmpty &&
                 existing.historyPath == topRef.historyPath)
            }
            guard exists else {
                return .failure(.topologicalElementMissing(topRef))
            }
        } else {
            guard !topRef.historyPath.isEmpty || topRef.disambiguator != nil else {
                return .failure(.topologicalElementMissing(topRef))
            }
        }

        return .success(ResolvedReference(reference: reference, target: makeTarget(sourceFeature)))
    }

    /// Resolves all references defined on a feature against the document model.
    public static func resolveAll(
        for feature: Feature,
        in document: DocumentModel
    ) -> [Reference: Result<ResolvedReference, ReferenceResolutionError>] {
        var results: [Reference: Result<ResolvedReference, ReferenceResolutionError>] = [:]
        for ref in feature.references {
            results[ref] = resolve(reference: ref, for: feature, in: document)
        }
        return results
    }

    /// Validates all references defined on a feature, returning the first resolution error encountered or nil if all valid.
    public static func validateReferences(
        for feature: Feature,
        in document: DocumentModel
    ) -> ReferenceResolutionError? {
        for ref in feature.references {
            if case .failure(let error) = resolve(reference: ref, for: feature, in: document) {
                return error
            }
        }
        let refIndex = document.features.firstIndex(where: { $0.id == feature.id })
        func isDeleted(_ bodyId: SolidId) -> Bool {
            guard let refIndex else { return false }
            for i in 0..<refIndex {
                let prior = document.features[i]
                guard !prior.isSuppressed else { continue }
                if case .deleteBody(let d) = prior.operation, d.targetBodyId == bodyId {
                    return true
                }
                if case .combine(let c) = prior.operation, !c.keepTool, c.toolBodyId == bodyId {
                    return true
                }
            }
            return false
        }
        if feature.bodyOperation != .create {
            guard let targetBodyId = feature.targetBodyId else {
                return .missingTargetBody(featureId: feature.id, operation: feature.bodyOperation)
            }
            if targetBodyId == feature.outputSolidId {
                return .selfReference(feature.id)
            }
            if let targetIndex = document.features.firstIndex(where: { $0.outputSolidId == targetBodyId }) {
                let targetFeat = document.features[targetIndex]
                if targetFeat.id == feature.id {
                    return .selfReference(feature.id)
                }
                if let refIndex, targetIndex > refIndex {
                    return .forwardReference(referencedFeatureId: targetFeat.id, currentFeatureId: feature.id)
                }
                if targetFeat.isSuppressed {
                    return .targetFeatureSuppressed(targetFeat.id)
                }
                if isDeleted(targetBodyId) {
                    return .bodyNotFound(targetBodyId)
                }
            } else if !document.objects.contains(where: { $0.id == targetBodyId }) || isDeleted(targetBodyId) {
                return .bodyNotFound(targetBodyId)
            }
        }
        switch feature.operation {
        case .combine(let c):
            if isDeleted(c.targetBodyId) { return .bodyNotFound(c.targetBodyId) }
            if isDeleted(c.toolBodyId) { return .bodyNotFound(c.toolBodyId) }
        case .moveBody(let m):
            if isDeleted(m.targetBodyId) { return .bodyNotFound(m.targetBodyId) }
        case .copyBody(let c):
            if isDeleted(c.sourceBodyId) { return .bodyNotFound(c.sourceBodyId) }
        case .deleteBody(let d):
            if isDeleted(d.targetBodyId) { return .bodyNotFound(d.targetBodyId) }
        default:
            break
        }
        return nil
    }
}
