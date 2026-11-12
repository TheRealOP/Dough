import Foundation
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Answers questions about spending with Apple's on-device language model (iOS 26+).
@MainActor @Observable final class SpendingAnalyst {
    private(set) var answer = ""
    private(set) var isWorking = false
    private(set) var errorMessage: String?

    /// nil when the on-device model can be used; otherwise a short user-facing reason.
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(.deviceNotEligible):
                return "This iPhone doesn't support Apple Intelligence, so Ask Dough isn't available."
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Turn on Apple Intelligence in Settings to use Ask Dough."
            case .unavailable(.modelNotReady):
                return "The on-device model is still downloading. Try again later."
            case .unavailable:
                return "The on-device model isn't available right now."
            }
        }
        #endif
        return "Ask Dough needs iOS 26 or later on an Apple Intelligence-capable iPhone."
    }

    /// Asks the model about `context`. A nil question requests a general analysis.
    func ask(_ question: String?, context: String) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        answer = ""
        defer { isWorking = false }

        let task: String
        if let question, !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            task = "Answer this question about my spending: \(question)"
        } else {
            task = "Give me a general analysis of my spending this period."
        }
        let prompt = "My spending data:\n\n\(context)\n\n\(task)"

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            do {
                answer = try await Self.respond(to: prompt)
            } catch {
                errorMessage = "Couldn't analyze your spending: \(error.localizedDescription)"
            }
            return
        }
        #endif
        errorMessage = Self.unavailableReason ?? "The on-device model isn't available."
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func respond(to prompt: String) async throws -> String {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt)
        return response.content
    }
    #endif

    private static let instructions = """
        You are Dough, a friendly, non-judgmental personal-finance helper. \
        Use ONLY the spending data provided. Never invent numbers, merchants or items; \
        if the data doesn't answer the question, say so. \
        For a general analysis give 3 or 4 short observations (where the money went, \
        what changed compared with the previous period, anything unusual, using the \
        user's tags and notes to explain it) followed by 1 or 2 practical suggestions. \
        Keep it brief. Reply in plain text with no markdown tables.
        """
}
