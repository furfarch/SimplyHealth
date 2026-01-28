import Testing
@testable import PurusHealth

struct CloudDefaultOffTests {
    @Test func newMedicalRecordIsLocalOnlyByDefault() async throws {
        let r = MedicalRecord()
        #expect(r.isCloudEnabled == false)
        #expect(r.isSharingEnabled == false)
        #expect(r.cloudRecordName == nil)
        #expect(r.cloudShareRecordName == nil)
        #expect(r.locationStatus == .local)
    }
}
