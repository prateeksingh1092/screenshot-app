import FrisketCore
import Testing

@Suite struct ExportFolderPolicyTests {
    @Test func folderPolicyRefusesHistoryAndUnwritableDestinationsAndWarnsForICloud() {
        func assess(_ folder: String, writable: Bool = true, ubiquitous: Bool = false) -> ExportFolderAssessment {
            ExportFolderPolicy.assess(folderPath: folder, historyRootPath: "/Users/fixture/History.noindex",
                homePath: "/Users/fixture", isWritable: writable, isUbiquitous: ubiquitous)
        }
        #expect(assess("/Users/fixture/History.noindex") == .refused(.insideHistory))
        #expect(assess("/Users/fixture/History.noindex/images") == .refused(.insideHistory))
        #expect(assess("/Users/fixture/elsewhere/../History.noindex/./images/") == .refused(.insideHistory))
        #expect(assess("/Users/fixture/History.noindex-copy") == .allowed(warnsAboutICloud: false))
        #expect(assess("/Users/fixture/Pictures/Frisket", writable: false) == .refused(.unwritable))
        #expect(assess("/Users/fixture/Library/Mobile Documents/com~apple~CloudDocs/Exports") == .allowed(warnsAboutICloud: true))
        #expect(assess("/Users/fixture/Library/Mobile Documents") == .allowed(warnsAboutICloud: true))
        #expect(assess("/Users/fixture/Library/Mobile Documents-copy") == .allowed(warnsAboutICloud: false))
        #expect(assess("/Volumes/Cloud/Exports", ubiquitous: true) == .allowed(warnsAboutICloud: true))
        #expect(assess("relative/path") == .refused(.unwritable))
    }
}
