import CoreGraphics
import Foundation
import FoundationModels
import GrimoireCore
import Observation

/// On-device intelligence built on Apple's Foundation Models framework: whether it can run
/// here, which model a request goes to, and streaming text or typed results back.
///
/// Requests run on the on-device model. A prompt too long for it goes to Private Cloud
/// Compute only when the user allowed that in Settings; otherwise it's refused with
/// `IntelligenceError.tooLong` so the caller can work in smaller pieces.
@MainActor @Observable
public final class IntelligenceService {
    public static let shared = IntelligenceService()

    private let preferences: Preferences
    /// Bumped by `refresh()` so views reading `status` look again.
    private var revision = 0

    public init(preferences: Preferences = .shared) {
        self.preferences = preferences
    }

    /// Whether AI features can run for `project`, and if not, why.
    public func status(for project: Project?) -> IntelligenceStatus {
        _ = revision
        guard preferences.intelligenceEnabled else { return .turnedOff }
        guard preferences.intelligenceEnabled(for: project) else { return .turnedOffForProject }
        return Self.modelStatus
    }

    public func isAvailable(for project: Project?) -> Bool {
        status(for: project) == .ready
    }

    /// Looks at the model's availability again (it changes as Apple Intelligence downloads
    /// or is switched on).
    public func refresh() {
        revision += 1
    }

