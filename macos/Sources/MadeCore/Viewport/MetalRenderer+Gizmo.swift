import Foundation
import Metal
import simd

extension MetalRenderer {
    func setupGizmo(arrowLength: Float = defaultGizmoArrowLength, ringRadius: Float = defaultGizmoRingRadius) {
        var geometry: [GizmoHandle: GizmoGeometryBuffers] = [:]
        
        // 1. Translation arrow geometry: shaft + 4-barb arrowhead
        let arrowheadLength: Float = 6.0
        let barbRadius: Float = 2.0
        
        for handle in [GizmoHandle.translateX, .translateY, .translateZ] {
            var positions: [Float] = []
            let axis = handle.axis
            let tip = axis * arrowLength
            
            // Shaft: (0, 0, 0) to tip
            positions.append(contentsOf: [0, 0, 0, tip.x, tip.y, tip.z])
            
            // Arrowhead barbs pointing backward toward the base
            switch handle {
            case .translateX:
                let base = tip.x - arrowheadLength
                // Barb 1 (+Y)
                positions.append(contentsOf: [tip.x, tip.y, tip.z, base, barbRadius, 0])
                // Barb 2 (-Y)
                positions.append(contentsOf: [tip.x, tip.y, tip.z, base, -barbRadius, 0])
                // Barb 3 (+Z)
                positions.append(contentsOf: [tip.x, tip.y, tip.z, base, 0, barbRadius])
                // Barb 4 (-Z)
                positions.append(contentsOf: [tip.x, tip.y, tip.z, base, 0, -barbRadius])
            case .translateY:
                let base = tip.y - arrowheadLength
                // Barb 1 (+X)
                positions.append(contentsOf: [tip.x, tip.y, tip.z, barbRadius, base, 0])
                // Barb 2 (-X)
                positions.append(contentsOf: [tip.x, tip.y, tip.z, -barbRadius, base, 0])
                // Barb 3 (+Z)
                positions.append(contentsOf: [tip.x, tip.y, tip.z, 0, base, barbRadius])
                // Barb 4 (-Z)
                positions.append(contentsOf: [tip.x, tip.y, tip.z, 0, base, -barbRadius])
            case .translateZ:
                let base = tip.z - arrowheadLength
                // Barb 1 (+X)
                positions.append(contentsOf: [tip.x, tip.y, tip.z, barbRadius, 0, base])
                // Barb 2 (-X)
                positions.append(contentsOf: [tip.x, tip.y, tip.z, -barbRadius, 0, base])
                // Barb 3 (+Y)
                positions.append(contentsOf: [tip.x, tip.y, tip.z, 0, barbRadius, base])
                // Barb 4 (-Y)
                positions.append(contentsOf: [tip.x, tip.y, tip.z, 0, -barbRadius, base])
            default:
                break
            }
            
            let vCount = positions.count / 3
            let defaultColor = handle.defaultColor
            let activeColor = GizmoColors.active
            
            let defColors: [SIMD4<Float>] = Array(repeating: defaultColor, count: vCount)
            let actColors: [SIMD4<Float>] = Array(repeating: activeColor, count: vCount)
            
            guard let posBuf = makeBuffer(positions, label: "Gizmo \(handle.rawValue) Positions"),
                  let defColBuf = makeBuffer(defColors, label: "Gizmo \(handle.rawValue) Default Colors"),
                  let actColBuf = makeBuffer(actColors, label: "Gizmo \(handle.rawValue) Active Colors") else {
                continue
            }
            geometry[handle] = GizmoGeometryBuffers(
                positionBuffer: posBuf,
                defaultColorBuffer: defColBuf,
                activeColorBuffer: actColBuf,
                vertexCount: vCount
            )
        }
        
        // 2. Rotation rings (32 segments each)
        let ringSegments = 32
        for handle in [GizmoHandle.rotateX, .rotateY, .rotateZ] {
            var positions: [Float] = []
            for i in 0..<ringSegments {
                let theta0 = Float(i) * (2.0 * .pi / Float(ringSegments))
                let theta1 = Float(i + 1) * (2.0 * .pi / Float(ringSegments))
                let p0: SIMD3<Float>
                let p1: SIMD3<Float>
                switch handle {
                case .rotateX:
                    p0 = SIMD3<Float>(0, ringRadius * cos(theta0), ringRadius * sin(theta0))
                    p1 = SIMD3<Float>(0, ringRadius * cos(theta1), ringRadius * sin(theta1))
                case .rotateY:
                    p0 = SIMD3<Float>(ringRadius * cos(theta0), 0, ringRadius * sin(theta0))
                    p1 = SIMD3<Float>(ringRadius * cos(theta1), 0, ringRadius * sin(theta1))
                case .rotateZ:
                    p0 = SIMD3<Float>(ringRadius * cos(theta0), ringRadius * sin(theta0), 0)
                    p1 = SIMD3<Float>(ringRadius * cos(theta1), ringRadius * sin(theta1), 0)
                default:
                    continue
                }
                positions.append(contentsOf: [p0.x, p0.y, p0.z, p1.x, p1.y, p1.z])
            }
            
            let vCount = positions.count / 3
            let defaultColor = handle.defaultColor
            let activeColor = GizmoColors.active
            
            let defColors: [SIMD4<Float>] = Array(repeating: defaultColor, count: vCount)
            let actColors: [SIMD4<Float>] = Array(repeating: activeColor, count: vCount)
            
            guard let posBuf = makeBuffer(positions, label: "Gizmo \(handle.rawValue) Positions"),
                  let defColBuf = makeBuffer(defColors, label: "Gizmo \(handle.rawValue) Default Colors"),
                  let actColBuf = makeBuffer(actColors, label: "Gizmo \(handle.rawValue) Active Colors") else {
                continue
            }
            geometry[handle] = GizmoGeometryBuffers(
                positionBuffer: posBuf,
                defaultColorBuffer: defColBuf,
                activeColorBuffer: actColBuf,
                vertexCount: vCount
            )
        }
        
        self.gizmoGeometry = geometry
        updateResidency()
    }
    
    func drawGizmo(
        _ ctx: EncodeContext,
        mesh: MetalMesh,
        viewMatrix: simd_float4x4,
        projMatrix: simd_float4x4,
        drawCalls: inout Int
    ) {
        var modelTranslation = matrix_identity_float4x4
        modelTranslation.columns.3 = SIMD4<Float>(mesh.transform.position, 1.0)
        let lineUniforms = GridUniforms(viewProjectionMatrix: projMatrix * viewMatrix * modelTranslation)
        guard ctx.bindUniforms(lineUniforms, at: 2) else { return }
        
        ctx.encoder.setRenderPipelineState(linePipeline)
        ctx.encoder.setDepthStencilState(snapDepthState)
        ctx.encoder.setCullMode(.none)
        
        for handle in GizmoHandle.allCases {
            guard let geom = gizmoGeometry[handle] else { continue }
            let colorBuf = (activeGizmoHandle == handle) ? geom.activeColorBuffer : geom.defaultColorBuffer
            ctx.bind(geom.positionBuffer, at: 0)
            ctx.bind(colorBuf, at: 1)
            ctx.encoder.drawPrimitives(primitiveType: .line, vertexStart: 0, vertexCount: geom.vertexCount)
            drawCalls += 1
        }
    }
}
