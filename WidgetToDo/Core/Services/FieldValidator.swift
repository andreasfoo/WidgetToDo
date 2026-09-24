import Foundation

public enum DataSourceKind: String, Codable, Sendable {
    case tasks
    case journal
}

public struct ValidationIssue: Equatable, Sendable, Identifiable {
    public let id = UUID()
    public let message: AppMessage

    public init(_ key: AppText.Key, arguments: [String] = []) {
        message = AppMessage(key, arguments: arguments)
    }
}

public enum ResolvedDatabaseFields: Equatable, Sendable {
    case tasks(TaskDatabaseFieldMapping)
    case journal(JournalDatabaseFieldMapping)
}

public enum FieldResolution: Equatable, Sendable {
    case success(ResolvedDatabaseFields)
    case failure([ValidationIssue])
}

public enum FieldValidator {
    public static func resolve(_ properties: [NotionPropertySchema], for kind: DataSourceKind) -> FieldResolution {
        switch kind {
        case .tasks:
            return resolveTasks(properties)
        case .journal:
            return resolveJournal(properties)
        }
    }

    private static func resolveTasks(_ properties: [NotionPropertySchema]) -> FieldResolution {
        var issues: [ValidationIssue] = []
        let title = resolveRequiredField(in: properties, type: "title", issues: &issues)
        let date = resolveRequiredField(in: properties, type: "date", issues: &issues)
        let checkboxFields = properties.filter { $0.type == "checkbox" }
        let statusFields = properties.filter { $0.type == "status" && $0.completedStatusName != nil }
        let completionFields = checkboxFields.map { ($0, TaskDoneFieldType.checkbox) } + statusFields.map { ($0, TaskDoneFieldType.status) }
        guard completionFields.count == 1 else {
            issues.append(ValidationIssue(.missingRequiredFieldType, arguments: ["checkbox or status"])); return .failure(issues)
        }
        guard let title, let date, issues.isEmpty else { return .failure(issues) }
        let (doneField, doneType) = completionFields[0]

        let priorityCandidates = properties.filter { $0.type == "select" }
        let estimatedMinutesCandidates = propertyNames(in: properties, matching: "number")
        let mapping = TaskDatabaseFieldMapping(
            title: title,
            date: date,
            done: doneField.name,
            doneType: doneType,
            completedStatusName: doneField.completedStatusName,
            priority: priorityCandidates.count == 1 ? priorityCandidates[0].name : nil,
            priorityOptions: priorityCandidates.count == 1 ? priorityCandidates[0].selectOptions : [],
            estimatedMinutes: estimatedMinutesCandidates.count == 1 ? estimatedMinutesCandidates[0] : nil
        )
        return .success(.tasks(mapping))
    }

    private static func resolveJournal(_ properties: [NotionPropertySchema]) -> FieldResolution {
        var issues: [ValidationIssue] = []
        let title = resolveRequiredField(in: properties, type: "title", issues: &issues)
        let date = resolveRequiredField(in: properties, type: "date", issues: &issues)

        guard let title, let date, issues.isEmpty else {
            return .failure(issues)
        }

        return .success(.journal(JournalDatabaseFieldMapping(title: title, date: date)))
    }

    private static func resolveRequiredField(
        in properties: [NotionPropertySchema],
        type: String,
        issues: inout [ValidationIssue]
    ) -> String? {
        let candidates = propertyNames(in: properties, matching: type)
        switch candidates.count {
        case 0:
            issues.append(ValidationIssue(.missingRequiredFieldType, arguments: [type]))
            return nil
        case 1:
            return candidates[0]
        default:
            issues.append(
                ValidationIssue(
                    .duplicateRequiredField,
                    arguments: [type, candidates.joined(separator: ", "), type]
                )
            )
            return nil
        }
    }

    private static func propertyNames(in properties: [NotionPropertySchema], matching type: String) -> [String] {
        properties.compactMap { property in
            property.type == type ? property.name : nil
        }
    }
}