    nonisolated static var modelStatus: IntelligenceStatus {
        switch SystemLanguageModel.default.availability {
        case .available: .ready
        case .unavailable(.deviceNotEligible): .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled): .appleIntelligenceOff
        case .unavailable(.modelNotReady): .downloading
        case .unavailable: .deviceNotEligible
        }
    }

    // MARK: - Routing

    /// Tokens kept free for the response when deciding whether a prompt fits.
    public static let responseReserve = 1_200

    /// Where a request of `tokens` prompt tokens can run: on-device when it fits, Private
    /// Cloud Compute when it doesn't and the user allowed it.
    public func route(forTokens tokens: Int) async throws -> ModelRoute {
        if tokens + Self.responseReserve <= SystemLanguageModel.default.contextSize { return .onDevice }
        guard preferences.allowsPrivateCloud else { throw IntelligenceError.tooLong }
        let cloud = PrivateCloudComputeLanguageModel()
        guard case .available = cloud.availability else { throw IntelligenceError.cloudUnavailable }
        let cloudContext = (try? await cloud.contextSize) ?? 32_000
        guard tokens + Self.responseReserve <= cloudContext else { throw IntelligenceError.tooLong }
        return .privateCloud
    }

    /// How many tokens the on-device model counts in `text`.
    public func tokenCount(_ text: String) async -> Int {
        (try? await SystemLanguageModel.default.tokenCount(for: text)) ?? text.utf8.count / 3
    }

    /// The on-device model's context window, in tokens.
    public var contextSize: Int { SystemLanguageModel.default.contextSize }

    // MARK: - Requests

    /// Streams the response to `request` as the whole text so far, each element longer
    /// than the last. Cancelling the consuming task stops generation.
    public func stream(_ request: IntelligenceRequest) -> AsyncThrowingStream<String, Error> {
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        let task = Task { @MainActor in
            do {
                let session = try await self.session(for: request)
                let options = GenerationOptions(temperature: request.temperature)
                let responses = session.streamResponse(options: options) { request.prompt(includingImages: true) }
                for try await snapshot in responses {
                    try Task.checkCancellation()
                    continuation.yield(snapshot.content)
                }
                continuation.finish()
            } catch is CancellationError {
                continuation.finish()
            } catch {
                continuation.finish(throwing: IntelligenceError(error))
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    /// The whole response to `request` as plain text.
    public func respond(_ request: IntelligenceRequest) async throws -> String {
        var last = ""
        for try await text in stream(request) { last = text }
        return last
    }

    /// A typed result, using guided generation.
    public func generate<Content: Generable>(_ type: Content.Type, for request: IntelligenceRequest) async throws
        -> Content
    {
        do {
            let session = try await session(for: request)
            let options = GenerationOptions(temperature: request.temperature)
            let response = try await session.respond(generating: type, options: options) {
                request.prompt(includingImages: true)
            }
            return response.content
        } catch {
            throw IntelligenceError(error)
        }
    }

    private func session(for request: IntelligenceRequest) async throws -> LanguageModelSession {
        guard Self.modelStatus == .ready else { throw IntelligenceError.unavailable(Self.modelStatus) }
        let route: ModelRoute
        if let forced = request.route {
            route = forced
        } else {
            route = try await self.route(forTokens: await tokenCount(request.instructions + "\n" + request.text))
        }
        switch route {
        case .onDevice:
            return LanguageModelSession(
                model: SystemLanguageModel.default, tools: request.tools, instructions: request.instructions)
        case .privateCloud:
            return LanguageModelSession(
                model: PrivateCloudComputeLanguageModel(), tools: request.tools, instructions: request.instructions)
        }
    }
}

/// Which model a request runs on.
public enum ModelRoute: Sendable, Equatable {
    case onDevice
    /// Apple's Private Cloud Compute, only when the user allowed it.
    case privateCloud
}

/// What to ask the model.
public struct IntelligenceRequest: @unchecked Sendable {
    public var instructions: String
    public var text: String
    public var images: [CGImage]
    public var tools: [any Tool]
    public var temperature: Double?
    /// Forces a model; nil picks one by length.
    public var route: ModelRoute?

    public init(
        instructions: String, text: String, images: [CGImage] = [], tools: [any Tool] = [],
        temperature: Double? = nil, route: ModelRoute? = nil
    ) {
        self.instructions = instructions
        self.text = text
        self.images = images
        self.tools = tools
        self.temperature = temperature
        self.route = route
    }

    func prompt(includingImages: Bool) -> Prompt {
        Prompt {
            text
            if includingImages {
                for image in images { Attachment(image) }
            }
        }
    }
}

/// Whether the AI features can run, and what to tell the user when they can't.
public enum IntelligenceStatus: Equatable, Sendable {
    case ready
    case turnedOff
    case turnedOffForProject
    case deviceNotEligible
    case appleIntelligenceOff
    case downloading

    /// A plain explanation for Settings and disabled menu items; nil when ready.
    public var message: String? {
        switch self {
        case .ready: nil
        case .turnedOff: String(localized: "Intelligence is turned off in Settings.")
        case .turnedOffForProject: String(localized: "Intelligence is turned off for this project.")
        case .deviceNotEligible: String(localized: "This Mac can't run Apple Intelligence.")
        case .appleIntelligenceOff:
            String(localized: "Turn on Apple Intelligence in System Settings to use these features.")
        case .downloading: String(localized: "Apple Intelligence is still downloading. Try again in a little while.")
        }
    }
}

/// Why a request failed, in plain words.
public enum IntelligenceError: LocalizedError, Equatable {
    case unavailable(IntelligenceStatus)
    case tooLong
    case cloudUnavailable
    case refused
    case unsupportedLanguage
    case busy
    case failed(String)

    init(_ error: Error) {
        if let error = error as? IntelligenceError {
            self = error
            return
        }
        if let error = error as? LanguageModelError {
            switch error {
            case .contextSizeExceeded: self = .tooLong
            case .guardrailViolation, .refusal: self = .refused
            case .unsupportedLanguageOrLocale: self = .unsupportedLanguage
            case .rateLimited: self = .busy
            default: self = .failed(error.localizedDescription)
            }
            return
        }
        self = .failed(error.localizedDescription)
    }

    public var errorDescription: String? {
        switch self {
        case .unavailable(let status): status.message
        case .tooLong:
            String(
                localized:
                    // swiftlint:disable:next line_length
                    "This is too long for the on-device model. Try a shorter selection, or allow Private Cloud Compute in Settings."
            )
        case .cloudUnavailable: String(localized: "Private Cloud Compute isn't available right now.")
        case .refused: String(localized: "The model declined to answer that.")
        case .unsupportedLanguage: String(localized: "The model doesn't support this language yet.")
        case .busy: String(localized: "The model is busy. Try again in a moment.")
        case .failed(let message): message
        }
    }
}
