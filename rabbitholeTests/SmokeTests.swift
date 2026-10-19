import Testing
@testable import rabbithole

struct SmokeTests {
    @Test func appModuleLoads() {
        #expect(Bool(true))
    }
}
