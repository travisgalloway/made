import Foundation

/// Rebuilds kernel requests from the document, so a restarted kernel service can be repopulated.
@MainActor
public enum KernelRegeneration {
    /// The request that recomputes `feature`, or nil for features that do not produce kernel geometry.
    public static func request(for feature: Feature, jobId: JobId) -> KernelRequest? {
        guard let solidId = feature.outputSolidId else { return nil }
        switch feature.operation {
        case .primitive(.box(let params)):
            return .makeBox(jobId: jobId, solidId: solidId, params: params)
        case .primitive(.cylinder(let params)):
            return .makeCylinder(jobId: jobId, solidId: solidId, params: params)
        case .primitive(.sphere(let params)):
            return .makeSphere(jobId: jobId, solidId: solidId, params: params)
        case .primitive(.cone(let params)):
            return .makeCone(jobId: jobId, solidId: solidId, params: params)
        case .primitive(.torus(let params)):
            return .makeTorus(jobId: jobId, solidId: solidId, params: params)
        case .primitive(.wedge(let params)):
            return .makeWedge(jobId: jobId, solidId: solidId, params: params)
        case .boolean(let b):
            return .booleanOperation(jobId: jobId, solidId: solidId, op: b.op, solidA: b.targetSolidId, solidB: b.toolSolidId)
        case .part(let p):
            guard let shape = p.shape else { return nil }
            return .evaluateShape(jobId: jobId, solidId: solidId, shape: shape)
        case .imported(let imp):
            if let data = imp.data {
                return .importStep(jobId: jobId, solidId: solidId, data: data)
            } else if let sourceURL = imp.sourceURL, FileManager.default.fileExists(atPath: sourceURL.path), let fileData = try? Data(contentsOf: sourceURL) {
                return .importStep(jobId: jobId, solidId: solidId, data: fileData)
            }
            return nil
        case .sketch, .datumPlane:
            return nil
        case .extrude(let data):
            guard let profile = data.profile, let solidId = feature.outputSolidId else { return nil }
            return .evaluateShape(
                jobId: jobId,
                solidId: solidId,
                shape: .extrude(profile: profile, distance: Float(data.distance), centered: data.isSymmetric)
            )
        }
    }

    /// The request that recomputes `object`, or nil for objects the kernel cannot build from parameters.
    public static func request(for object: SceneObject, jobId: JobId) -> KernelRequest? {
        switch object.def {
        case .box(let params): return .makeBox(jobId: jobId, solidId: object.id, params: params)
        case .cylinder(let params): return .makeCylinder(jobId: jobId, solidId: object.id, params: params)
        case .sphere(let params): return .makeSphere(jobId: jobId, solidId: object.id, params: params)
        case .cone(let params): return .makeCone(jobId: jobId, solidId: object.id, params: params)
        case .torus(let params): return .makeTorus(jobId: jobId, solidId: object.id, params: params)
        case .wedge(let params): return .makeWedge(jobId: jobId, solidId: object.id, params: params)
        case .part(_, let shape):
            guard let shape else { return nil }
            return .evaluateShape(jobId: jobId, solidId: object.id, shape: shape)
        case .extrude(let params):
            return .evaluateShape(
                jobId: jobId,
                solidId: object.id,
                shape: .extrude(profile: params.profile, distance: Float(params.distance), centered: params.isSymmetric)
            )
        case .boolean(let op, let solidA, let solidB):
            return .booleanOperation(jobId: jobId, solidId: object.id, op: op, solidA: solidA, solidB: solidB)
        case .imported(_, let sourceURL, let data):
            if let data {
                return .importStep(jobId: jobId, solidId: object.id, data: data)
            } else if let sourceURL, FileManager.default.fileExists(atPath: sourceURL.path), let fileData = try? Data(contentsOf: sourceURL) {
                return .importStep(jobId: jobId, solidId: object.id, data: fileData)
            }
            return nil
        }
    }
    
