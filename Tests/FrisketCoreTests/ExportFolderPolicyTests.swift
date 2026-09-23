import Foundation
import FrisketCore
import Testing

@Suite struct ExportFolderPolicyTests {
    @Test(arguments: ["io.github.prateeksingh1092.frisket", "io.github.prateeksingh1092.frisket.debug"])
    func refusesAnotherBuildsRelocatedHistory(bundle: String) throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let bundleFolder = home.appendingPathComponent("Library/Application Support/" + bundle)
        let relocated = home.appendingPathComponent("RelocatedHistory")
        try FileManager.default.createDirectory(at: bundleFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: relocated, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: bundleFolder.appendingPathComponent("History.noindex"),
                                                   withDestinationURL: relocated)
        #expect(PNGFileExporter.assess(folder: relocated.appendingPathComponent("exports/new"),
            historyRoot: home.appendingPathComponent("current/History.noindex"), home: home) == .refused(.insideHistory))
    }

    @Test(arguments: [false, true])
    func refusesHistoryThroughDataVolumeAliases(rootExists: Bool) throws {
        let home = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let alias = URL(fileURLWithPath: "/System/Volumes/Data" + home.path)
        #expect(FileManager.default.fileExists(atPath: alias.path))
        for bundle in ["io.github.prateeksingh1092.frisket", "io.github.prateeksingh1092.frisket.debug"] {
            let relative = "Library/Application Support/\(bundle)/History.noindex"
            let root = home.appendingPathComponent(relative)
            if rootExists { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
            for suffix in ["", "/exports/new"] {
                #expect(PNGFileExporter.assess(folder: alias.appendingPathComponent(relative + suffix),
                    historyRoot: home.appendingPathComponent("current/History.noindex"), home: home) == .refused(.insideHistory))
            }
            #expect(PNGFileExporter.assess(folder: alias.appendingPathComponent(relative + "-copy"),
                historyRoot: root, home: home) == .allowed(warnsAboutICloud: false))
        }
    }

    @Test(arguments: ["io.github.prateeksingh1092.frisket", "io.github.prateeksingh1092.frisket.debug"])
    func refusesEveryBuildsHistory(bundle: String) {
        let root = "/Users/fixture/Library/Application Support/\(bundle)/History.noindex"
        for folder in [root, root + "/exports/new"] {
            #expect(ExportFolderPolicy.assess(folderPath: folder,
                historyRootPath: "/Users/fixture/current-build/History.noindex", homePath: "/Users/fixture",
                isWritable: true, isUbiquitous: false) == .refused(.insideHistory))
        }
        #expect(ExportFolderPolicy.assess(folderPath: root + "-copy",
            historyRootPath: "/Users/fixture/current-build/History.noindex", homePath: "/Users/fixture",
            isWritable: true, isUbiquitous: false) == .allowed(warnsAboutICloud: false))
    }

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
