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
        s = preprocessInput(s)          // strip iOS auto-punctuation commas
        s = applyMultiTokenRules(s)     // longest-match multi-word rewrites first
        s = applyNATOCollapse(s)        // collapse phonetic sequences → letters
        s = applyPhoneticNormalisation(s)
        s = applyStructuralCleanup(s)
        return s
    }

    // MARK: - Pre-processing

    /// Removes commas that iOS punctuation-prediction inserts inside JTAC
    /// Normalises whitespace only.  Commas are preserved because iOS
    /// addsPunctuation inserts them at natural pause points — those pauses are
    /// exactly the field boundaries in a 9-line brief ("EEL, 090°, 950").
    /// Stripping them would destroy the only positional delimiters the parser
    /// can use to split lines 1-3, 4-6, and 7-9.
    private func preprocessInput(_ input: String) -> String {
        var s = input
        s = s.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
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

        // ── "callsign" mishearings ────────────────────────────────────────────
        ("(?i)\\bgoal\\s+sign\\b",               "callsign",               true),
        ("(?i)\\bcoal\\s+sign\\b",               "callsign",               true),
        ("(?i)\\bcosine\\b",                     "callsign",               true),
        ("(?i)\\bcall\\s+sign\\b",               "callsign",               true),

        // ── Callsign phonetic mishearings ─────────────────────────────────
        ("(?i)\\bpan\\s+are\\b",                 "Panther",  true),
        // STT mishearings of "panther" — none of these have JTAC meaning.
        ("(?i)\\banswer\\b",                      "Panther",  true),
        ("(?i)\\bpuncture\\b",                    "Panther",  true),
        ("(?i)\\bpantera\\b",                     "Panther",  true),
        ("(?i)\\bpanthere\\b",                    "Panther",  true),

        // ── Briefing-point / Battle-position identifiers ──────────────────
        // Full NATO phonetic spelling — must run BEFORE generic NATO collapse.
        // Use [\s,]+ between tokens so that iOS comma-punctuated input like
        // "Bravo, Papa, Echo, Echo, Lima, 2K" is caught correctly.
        ("(?i)\\bbravo[\\s,]+papa[\\s,]+(?:echo|eko)[\\s,]+(?:echo|eko)[\\s,]+lima[\\s,]+2k\\b", "BP EEL 2K", true),
        ("(?i)\\bbravo[\\s,]+papa[\\s,]+(?:echo|eko)[\\s,]+(?:echo|eko)[\\s,]+lima\\b",           "BP EEL",    true),
        ("(?i)\\bBPEEL\\s*2K\\b",               "BP EEL 2K", true),
        ("(?i)\\bB\\s*PEEL\\s*2K\\b",           "BP EEL 2K", true),
        ("(?i)\\bb[ei][\\s,]+peel[\\s,]*2k\\b", "BP EEL 2K", true),
        ("(?i)\\bbravo[\\s,]+papa[\\s,]+eel[\\s,]+2k\\b", "BP EEL 2K", true),
        // Broad catch-all: "B P" + 1–6 garbled/comma-separated tokens + "2K".
        // Handles "B P EK,Ko, Ek, Komatke" → "BP EEL 2K" even without prior
        // comma-stripping (iOS addsPunctuation inserts commas between tokens).
        ("(?i)\\bB[\\s,]+P(?:[\\s,]+[A-Za-z0-9]+){1,6}[\\s,]+2[Kk]\\b", "BP EEL 2K", true),
        ("(?i)\\bBP(?:[\\s,]+[A-Za-z0-9]+){1,6}[\\s,]+2[Kk]\\b",         "BP EEL 2K", true),

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
        ("(?i)\\btype\\s+(1|one|wun)\\s+control\\b",       "type 1 control", true),
        ("(?i)\\btype\\s+(2|two|to)\\s+control\\b",        "type 2 control", true),
        ("(?i)\\btype\\s+(3|three|tree)\\s+control\\b",    "type 3 control", true),
        ("(?i)\\btype\\s+(1|one|wun)\\b",                  "type 1",         true),
        ("(?i)\\btype\\s+(2|two|to)\\b",                   "type 2",         true),
        ("(?i)\\btype\\s+(3|three|tree)\\b",               "type 3",         true),

        // ── Brevity code variants ─────────────────────────────────────────
        ("(?i)\\bcleared\\s+hot\\b",               "cleared hot",     true),
        ("(?i)\\bnot\\s+cleared\\s+hot\\b",        "not cleared hot", true),
        ("(?i)\\bin\\s+hot\\b",                    "in hot",          true),
        ("(?i)\\bin\\s+dry\\b",                    "in dry",          true),
        ("(?i)\\boff\\s+dry\\b",                   "off dry",         true),
        ("(?i)\\bdanger\\s+close\\b",              "danger close",    true),
        ("(?i)\\babort\\s+abort\\s+abort\\b",      "abort abort abort", true),
        // "a board" / "aboard" — common STT mishearing of "abort" in radio comms
        ("(?i)\\ba\\s+board\\b",                   "abort",             true),
        ("(?i)\\baboard\\b",                       "abort",             true),

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

        // ── Procedural-phrase mishearings ─────────────────────────────────
        // "call ready" variants
        ("(?i)\\bcolor\\s+already\\b",              "call ready",             true),
        ("(?i)\\bcolou?r\\s+ready\\b",              "call ready",             true),
        // "checking in when ready" variants
        ("(?i)\\bcheck\\s+on\\s+lady\\b",           "checking in when ready", true),
        ("(?i)\\bcheck\\s+on\\s+when\\s+ready\\b",  "checking in when ready", true),
        ("(?i)\\bcheck\\s+in\\s+when\\s+ready\\b",  "checking in when ready", true),

        // "when ready" standalone
        // "on the rent" is the top STT mishearing of "when ready" in radio context
        ("(?i)\\bon\\s+the\\s+rent\\b",              "when ready",             true),
        ("(?i)\\bwhen\\s+ready\\b",                 "when ready",             true),

        // "situation update" mishearings ─────────────────────────────────
        // iOS hears the letter "A" in auth codes as "8" (both sound like "ay"/"eigh")
        // Cast the net wide: match any garbled form of "update" before "code 8"
        ("(?i)\\bsituation\\s+upd\\w*\\s+code\\s+8\\b", "situation update code alpha", true),
        ("(?i)\\bsituation\\s+update\\s+code\\s+8\\b",  "situation update code alpha", true),
        // Catch a standalone garbled "situatn" / "situate" prefix too
        ("(?i)\\bsituat\\w+\\s+upd\\w+\\b",             "situation update",           true),

        // ── "bomb" ── STT conflates with "bump" in JTAC radio context ─────
        ("(?i)\\bbump\\b",                          "bomb",    true),

        // ── "target" ── STT drops the "-get" syllable → "tart" ────────────
        ("(?i)\\btart\\b",                          "target",  true),
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

    // MARK: - NATO Phonetic Alphabet Collapse

    // Maps each NATO phonetic word (and ALL known STT variants) to its letter.
    // Rule: when a word appears here it ALWAYS becomes its letter unless it is
    // in natoProtectedPhrases.  Variants are sourced from observed iOS STT
    // output on JTAC radio audio.
    private static let natoToLetter: [String: Character] = [
        // A — alpha
        "alpha": "A", "alfa": "A", "alfie": "A", "al-fa": "A",
        // B — bravo
        "bravo": "B",
        // C — charlie
        "charlie": "C", "charley": "C", "charly": "C", "charli": "C",
        // D — delta
        "delta": "D",
        // E — echo
        "echo": "E", "eko": "E",   // "eko" very common iOS variant
        "teko": "E",               // user-reported: "sqarah teko" for "sierra echo"
        "eco": "E",
        // F — foxtrot
        "foxtrot": "F",
        "fox": "F",                // STT splits "foxtrot" → "fox trot"; "fox" → F
        // G — golf
        "golf": "G",
        // H — hotel
        "hotel": "H", "ho-tel": "H",
        // I — india
        "india": "I", "indie": "I", "indy": "I", "india's": "I",
        // J — juliet
        "juliet": "J", "juliett": "J", "julie": "J", "julio": "J",
        // K — kilo
        "kilo": "K", "killo": "K",
        // L — lima
        "lima": "L", "leema": "L",
        // M — mike
        "mike": "M",
        // N — november
        "november": "N", "novem": "N",
        // O — oscar
        "oscar": "O", "oskar": "O", "oscars": "O",
        // P — papa
        "papa": "P", "poppa": "P",
        // Q — quebec
        "quebec": "Q", "kebec": "Q", "kebeck": "Q", "keh-beck": "Q",
        // R — romeo
        "romeo": "R", "romero": "R",   // "romero" = extra syllable added by STT
        // S — sierra
        "sierra": "S",
        "sqarah": "S",   // user-reported: "sqarah teko"
        "sarah": "S",    // user-reported: iOS hears "sierra" as "sarah"
        "sara": "S",     // truncated form
        "saira": "S", "siara": "S", "seera": "S", "siera": "S",
        "seara": "S", "ceara": "S", "see-ara": "S", "sear": "S",
        // T — tango
        "tango": "T",
        // U — uniform
        "uniform": "U", "uni": "U",
        // V — victor
        "victor": "V", "viktor": "V",
        // W — whiskey
        "whiskey": "W", "whisky": "W",
        // X — x-ray
        "xray": "X", "x-ray": "X", "x ray": "X",
        // Y — yankee
        "yankee": "Y",
        // Z — zulu
        "zulu": "Z",
    ]

    // Exact multi-word NATO sequences that are established brevity phrases and
    // must NOT be collapsed to letters.
    private static let natoProtectedPhrases: Set<String> = [
        "lima charlie",   // loud and clear
        "charlie mike",   // continue mission
        "oscar mike",     // on the move
        "tango mike",     // thanks much
    ]

    /// Collapses runs of NATO phonetic words into their letters.
    /// Every NATO word — including single isolated ones — becomes its letter.
    /// e.g.  "alpha"               → "A"
    ///        "bravo papa echo"     → "BPE"
    ///        "lima charlie"        → "lima charlie"  (protected brevity)
    /// Runs after multiTokenRules, before phonetic normalisation.
    private func applyNATOCollapse(_ input: String) -> String {
        let tokens = input.components(separatedBy: " ").filter { !$0.isEmpty }
        var out: [String] = []
        var run: [(original: String, letter: Character)] = []

        func flushRun() {
            defer { run.removeAll() }
            guard !run.isEmpty else { return }

            // Check whether the entire run (or any sub-pair) is a protected phrase.
            let lower = run.map { $0.original.lowercased() }.joined(separator: " ")
            if Self.natoProtectedPhrases.contains(lower) {
                // Preserve original words.
                out.append(contentsOf: run.map { $0.original })
                return
            }

            // For runs of 2+ check each consecutive pair too.
            if run.count >= 2 {
                var i = 0
                while i < run.count {
                    // Try to match a protected pair starting at i.
                    if i + 1 < run.count {
                        let pair = (run[i].original + " " + run[i+1].original).lowercased()
                        if Self.natoProtectedPhrases.contains(pair) {
                            out.append(run[i].original)
                            out.append(run[i+1].original)
                            i += 2
                            continue
                        }
                    }
                    out.append(String(run[i].letter))
                    i += 1
                }
            } else {
                // Single NATO word → its letter.
                out.append(String(run[0].letter))
            }
        }

        for token in tokens {
            let key = token.lowercased()
                .trimmingCharacters(in: .punctuationCharacters)
            if let letter = Self.natoToLetter[key] {
                run.append((original: token, letter: letter))
            } else {
                flushRun()
                out.append(token)
            }
        }
        flushRun()
        return out.joined(separator: " ")
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
