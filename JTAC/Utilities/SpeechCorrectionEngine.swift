import Speech
import Foundation

// MARK: - SpeechCorrectionEngine
//
// Post-recognition rule engine that fixes the most common ASR misrecognitions
// in JTAC radio transcripts before the text reaches JTACParser.
//
// Pipeline (applied in order):
//   1. Confidence flagging  — segments below threshold are tagged
//   2. Rule-based rewrite   — exact/regex substitutions (highest-priority rules first)
//   3. Phonetic normalisation — military number words, phonetic alternates
//   4. Structural cleanup   — hyphenation, spacing, case normalisation
//
// All processing is synchronous and fully offline.

// MARK: - CorrectedTranscript

/// Output of the correction engine for one recognition result.
struct CorrectedTranscript {
    /// Fully corrected text, ready for JTACParser.
    let text: String
    /// Segments whose ASR confidence was below `SpeechCorrectionEngine.lowConfidenceThreshold`.
    /// Each tuple: (original word, correction applied or nil, confidence 0–1).
    let lowConfidenceFlags: [(word: String, correction: String?, confidence: Float)]
    /// True if any safety-critical phrase (cleared hot, abort, etc.) was found
    /// in a low-confidence segment — caller should visually flag this to the operator.
    let hasCriticalLowConfidence: Bool
}

// MARK: - SpeechCorrectionEngine

final class SpeechCorrectionEngine {

    // ── Configuration ──────────────────────────────────────────────────────
    /// Segments with confidence below this are flagged.
    static let lowConfidenceThreshold: Float = 0.6

    // ── Singleton ─────────────────────────────────────────────────────────
    static let shared = SpeechCorrectionEngine()
    private init() {}

    // MARK: - Public API

    /// Full pipeline: confidence → rules → phonetics → cleanup.
    /// - Parameter result: The raw SFSpeechRecognitionResult from the recognizer.
    /// - Returns: CorrectedTranscript with clean text and any confidence alerts.
    func correct(_ result: SFSpeechRecognitionResult) -> CorrectedTranscript {
        let segments = result.bestTranscription.segments

        // 1. Confidence pass — identify low-confidence tokens.
        var flags: [(word: String, correction: String?, confidence: Float)] = []
        for seg in segments where seg.confidence < Self.lowConfidenceThreshold {
            // Try to find a rule-based correction for this specific segment.
            let corrected = applySingleTokenRules(seg.substring)
            let correction: String? = (corrected != seg.substring) ? corrected : nil
            flags.append((word: seg.substring, correction: correction, confidence: seg.confidence))
        }

        // 2–4. Apply full rewrite pipeline to the complete transcript string.
        let raw = result.bestTranscription.formattedString
        let corrected = applyFullPipeline(raw)

        // 5. Check whether any flagged segment contains a critical phrase.
        let criticalPhrases: Set<String> = [
            "cleared hot", "not cleared hot", "abort", "abort abort abort",
            "danger close", "hold fire", "cease fire", "in hot",
        ]
        let hasCritical = flags.contains { flag in
            criticalPhrases.contains(where: { flag.word.lowercased().contains($0) })
        }

        return CorrectedTranscript(
            text: corrected,
            lowConfidenceFlags: flags,
            hasCriticalLowConfidence: hasCritical
        )
    }

    /// Lightweight version for live partial results (display only, no flagging).
    func quickCorrect(_ raw: String) -> String {
        applyFullPipeline(raw)
    }

    // MARK: - Pipeline

    private func applyFullPipeline(_ input: String) -> String {
        var s = input
        s = applyMultiTokenRules(s)     // longest-match multi-word rewrites first
        s = applyPhoneticNormalisation(s)
        s = applyStructuralCleanup(s)
        return s
    }

    // MARK: - Rule Sets

    // ── Multi-token rules (ordered longest-first to prevent partial matches) ─

