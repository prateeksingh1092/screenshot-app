import FrisketCore
import Testing

@Suite struct CapturePermissionPolicyTests {
    @Test func authorizationRefusalUsesPreflightAndGrantHistoryToChooseRecovery() {
        var staleGrant = CapturePermissionPolicy(hasRequested: false)
        #expect(staleGrant.observe(.preflight(true)) == .granted)
        #expect(staleGrant.observe(.authorizationDenied(preflight: true)) == .needsRelaunch)
        #expect(staleGrant.hasRequested)
        #expect(!staleGrant.canRequest)
        #expect(staleGrant.observe(.preflight(false)) == .needsRelaunch)
        #expect(staleGrant.observe(.preflight(true)) == .needsRelaunch)

        var revoked = CapturePermissionPolicy(hasRequested: false)
        #expect(revoked.observe(.preflight(true)) == .granted)
        #expect(revoked.observe(.authorizationDenied(preflight: false)) == .revokedWhileRunning)
        #expect(revoked.canRequest)
        #expect(revoked.observe(.preflight(true)) == .granted)

        var neverGranted = CapturePermissionPolicy(hasRequested: false)
        #expect(neverGranted.observe(.authorizationDenied(preflight: false)) == .denied)
        #expect(neverGranted.hasRequested)
        var nextProcess = CapturePermissionPolicy(hasRequested: staleGrant.hasRequested)
        #expect(nextProcess.observe(.preflight(true)) == .granted)
    }

    @Test func acceptedButUnusableRequestLatchesUntilANewProcess() {
        var policy = CapturePermissionPolicy(hasRequested: false)
        #expect(policy.observe(.requestCompleted(accepted: true, preflight: false)) == .needsRelaunch)
        #expect(policy.hasRequested)
        #expect(!policy.canRequest)
        #expect(policy.observe(.preflight(true)) == .needsRelaunch)
        #expect(policy.observe(.preflight(false)) == .needsRelaunch)

        var nextProcess = CapturePermissionPolicy(hasRequested: policy.hasRequested)
        #expect(nextProcess.observe(.preflight(true)) == .granted)
        var immediatelyUsable = CapturePermissionPolicy(hasRequested: false)
        #expect(immediatelyUsable.observe(.requestCompleted(accepted: true, preflight: true)) == .granted)
    }

    @Test func existingGrantCanBeRevokedAndRestoredButGrantHistoryIsProcessLocal() {
        var policy = CapturePermissionPolicy(hasRequested: false)
        #expect(policy.observe(.preflight(true)) == .granted)
        #expect(!policy.canRequest)
        #expect(policy.hasRequested)
        #expect(policy.observe(.preflight(false)) == .revokedWhileRunning)
        #expect(policy.canRequest)
        #expect(policy.observe(.preflight(false)) == .revokedWhileRunning)
        #expect(policy.observe(.preflight(true)) == .granted)

        var nextProcess = CapturePermissionPolicy(hasRequested: policy.hasRequested)
        #expect(nextProcess.observe(.preflight(false)) == .denied)
    }

    @Test func requestHistoryDistinguishesFirstUseFromDenialAcrossProcesses() {
        var firstProcess = CapturePermissionPolicy(hasRequested: false)
        #expect(firstProcess.observe(.preflight(false)) == .notAsked)
        #expect(firstProcess.canRequest)
        #expect(firstProcess.observe(.requestCompleted(accepted: false, preflight: false)) == .denied)
        #expect(firstProcess.hasRequested)

        var nextProcess = CapturePermissionPolicy(hasRequested: firstProcess.hasRequested)
        #expect(nextProcess.observe(.preflight(false)) == .denied)
        #expect(nextProcess.canRequest)
    }
}
