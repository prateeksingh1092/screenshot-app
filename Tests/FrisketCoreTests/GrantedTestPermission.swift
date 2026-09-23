import FrisketCore

struct GrantedTestPermission: CapturePermissionSource {
    func capturePermission() async -> CapturePermissionState { .granted }
}
