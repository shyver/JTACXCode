import Speech
import Foundation

// MARK: - JTACLanguageModel (deprecated shim)
//
// Points old references to CustomLanguageModelBuilder.

@available(iOS 17, *)
@available(*, deprecated, renamed: "CustomLanguageModelBuilder")
typealias JTACLanguageModel = _JTACLanguageModelStub

@available(iOS 17, *)
final class _JTACLanguageModelStub {
    static let shared = _JTACLanguageModelStub()
    private init() {}

    var configuration: SFSpeechLanguageModel.Configuration? {
        get async { await CustomLanguageModelBuilder.shared.configuration(for: .general) }
    }

    func prepare() async {
        await CustomLanguageModelBuilder.shared.prepare(phase: .general)
    }
}
