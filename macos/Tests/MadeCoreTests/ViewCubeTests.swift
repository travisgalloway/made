import Testing
import Foundation
import simd
import CoreGraphics
@testable import MadeCore

@Suite struct ViewCubeTests {

    let size = CGSize(width: 100, height: 100)

    // MARK: - Direct Orthogonal Face Hit-Testing

    @Test func testOrthogonalFaceHitTesting() {
        // In each preset orthogonal view, clicking the center (50, 50) should hit that face
        let center = CGPoint(x: 50, y: 50)

        let frontCam = Camera.preset(.front)
        #expect(ViewCube.hitTest(point: center, in: size, camera: frontCam) == .face(.front))

        let topCam = Camera.preset(.top)
        #expect(ViewCube.hitTest(point: center, in: size, camera: topCam) == .face(.top))

        let rightCam = Camera.preset(.right)
        #expect(ViewCube.hitTest(point: center, in: size, camera: rightCam) == .face(.right))

        let backCam = Camera.preset(.back)
        #expect(ViewCube.hitTest(point: center, in: size, camera: backCam) == .face(.back))

        let leftCam = Camera.preset(.left)
        #expect(ViewCube.hitTest(point: center, in: size, camera: leftCam) == .face(.left))

        let bottomCam = Camera.preset(.bottom)
        #expect(ViewCube.hitTest(point: center, in: size, camera: bottomCam) == .face(.bottom))
    }

    // MARK: - Edge Hit-Testing

    @Test func testEdgeHitTesting() {
        let frontCam = Camera.preset(.front)
        // With size 100x100, scale = 28.0, center = (50, 50)
        // Offset for 0.85 threshold: 0.85 * 28 = 23.8 pt

        // Top edge of Front face
        let topEdgePoint = CGPoint(x: 50, y: 50 - 23.8)
        let topEdgeHit = ViewCube.hitTest(point: topEdgePoint, in: size, camera: frontCam)
        #expect(topEdgeHit == .edge(.front, .top))
        #expect(topEdgeHit == .edge(.top, .front)) // Canonical equality

        // Bottom edge of Front face
        let bottomEdgePoint = CGPoint(x: 50, y: 50 + 23.8)
        let bottomEdgeHit = ViewCube.hitTest(point: bottomEdgePoint, in: size, camera: frontCam)
        #expect(bottomEdgeHit == .edge(.front, .bottom))
        #expect(bottomEdgeHit == .edge(.bottom, .front))

        // Right edge of Front face
        let rightEdgePoint = CGPoint(x: 50 + 23.8, y: 50)
        let rightEdgeHit = ViewCube.hitTest(point: rightEdgePoint, in: size, camera: frontCam)
        #expect(rightEdgeHit == .edge(.front, .right))
        #expect(rightEdgeHit == .edge(.right, .front))

        // Left edge of Front face
        let leftEdgePoint = CGPoint(x: 50 - 23.8, y: 50)
        let leftEdgeHit = ViewCube.hitTest(point: leftEdgePoint, in: size, camera: frontCam)
        #expect(leftEdgeHit == .edge(.front, .left))
        #expect(leftEdgeHit == .edge(.left, .front))
    }

    // MARK: - Corner Hit-Testing

    @Test func testCornerHitTesting() {
        let frontCam = Camera.preset(.front)

        // Top-right corner of Front face
        let trCornerPoint = CGPoint(x: 50 + 23.8, y: 50 - 23.8)
        let trHit = ViewCube.hitTest(point: trCornerPoint, in: size, camera: frontCam)
        #expect(trHit == .corner(.front, .right, .top))
        #expect(trHit == .corner(.top, .front, .right)) // Order-independent equality

        // Top-left corner of Front face
        let tlCornerPoint = CGPoint(x: 50 - 23.8, y: 50 - 23.8)
        let tlHit = ViewCube.hitTest(point: tlCornerPoint, in: size, camera: frontCam)
        #expect(tlHit == .corner(.front, .left, .top))

        // Bottom-right corner of Front face
        let brCornerPoint = CGPoint(x: 50 + 23.8, y: 50 + 23.8)
        let brHit = ViewCube.hitTest(point: brCornerPoint, in: size, camera: frontCam)
        #expect(brHit == .corner(.front, .right, .bottom))

        // Bottom-left corner of Front face
        let blCornerPoint = CGPoint(x: 50 - 23.8, y: 50 + 23.8)
        let blHit = ViewCube.hitTest(point: blCornerPoint, in: size, camera: frontCam)
        #expect(blHit == .corner(.front, .left, .bottom))
    }

