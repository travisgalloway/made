import Testing
import Foundation
@testable import MadeCore

@Suite struct CADDSLTests {
    let kernel = KernelClient(debounceDuration: .milliseconds(5))
    
    private func payload(_ shape: any CADShape) async throws -> MeshPayload {
        try #require(await shape.evaluate(on: kernel, solidId: SolidId("dsl")).value)
    }
    
    @Test func testDeclarativeBoxCreation() async throws {
        let box = Box(width: 40, depth: 30, height: 10)
        let payload = try await payload(box)
        
        #expect(payload.triangleCount > 0)
        #expect(payload.indices.count == (payload.triangleCount * 3))
        #expect(payload.positions.count == payload.normals.count)
    }
    
    @Test func testDeclarativeCylinderCreation() async throws {
        let cyl = Cylinder(radius: 5, height: 20, slices: 16)
        let payload = try await payload(cyl)
        
        #expect(payload.triangleCount > 0)
        #expect(payload.indices.count == (payload.triangleCount * 3))
    }
    
    @Test func testDeclarativeSubtractionOperator() async throws {
        let plateWithHole = Box(width: 50, depth: 50, height: 10) - Cylinder(radius: 8, height: 20)
        let payload = try await payload(plateWithHole)
        
        #expect(payload.triangleCount > 0)
        #expect(payload.indices.count == (payload.triangleCount * 3))
    }
    
    @Test func testDeclarativeUnionOperator() async throws {
        let combined = Box(width: 20, depth: 20, height: 20) + Box(width: 10, depth: 10, height: 10).translated(x: 20)
        let payload = try await payload(combined)
        
        #expect(payload.triangleCount > 0)
        #expect(payload.indices.count == (payload.triangleCount * 3))
    }
    
    @Test func testDeclarativeIntersectionOperator() async throws {
        let common = Box(width: 20, depth: 20, height: 20) & Cylinder(radius: 10, height: 30)
        let payload = try await payload(common)
        
        #expect(payload.triangleCount > 0)
        #expect(payload.indices.count == (payload.triangleCount * 3))
    }
    
    @Test func testDeclarativeMethodChaining() async throws {
        let part = Box(width: 60, depth: 40, height: 15)
            .subtracting(Cylinder(radius: 5, height: 25))
            .translated(z: 5)
        let payload = try await payload(part)
        
        #expect(payload.triangleCount > 0)
        #expect(payload.indices.count == (payload.triangleCount * 3))
    }
    
    // MARK: - Descriptions (no kernel)
    
    @Test func testBoxOffsetWrapsInTranslate() {
        let params = BoxParams(width: 1, depth: 2, height: 3)
        var box = Box(width: 1, depth: 2, height: 3)
        #expect(box.shapeDescription == .box(params))
        box.offset = SIMD3(4, 5, 6)
        #expect(box.shapeDescription == .translate(.box(params), offset: SIMD3(4, 5, 6)))
        
        var cyl = Cylinder(radius: 1, height: 2, slices: 12)
        cyl.offset = SIMD3(0, 0, 1)
        #expect(cyl.shapeDescription == .translate(.cylinder(CylinderParams(radius: 1, height: 2), slices: 12), offset: SIMD3(0, 0, 1)))
    }
    
    @Test func testOperatorsBuildBooleanNodes() {
        let a = Box(width: 1, depth: 1, height: 1), b = Cylinder(radius: 1, height: 1)
        let pairs: [(CSGCompositeShape, BooleanOp)] = [(a - b, .subtract), (a + b, .union), (a & b, .intersect)]
        for (shape, op) in pairs {
            #expect(shape.shapeDescription == .boolean(op, a.shapeDescription, b.shapeDescription))
        }
    }
    
    @Test func testTranslatedWrapsNode() {
        let box = Box(width: 1, depth: 1, height: 1)
        #expect(box.translated(x: 1, z: 2).shapeDescription == .translate(box.shapeDescription, offset: SIMD3(1, 0, 2)))
    }
    
    // MARK: - CADShapeBuilder Result Builder Tests
    
    @Test func testShapeBuilderMultipleStatementsCombinesAsUnion() async throws {
        let a = Box(width: 10, depth: 10, height: 10)
        let b = Cylinder(radius: 5, height: 20)
        let c = Box(width: 5, depth: 5, height: 5).translated(z: 10)
        
        // Single statement returns unwrapped shape
        let single = shape {
            a
        }
        #expect(single.shapeDescription == a.shapeDescription)
        
        // Two statements fold to union
        let two = shape {
            a
            b
        }
        #expect(two.shapeDescription == .boolean(.union, a.shapeDescription, b.shapeDescription))
        
        // Three statements fold into left-leaning binary tree ((a union b) union c)
        let three = shape {
            a
            b
            c
        }
        let expectedThree = ShapeNode.boolean(.union, .boolean(.union, a.shapeDescription, b.shapeDescription), c.shapeDescription)
        #expect(three.shapeDescription == expectedThree)
        
        // Kernel mesh evaluation
        let payloadTwo = try await payload(two)
        #expect(payloadTwo.triangleCount > 0)
        #expect(payloadTwo.indices.count == (payloadTwo.triangleCount * 3))
        
        let payloadThree = try await payload(three)
        #expect(payloadThree.triangleCount > 0)
        #expect(payloadThree.indices.count == (payloadThree.triangleCount * 3))
    }
    