    /// Resubmits specified features in order, skipping suppressed features, `excluded`, and non-solid features.
    /// Kernel failures and broken references are recorded as `FeatureErrorState` on the affected feature (BL-FND-03).
    public static func regenerate(
        features: [Feature],
        in document: DocumentModel,
        client: any KernelClientProtocol,
        excluding excluded: SolidId? = nil
    ) async {
        for feat in features {
            var feature = document.feature(for: feat.id) ?? feat
            guard !feature.isSuppressed else { continue }
            guard document.isFeatureActive(id: feature.id) else { continue }
            if let excluded, feature.outputSolidId == excluded { continue }

            // Evaluate datum plane features
            if case .datumPlane(var planeData) = feature.operation {
                let upstreamIds = document.directDependencies(of: feature)
                let failedParent = upstreamIds.compactMap { document.feature(for: $0) }.first { $0.errorState != nil }
                if failedParent != nil {
                    let errorState = FeatureErrorState(
                        code: "parent-failed",
                        message: "parent failed",
                        severity: .warning
                    )
                    document.setFeatureError(id: feature.id, error: errorState)
                    continue
                } else if feature.errorState?.code == "parent-failed" {
                    document.setFeatureError(id: feature.id, error: nil)
                }

                if let brokenErr = ReferenceResolver.validateReferences(for: feature, in: document) {
                    let errorState = FeatureErrorState(
                        code: "reference-broken",
                        message: "Reference broken: \(brokenErr.description)",
                        severity: .error
                    )
                    document.setFeatureError(id: feature.id, error: errorState)
                    for dep in document.dependentFeatures(referencing: feature.id) {
                        document.setFeatureError(
                            id: dep.id,
                            error: FeatureErrorState(code: "parent-failed", message: "parent failed", severity: .warning)
                        )
                    }
                    continue
                } else if feature.errorState?.code == "reference-broken" {
                    document.setFeatureError(id: feature.id, error: nil)
                }

                do {
                    let evaluatedPlane = try DatumPlaneEvaluator.evaluate(feature: feature, data: planeData, in: document)
                    planeData.cachedPlane = evaluatedPlane
                    feature.operation = .datumPlane(planeData)
                    _ = document.updateFeature(feature)
                    if feature.errorState?.code == "datum-plane-error" {
                        document.setFeatureError(id: feature.id, error: nil)
                    }
                } catch {
                    let errorState = FeatureErrorState(
                        code: "datum-plane-error",
                        message: error.localizedDescription,
                        severity: .error
                    )
                    document.setFeatureError(id: feature.id, error: errorState)
                    for dep in document.dependentFeatures(referencing: feature.id) {
                        document.setFeatureError(
                            id: dep.id,
                            error: FeatureErrorState(code: "parent-failed", message: "parent failed", severity: .warning)
                        )
                    }
                }
                continue
            }

            // Rebuild profile from upstream sketch entities for extrude features
            if case .extrude(var extrudeData) = feature.operation {
                if let sketchId = extrudeData.sketchFeatureId, let sketchFeature = document.feature(for: sketchId),
                   case .sketch(let sketchData) = sketchFeature.operation {
                    do {
                        let sketchPlane = document.resolveSketchPlane(for: sketchData)
                        let newProfile = try SketchProfileBuilder.build(from: sketchData.entities, plane: sketchPlane)
                        extrudeData.profile = newProfile
                        feature.operation = .extrude(extrudeData)
                        _ = document.updateFeature(feature)
                        if feature.errorState?.code == "sketch-error" {
                            document.setFeatureError(id: feature.id, error: nil)
                        }
                    } catch {
                        let errorState = FeatureErrorState(
                            code: "sketch-error",
                            message: error.localizedDescription,
                            severity: .error
                        )
                        document.setFeatureError(id: feature.id, error: errorState)
                        for dep in document.dependentFeatures(referencing: feature.id) {
                            document.setFeatureError(
                                id: dep.id,
                                error: FeatureErrorState(code: "parent-failed", message: "parent failed", severity: .warning)
                            )
                        }
                        continue
                    }
                }
            }

            // Check upstream parent failures
            let upstreamIds = document.directDependencies(of: feature)
            let failedParent = upstreamIds.compactMap { document.feature(for: $0) }.first { $0.errorState != nil }
            if failedParent != nil {
                let errorState = FeatureErrorState(
                    code: "parent-failed",
                    message: "parent failed",
                    severity: .warning
                )
                document.setFeatureError(id: feature.id, error: errorState)
                continue
            } else if feature.errorState?.code == "parent-failed" {
                document.setFeatureError(id: feature.id, error: nil)
            }

            if let brokenErr = ReferenceResolver.validateReferences(for: feature, in: document) {
                let errorState = FeatureErrorState(
                    code: "reference-broken",
                    message: "Reference broken: \(brokenErr.description)",
                    severity: .error
                )
                document.setFeatureError(id: feature.id, error: errorState)
                for dep in document.dependentFeatures(referencing: feature.id) {
                    document.setFeatureError(
                        id: dep.id,
                        error: FeatureErrorState(code: "parent-failed", message: "parent failed", severity: .warning)
                    )
                }
                continue
            } else if feature.errorState?.code == "reference-broken" {
                document.setFeatureError(id: feature.id, error: nil)
            }

            guard let req = request(for: feature, jobId: JobId("regen-\(UUID().uuidString)")) else { continue }

            let result = await client.request(req)
            switch result {
            case .success:
                document.setFeatureError(id: feature.id, error: nil)
            case .failure(_, let err):
                let errorState = FeatureErrorState(code: err.code.rawValue, message: err.message, severity: .error)
                document.setFeatureError(id: feature.id, error: errorState)
                for dep in document.dependentFeatures(referencing: feature.id) {
                    document.setFeatureError(
                        id: dep.id,
                        error: FeatureErrorState(code: "parent-failed", message: "parent failed", severity: .warning)
                    )
                }
            }
        }
        document.pruneInvalidSelection()
    }

    /// Incrementally regenerates geometry starting from `featureId` and cascading strictly to its transitive dependents (BL-FND-03).
    public static func regenerateIncremental(
        from featureId: UUID,
        in document: DocumentModel,
        client: any KernelClientProtocol,
        excluding excluded: SolidId? = nil
    ) async {
        guard let rootFeature = document.feature(for: featureId),
              document.isFeatureActive(id: featureId) else { return }
        let dependents = document.dependentFeatures(referencing: featureId)
            .filter { document.isFeatureActive(id: $0.id) }
        await regenerate(features: [rootFeature] + dependents, in: document, client: client, excluding: excluded)
    }

    /// Resubmits every buildable feature in sequential list order, skipping suppressed features and `excluded`.
    /// Kernel failures are recorded as `FeatureErrorState` on the affected feature.
    public static func regenerate(
        document: DocumentModel,
        client: any KernelClientProtocol,
        excluding excluded: SolidId? = nil
    ) async {
        await regenerate(features: document.activeFeatures, in: document, client: client, excluding: excluded)
    }
}