    // MARK: - Raycast Miss Detection

    @Test func testRaycastMissReturnsNil() {
        let frontCam = Camera.preset(.front)

        // Far corners of the 100x100 canvas (outside the ~28pt radius cube)
        #expect(ViewCube.hitTest(point: CGPoint(x: 5, y: 5), in: size, camera: frontCam) == nil)
        #expect(ViewCube.hitTest(point: CGPoint(x: 95, y: 5), in: size, camera: frontCam) == nil)
        #expect(ViewCube.hitTest(point: CGPoint(x: 5, y: 95), in: size, camera: frontCam) == nil)
        #expect(ViewCube.hitTest(point: CGPoint(x: 95, y: 95), in: size, camera: frontCam) == nil)
    }

    // MARK: - Isometric Projection and Face Visibility

    @Test func testIsometricProjectedFaces() {
        let isoCam = Camera.preset(.isometric)
        let projected = ViewCube.projectedFaces(camera: isoCam, size: size)

        // Isometric view looking from (+X, -Y, +Z) must see Top, Front, Right
        let visibleFaces = Set(projected.map(\.face))
        #expect(visibleFaces.count == 3)
        #expect(visibleFaces.contains(.top))
        #expect(visibleFaces.contains(.front))
        #expect(visibleFaces.contains(.right))

        for pf in projected {
            #expect(pf.vertices.count == 4)
            #expect(!pf.center.x.isNaN && !pf.center.y.isNaN)
        }
    }

    // MARK: - Camera Presets Generated for Regions

    @Test func testCamerasGeneratedForRegions() {
        let target = SIMD3<Float>(10, 20, 30)
        let distance: Float = 200.0

        // Home
        let homeCam = ViewCube.camera(for: .home, target: target, distance: distance)
        #expect(homeCam.target == target)
        let homeDist = simd_length(homeCam.position - target)
        #expect(abs(homeDist - distance) <= 1e-2)

        // Faces
        for face in ViewCube.Face.allCases {
            let cam = ViewCube.camera(for: .face(face), target: target, distance: distance)
            #expect(cam.target == target)
            let d = simd_length(cam.position - target)
            #expect(abs(d - distance) <= 1e-2)

            let lookAt = Orientation.makeLookAt(eye: cam.position, target: cam.target)
            #expect(!lookAt.columns.0.x.isNaN)
            #expect(!lookAt.columns.3.w.isNaN)
        }

        // Edge
        let edgeCam = ViewCube.camera(for: .edge(.top, .front), target: target, distance: distance)
        #expect(edgeCam.target == target)
        let edgeDist = simd_length(edgeCam.position - target)
        #expect(abs(edgeDist - distance) <= 1e-2)
        #expect(edgeCam.position.z > target.z)
        #expect(edgeCam.position.y < target.y)

        // Corner
        let cornerCam = ViewCube.camera(for: .corner(.top, .front, .right), target: target, distance: distance)
        #expect(cornerCam.target == target)
        let cornerDist = simd_length(cornerCam.position - target)
        #expect(abs(cornerDist - distance) <= 1e-2)
        #expect(cornerCam.position.z > target.z)
        #expect(cornerCam.position.y < target.y)
        #expect(cornerCam.position.x > target.x)
    }

    // MARK: - Region Helper Methods

    @Test func testRegionContainsFaceAndDisplayName() {
        let home = ViewCube.Region.home
        #expect(!home.contains(face: .top))
        #expect(home.displayName == "Home")

        let face = ViewCube.Region.face(.front)
        #expect(face.contains(face: .front))
        #expect(!face.contains(face: .back))
        #expect(face.displayName == "FRONT")

        let edge = ViewCube.Region.edge(.top, .front)
        #expect(edge.contains(face: .top))
        #expect(edge.contains(face: .front))
        #expect(!edge.contains(face: .right))

        let corner = ViewCube.Region.corner(.top, .front, .right)
        #expect(corner.contains(face: .top))
        #expect(corner.contains(face: .front))
        #expect(corner.contains(face: .right))
        #expect(!corner.contains(face: .left))
    }
}