    @Test func testShapeBuilderConditionals() {
        let a = Box(width: 10, depth: 10, height: 10)
        let b = Cylinder(radius: 5, height: 10)
        
        let includeShape = true
        let trueResult = shape {
            a
            if includeShape {
                b
            }
        }
        #expect(trueResult.shapeDescription == .boolean(.union, a.shapeDescription, b.shapeDescription))
        
        let excludeShape = false
        let falseResult = shape {
            a
            if excludeShape {
                b
            }
        }
        #expect(falseResult.shapeDescription == a.shapeDescription)
    }
    
    @Test func testShapeBuilderIfElse() {
        let a = Box(width: 10, depth: 10, height: 10)
        let b = Cylinder(radius: 5, height: 10)
        
        func branchShape(first: Bool) -> any CADShape {
            shape {
                if first {
                    a
                } else {
                    b
                }
            }
        }
        
        #expect(branchShape(first: true).shapeDescription == a.shapeDescription)
        #expect(branchShape(first: false).shapeDescription == b.shapeDescription)
    }
    
    @Test func testShapeBuilderLoops() async throws {
        let count = 3
        let stepped = shape {
            for i in 0..<count {
                Box(width: 10, depth: 10, height: 10).translated(x: Float(i * 15))
            }
        }
        
        let b0 = Box(width: 10, depth: 10, height: 10).translated(x: 0)
        let b1 = Box(width: 10, depth: 10, height: 10).translated(x: 15)
        let b2 = Box(width: 10, depth: 10, height: 10).translated(x: 30)
        let expected = ShapeNode.boolean(.union, .boolean(.union, b0.shapeDescription, b1.shapeDescription), b2.shapeDescription)
        #expect(stepped.shapeDescription == expected)
        
        let payloadLoop = try await payload(stepped)
        #expect(payloadLoop.triangleCount > 0)
        #expect(payloadLoop.indices.count == (payloadLoop.triangleCount * 3))
    }
    
    @Test func testShapeBuilderZeroIterationLoopContributesNothing() {
        let single = Box(width: 10, depth: 10, height: 10)
        let result = shape {
            single
            for _ in 0..<0 {
                Cylinder(radius: 5, height: 10)
            }
        }
        #expect(result.shapeDescription == single.shapeDescription)
    }
    
    @Test func testShapeBuilderFalseConditionContributesNothing() {
        let single = Box(width: 10, depth: 10, height: 10)
        let result = shape {
            single
            if false {
                Cylinder(radius: 5, height: 10)
            }
        }
        #expect(result.shapeDescription == single.shapeDescription)
    }
    
    @CADShapeBuilder
    private static func subAssembly() -> any CADShape {
        Box(width: 5, depth: 5, height: 5)
        Cylinder(radius: 2, height: 10)
    }

    @Test func testShapeBuilderNestedBuilder() async throws {
        // 1. @CADShapeBuilder function called from another builder
        let base = Box(width: 20, depth: 20, height: 20)
        let combinedFunc = shape {
            base
            Self.subAssembly()
        }
        let expectedSub = ShapeNode.boolean(
            .union,
            Box(width: 5, depth: 5, height: 5).shapeDescription,
            Cylinder(radius: 2, height: 10).shapeDescription
        )
        #expect(combinedFunc.shapeDescription == .boolean(.union, base.shapeDescription, expectedSub))
        
        // 2. Builder closure in .subtracting with multiple statements
        let plate = Box(width: 50, depth: 50, height: 10)
        let c1 = Cylinder(radius: 4, height: 20).translated(x: -15)
        let c2 = Cylinder(radius: 4, height: 20).translated(x: 15)
        let subtracted = plate.subtracting {
            c1
            c2
        }
        let expectedHoles = ShapeNode.boolean(.union, c1.shapeDescription, c2.shapeDescription)
        #expect(subtracted.shapeDescription == .boolean(.subtract, plate.shapeDescription, expectedHoles))
        
        // 3. Builder closure in .union with multiple statements
        let unioned = plate.union {
            c1
            c2
        }
        #expect(unioned.shapeDescription == .boolean(.union, plate.shapeDescription, expectedHoles))
        
        // 4. Top-level shape helper with nested shape helper
        let nested = shape {
            shape {
                Box(width: 10, depth: 10, height: 10)
                Box(width: 10, depth: 10, height: 10).translated(x: 10)
            }
            Cylinder(radius: 4, height: 15)
        }
        let payloadNested = try await payload(nested)
        #expect(payloadNested.triangleCount > 0)
    }
    
    @Test func testShapeBuilderEmptyBlockFailsWithMessage() {
        var capturedMessage: String?
        CADShapeBuilder.emptyBlockHandler = { msg in
            capturedMessage = msg
        }
        defer {
            CADShapeBuilder.emptyBlockHandler = nil
        }
        
        _ = shape { }
        #expect(capturedMessage == CADShapeBuilder.emptyBlockMessage)
    }
}
