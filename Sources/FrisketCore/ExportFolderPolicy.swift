/// Pure policy over filesystem facts. Adapters resolve symlinks, inspect access
/// and ubiquitous-resource flags; this module performs no filesystem operations.
public enum ExportFolderAssessment: Equatable, Sendable {
    case allowed(warnsAboutICloud: Bool)
    case refused(ExportFailure)
}

public enum ExportFolderPolicy {
    public static func assess(folderPath: String, historyRootPath: String, homePath: String,
                              isWritable: Bool, isUbiquitous: Bool, isCaseSensitive: Bool = true) -> ExportFolderAssessment {
        guard folderPath.hasPrefix("/"), historyRootPath.hasPrefix("/"), homePath.hasPrefix("/") else {
            return .refused(.unwritable)
        }
        func normalized(_ path: String) -> [String] {
            components(isCaseSensitive ? path : path.lowercased())
        }
        let folder = normalized(folderPath)
        if folder.starts(with: normalized(historyRootPath)) { return .refused(.insideHistory) }
        guard isWritable else { return .refused(.unwritable) }
        let cloud = normalized(homePath + "/Library/Mobile Documents")
        return .allowed(warnsAboutICloud: isUbiquitous || folder.starts(with: cloud))
    }

    private static func components(_ path: String) -> [String] {
        var result: [String] = []
        for part in path.split(separator: "/") {
            if part == ".." { if !result.isEmpty { result.removeLast() } }
            else if part != "." { result.append(String(part)) }
        }
        return result
    }
}
