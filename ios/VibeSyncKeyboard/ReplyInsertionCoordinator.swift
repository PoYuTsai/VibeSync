import Foundation

enum KeyboardInsertionOutcome: Equatable {
    case inserted
    case alreadyInserted
}

enum KeyboardInsertionError: Error, Equatable {
    case candidateNotPresented
}

final class ReplyInsertionCoordinator {
    private let insertText: (String) -> Void
    private var insertedCandidateKeys = Set<String>()

    init(insertText: @escaping (String) -> Void) {
        self.insertText = insertText
    }

    func insert(
        option: KeyboardAssistOption,
        presentation: KeyboardResultsPresentation,
        context: KeyboardInsertionContext
    ) throws -> KeyboardInsertionOutcome {
        guard presentation.options.contains(option) else {
            throw KeyboardInsertionError.candidateNotPresented
        }
        try presentation.binding.validateForInsertion(
            context: context,
            presentedAt: presentation.presentedAt
        )
        let key = presentation.binding.operationID.uuidString +
            ":" + option.candidateID
        guard !insertedCandidateKeys.contains(key) else {
            return .alreadyInserted
        }

        // This is the sole screenshot-assist path that may reach insertText.
        // Transport callbacks only create KeyboardResultsPresentation values.
        insertText(option.text)
        insertedCandidateKeys.insert(key)
        return .inserted
    }

    func insertLegacy(
        candidateID: String,
        text: String
    ) -> KeyboardInsertionOutcome {
        let key = "legacy:" + candidateID
        guard !insertedCandidateKeys.contains(key) else {
            return .alreadyInserted
        }
        insertText(text)
        insertedCandidateKeys.insert(key)
        return .inserted
    }

}
