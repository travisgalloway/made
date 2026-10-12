import Testing
import Foundation
@testable import MadeCore

@Suite struct FaultInjectingKernelClientTests {
    private let params = BoxParams(width: 20, depth: 30, height: 40)

    private func makeClient() -> FaultInjectingKernelClient {
        FaultInjectingKernelClient(wrapping: KernelClient(debounceDuration: .milliseconds(5)))
    }

    @Test func nextRequestFailsWithInjectedCode() async {
        let client = makeClient()
        await client.failNextRequest(with: .invalidParams)
        let jobId = JobId("job-forced")

        let result = await client.request(.makeBox(jobId: jobId, solidId: SolidId("box-test"), params: params))

        #expect(result.error?.code == .invalidParams)
        #expect(result.jobId == jobId)
    }

    @Test func injectionIsOneShot() async {
        let client = makeClient()
        await client.failNextRequest(with: .geometryFailed)
        let solidId = SolidId("box-test")

        let first = await client.request(.makeBox(jobId: JobId("job-1"), solidId: solidId, params: params))
        let second = await client.request(.makeBox(jobId: JobId("job-2"), solidId: solidId, params: params))

        #expect(first.error?.code == .geometryFailed)
        #expect(second.isSuccess)
        #expect(second.value?.triangleCount == 12)
    }

    @Test func forwardsWithoutInjection() async {
        let client = makeClient()

        let result = await client.request(.makeBox(jobId: JobId("job-1"), solidId: SolidId("box-test"), params: params))

        #expect(result.isSuccess)
        #expect(await client.getStats().completed == 1)
    }
}