    /// Each entry: (pattern, replacement, isRegex)
    /// Ordered from most-specific to least-specific.
    private let multiTokenRules: [(pattern: String, replacement: String, isRegex: Bool)] = [

        // ── Callsign mishearings ───────────────────────────────────────────
        ("asked man",           "Axeman",       false),
        ("X-men",               "Axeman",       false),
        ("Xmen",                "Axeman",       false),
        ("x-men",               "Axeman",       false),
        ("xmen",                "Axeman",       false),
        ("Axman",               "Axeman",       false),
        ("axman",               "Axeman",       false),
        ("Haug",                "Hawg",         false),
        ("haug",                "Hawg",         false),
        ("Hogg",                "Hawg",         false),
        ("hogg",                "Hawg",         false),
        ("Sabre",               "Saber",        false),

        // ── Quantity / "N by weapon" fusions ──────────────────────────────
        // "Dubai" is the top STT fusion of "two by" — highest priority.
        ("(?i)\\bDubai\\b",                        "2x",    true),
        ("(?i)\\bdo\\s+bu[yi]\\b",                 "2x",    true),
        ("(?i)\\b(one|1)\\s+by\\b",                "1x",    true),
        ("(?i)\\b(two|2)\\s+by\\b",                "2x",    true),
        ("(?i)\\b(three|3)\\s+by\\b",              "3x",    true),
        ("(?i)\\b(four|4)\\s+by\\b",               "4x",    true),
        ("(?i)\\b(six|6)\\s+by\\b",                "6x",    true),
        ("(?i)\\b(eight|8)\\s+by\\b",              "8x",    true),

        // ── Mike-mike (with and without hyphen) ───────────────────────────
        ("(?i)\\bmike\\s+mike\\b",                 "mike-mike", true),

        // ── Nine-line triggers ─────────────────────────────────────────────
        ("(?i)\\bniner\\s+line\\b",                "nine line",  true),
        ("(?i)\\b9\\s+line\\b",                    "nine line",  true),
        ("(?i)\\bnine\\s+liner\\b",                "nine line",  true),
        ("(?i)\\bnine-line\\b",                    "nine line",  true),

        // ── CAS type variants ─────────────────────────────────────────────
        ("(?i)\\btype\\s+(1|one)\\s+control\\b",   "type 1 control", true),
        ("(?i)\\btype\\s+(2|two)\\s+control\\b",   "type 2 control", true),
        ("(?i)\\btype\\s+(3|three)\\s+control\\b", "type 3 control", true),
        ("(?i)\\btype\\s+(1|one)\\b",              "type 1", true),
        ("(?i)\\btype\\s+(2|two)\\b",              "type 2", true),
        ("(?i)\\btype\\s+(3|three)\\b",            "type 3", true),

        // ── Brevity code variants ─────────────────────────────────────────
        ("(?i)\\bcleared\\s+hot\\b",               "cleared hot",     true),
        ("(?i)\\bnot\\s+cleared\\s+hot\\b",        "not cleared hot", true),
        ("(?i)\\bin\\s+hot\\b",                    "in hot",          true),
        ("(?i)\\bin\\s+dry\\b",                    "in dry",          true),
        ("(?i)\\boff\\s+dry\\b",                   "off dry",         true),
        ("(?i)\\bdanger\\s+close\\b",              "danger close",    true),
        ("(?i)\\babort\\s+abort\\s+abort\\b",      "abort abort abort", true),

        // ── BDA ───────────────────────────────────────────────────────────
        ("(?i)\\bb\\.?d\\.?a\\.?\\b",             "BDA",    true),
        ("(?i)\\bbattle\\s+damage\\s+assessment\\b","BDA complete", true),
        ("(?i)\\bsplash\\s+out\\b",               "splash", true),

        // ── smoke colours ─────────────────────────────────────────────────
        ("(?i)\\bpop\\s+smoke\\b",                "pop smoke", true),

        // ── Radio procedure ───────────────────────────────────────────────
        ("(?i)\\bbreak\\s+break\\b",              "break break",   true),
        ("(?i)\\bsay\\s+again\\b",                "say again",     true),
        ("(?i)\\bhow\\s+copy\\b",                 "how copy",      true),
        ("(?i)\\bgood\\s+copy\\b",                "good copy",     true),
        ("(?i)\\blima\\s+charlie\\b",             "lima charlie",  true),
        ("(?i)\\bloud\\s+and\\s+clear\\b",        "loud and clear",true),
        ("(?i)\\bstand\\s+by\\b",                 "standby",       true),
        ("(?i)\\bwill\\s+co\\b",                  "wilco",         true),
    ]

    private func applyMultiTokenRules(_ input: String) -> String {
        var s = input
        for rule in multiTokenRules {
            if rule.isRegex {
                s = s.replacingOccurrences(
                    of: rule.pattern, with: rule.replacement,
                    options: [.regularExpression, .caseInsensitive])
            } else {
                s = s.replacingOccurrences(of: rule.pattern, with: rule.replacement)
            }
        }
        return s
    }

    // ── Single-token rules (used for per-segment confidence correction) ────

    private let singleTokenRules: [(String, String)] = [
        ("wun",   "one"),
        ("Wun",   "one"),
        ("fife",  "five"),
        ("Fife",  "five"),
        ("niner", "9"),
        ("tree",  "3"),
    ]

    private func applySingleTokenRules(_ token: String) -> String {
        for (from, to) in singleTokenRules {
            if token == from { return to }
        }
        return token
    }

    // MARK: - Phonetic Normalisation

    // Number words that should only be converted to digits when standing alone
    // (i.e. part of a code, not a phrase like "line one").
    // We leave word-form numbers intact so JTACParser can still handle them.
    private func applyPhoneticNormalisation(_ input: String) -> String {
        var s = input

        // ── "to" → "two" only when between number words ──────────────────
        // e.g. "Hawg one to one" → "Hawg one two one"
        let numberWord = "(?:one|two|three|four|five|fife|six|seven|eight|nine|niner|zero|wun|tree)"
        let toFix = "(?i)(\(numberWord))\\s+to\\s+(\(numberWord))"
        s = s.replacingOccurrences(of: toFix, with: "$1 two $2",
                                   options: .regularExpression)

        // ── Wun → one (missed by multi-token pass in some contexts) ──────
        s = s.replacingOccurrences(
            of: "(?i)\\bwun\\b", with: "one", options: .regularExpression)

        // ── Fife → five ───────────────────────────────────────────────────
        s = s.replacingOccurrences(
            of: "(?i)\\bfife\\b", with: "five", options: .regularExpression)

        return s
    }

    // MARK: - Structural Cleanup

    private func applyStructuralCleanup(_ input: String) -> String {
        var s = input

        // Normalise ordnance designator spacing: "GBU 12" → "GBU-12"
        s = s.replacingOccurrences(
            of: "(?i)\\b(GBU|MK|Mk)\\s+(\\d+)", with: "$1-$2",
            options: .regularExpression)

        // Aircraft designator: "A 10" → "A-10", "F 16" → "F-16"
        s = s.replacingOccurrences(
            of: "(?i)\\b([A-Z])\\s+(\\d{2,3}[A-Z]?)\\b", with: "$1-$2",
            options: .regularExpression)

        // Collapse multiple spaces
        s = s.replacingOccurrences(
            of: "\\s{2,}", with: " ", options: .regularExpression)

        return s.trimmingCharacters(in: .whitespaces)
    }
}
