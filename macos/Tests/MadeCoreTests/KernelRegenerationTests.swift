import Testing
import Foundation
@testable import MadeCore

@MainActor
@Suite struct KernelRegenerationTests {
    @Test func testRequestForEachKind() {
        let box = BoxParams(width: 1, depth: 2, height: 3)
        let cylinder = CylinderParams(radius: 4, height: 5)
        let jobId = JobId("j")
        let id = SolidId("s")
        #expect(KernelRegeneration.request(for: object(id, .box(box)), jobId: jobId) == .makeBox(jobId: jobId, solidId: id, params: box))
        #expect(KernelRegeneration.request(for: object(id, .cylinder(cylinder)), jobId: jobId)
                == .makeCylinder(jobId: jobId, solidId: id, params: cylinder))
    }
    
    @Test func testImportedObjectsAreSkipped() {
        #expect(KernelRegeneration.request(for: object(SolidId("i"), .imported(name: "part.step")), jobId: JobId("j")) == nil)
    }
    
    @Test func testRegenerateExcludesSolidAndRepopulatesCache() async {
        let document = DocumentModel()
        let kept = document.addObject(def: .cylinder(CylinderParams(radius: 3, height: 4)))
        let culprit = document.addObject(def: .box(BoxParams(width: 1, depth: 1, height: 1)))
        let imported = document.addObject(def: .imported(name: "part.step"))
        // A fresh client stands in for a restarted service: it holds no solids.
        let client = KernelClient(debounceDuration: .milliseconds(5))
        
        await KernelRegeneration.regenerate(document: document, client: client, excluding: culprit)
        
        for id in document.objects.map(\.id) where id != culprit && id != imported {
            #expect(await client.request(.tessellate(jobId: JobId("t-\(id)"), solidId: id)).isSuccess)
        }
        #expect(await client.request(.tessellate(jobId: JobId("t-kept"), solidId: kept)).isSuccess)
        #expect(await client.request(.tessellate(jobId: JobId("t-culprit"), solidId: culprit)).error?.code == .unknownSolid)
        #expect(await client.request(.tessellate(jobId: JobId("t-imported"), solidId: imported)).error?.code == .unknownSolid)
    }
    
    private func object(_ id: SolidId, _ def: ObjectDef) -> SceneObject {
        SceneObject(id: id, name: id.rawValue, def: def)
    }
}
