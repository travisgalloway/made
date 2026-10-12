import Metal
import Testing
@testable import MadeCore

enum MetalTestSupport {
    /// The renderer needs Metal 4. Hosted CI runners expose a paravirtual GPU without it, so renderer tests skip there.
    static let isMetal4Available = MTLCreateSystemDefaultDevice()?.supportsFamily(.metal4) == true
}

/// Runs on any Metal device, including CI's paravirtual GPU, so a renderer-test skip cannot hide missing shaders.
@Suite struct ShaderLibraryTests {
    @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "Metal unavailable"))
    func testBundledLibraryHasEveryShaderEntryPoint() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let library = try MetalRenderer.makeShaderLibrary(device: device)
        for name in MetalRenderer.shaderFunctionNames {
            #expect(library.functionNames.contains(name), "missing shader \(name)")
        }
    }
}
