import Testing
import Foundation
@testable import MadeCore

@Suite struct SelectionFilterTests {
    @Test func testSelectionFilterConstantsAndBitmask() {
        #expect(SelectionFilter.faces.rawValue == 1 << 0)
        #expect(SelectionFilter.edges.rawValue == 1 << 1)
        #expect(SelectionFilter.vertices.rawValue == 1 << 2)
        #expect(SelectionFilter.bodies.rawValue == 1 << 3)
        #expect(SelectionFilter.sketchEntities.rawValue == 1 << 4)
        #expect(SelectionFilter.components.rawValue == 1 << 5)

        let expectedAllRaw: UInt8 = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4) | (1 << 5)
        #expect(SelectionFilter.all.rawValue == expectedAllRaw)
    }

    @Test func testAllowsQueryHelpersOnAll() {
        let filter = SelectionFilter.all
        #expect(filter.allowsFaces)
        #expect(filter.allowsEdges)
        #expect(filter.allowsVertices)
        #expect(filter.allowsBodies)
        #expect(filter.allowsSketchEntities)
        #expect(filter.allowsComponents)
        #expect(filter.allowsSubElements)
    }

    @Test func testAllowsQueryHelpersOnIndividualFilters() {
        let faceOnly = SelectionFilter.faces
        #expect(faceOnly.allowsFaces)
        #expect(!faceOnly.allowsEdges)
        #expect(!faceOnly.allowsVertices)
        #expect(!faceOnly.allowsBodies)
        #expect(!faceOnly.allowsSketchEntities)
        #expect(!faceOnly.allowsComponents)
        #expect(faceOnly.allowsSubElements)

        let edgeOnly = SelectionFilter.edges
        #expect(!edgeOnly.allowsFaces)
        #expect(edgeOnly.allowsEdges)
        #expect(!edgeOnly.allowsVertices)
        #expect(!edgeOnly.allowsBodies)
        #expect(edgeOnly.allowsSubElements)

        let vertexOnly = SelectionFilter.vertices
        #expect(!vertexOnly.allowsFaces)
        #expect(!vertexOnly.allowsEdges)
        #expect(vertexOnly.allowsVertices)
        #expect(!vertexOnly.allowsBodies)
        #expect(vertexOnly.allowsSubElements)

        let bodyOnly = SelectionFilter.bodies
        #expect(!bodyOnly.allowsFaces)
        #expect(!bodyOnly.allowsEdges)
        #expect(!bodyOnly.allowsVertices)
        #expect(bodyOnly.allowsBodies)
        #expect(!bodyOnly.allowsSubElements)

        let sketchOnly = SelectionFilter.sketchEntities
        #expect(!sketchOnly.allowsFaces)
        #expect(!sketchOnly.allowsSubElements)
        #expect(sketchOnly.allowsSketchEntities)

        let compOnly = SelectionFilter.components
        #expect(!compOnly.allowsFaces)
        #expect(!compOnly.allowsSubElements)
        #expect(compOnly.allowsComponents)
    }

    @Test func testEmptyOptionSet() {
        let empty: SelectionFilter = []
        #expect(!empty.allowsFaces)
        #expect(!empty.allowsEdges)
        #expect(!empty.allowsVertices)
        #expect(!empty.allowsBodies)
        #expect(!empty.allowsSketchEntities)
        #expect(!empty.allowsComponents)
        #expect(!empty.allowsSubElements)
    }

    @Test func testCombinationFilters() {
        let topoFilters: SelectionFilter = [.faces, .edges]
        #expect(topoFilters.allowsFaces)
        #expect(topoFilters.allowsEdges)
        #expect(!topoFilters.allowsVertices)
        #expect(!topoFilters.allowsBodies)
        #expect(topoFilters.allowsSubElements)

        let bodyAndSketch: SelectionFilter = [.bodies, .sketchEntities]
        #expect(!bodyAndSketch.allowsSubElements)
        #expect(bodyAndSketch.allowsBodies)
        #expect(bodyAndSketch.allowsSketchEntities)
    }

    @Test func testCodableRoundtrip() throws {
        let original: SelectionFilter = [.faces, .vertices, .bodies]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SelectionFilter.self, from: data)
        #expect(decoded == original)
    }

    @Test func testHashableAndEquatable() {
        var set = Set<SelectionFilter>()
        set.insert(.faces)
        set.insert(.edges)
        #expect(set.contains(.faces))
        #expect(set.contains(.edges))
        #expect(!set.contains(.vertices))
    }
}
