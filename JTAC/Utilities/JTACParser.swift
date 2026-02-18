import Foundation

// MARK: - JTACParser
// Stateful, fully-offline parser.
// Call process(segment:) for each completed transcript segment.
// The published `report` updates in place as new data arrives.

class JTACParser: ObservableObject {

    @Published var report = JTACReport()

    // Tracks which section most recently opened — new segments without an
    // explicit keyword are appended to the current section.
    private var currentSection: Section = .unknown

    private enum Section {
        case unknown
        case cas
        case situationUpdate
        case nineLine
        case remarks
        case restrictions
        case bda
        case gamePlan
    }

    // MARK: - Public API

    /// Feed each completed transcript segment here.
    func process(segment: String) {
        guard !segment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Normalize first — fix common STT mis-recognitions before parsing.
        let normalized = normalize(segment)

        // Stage 1 — hard-split on radio procedure boundaries ("break break",
        // end-of-keying words followed by new content, callsign re-address).
        // This separates back-to-back transmissions captured in one audio blob.
        let transmissions = presplit(normalized)

        for transmission in transmissions {
            // Stage 2 — split each transmission on every section keyword.
            let chunks = splitIntoChunks(transmission)

            for chunk in chunks {
                if let section = chunk.section {
                    // Explicit keyword → always route there.
                    transition(to: section, trailing: chunk.trailing, fullSegment: chunk.text)
                } else if let inferred = inferSection(for: chunk.text) {
                    // No keyword but strong content signals → infer the section.
                    transition(to: inferred, trailing: chunk.text, fullSegment: chunk.text)
                } else {
                    // True continuation or noise → append to current section.
                    appendToCurrentSection(chunk.text)
                }
            }

            // After each discrete transmission: if the last chunk was keywordless
            // AND had no inferable section, reset so the next transmission cannot
            // accidentally continue into this one's section.
            let lastChunk = chunks.last
            if lastChunk?.section == nil && inferSection(for: lastChunk?.text ?? "") == nil {
                currentSection = .unknown
            }
        }
    }

    /// Wipe all parsed data and reset state.
    func reset() {
        report  = JTACReport()
        currentSection = .unknown
    }

    // MARK: - Pre-Splitting on Radio Procedure Boundaries

    /// Splits `text` into discrete transmission units before section keyword
    /// detection runs. Catches cases where a single audio capture contains
    /// multiple distinct back-to-back radio transmissions.
    ///
    /// Boundaries detected (in priority order):
    ///  1. "break break" — explicit inter-transmission separator
    ///  2. "over" / "out" followed by ≥10 chars of new content
    ///  3. Callsign pattern (word + digits + comma) reappearing mid-segment
    private func presplit(_ text: String) -> [String] {

        // ── 1. Hard split on "break break" ──────────────────────────────────
        let lowerText = text.lowercased()
        if lowerText.contains("break break") {
            // Reconstruct split points case-insensitively by scanning the original.
            var parts: [String] = []
            var remaining = text
            let marker = "break break"
            while let range = remaining.lowercased().range(of: marker) {
                let before = String(remaining[remaining.startIndex..<range.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
                if !before.isEmpty { parts.append(before) }
                remaining = String(remaining[range.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
            }
            if !remaining.isEmpty { parts.append(remaining) }
            if parts.count > 1 { return parts.flatMap { presplit($0) } }
        }

        // ── 2. Split after "over" / "out" when followed by substantial content ─
        // Require at least ~10 chars after the procedure word to avoid splitting
        // on a trailing "over" with nothing meaningful following.
        let eoPattern = #"(?i)\b(over|out)\b(\s+)(?=\S{3}.{6,})"#
        if let regex = try? NSRegularExpression(pattern: eoPattern) {
            let ns = text as NSString
            let all = NSRange(location: 0, length: ns.length)
            let matches = regex.matches(in: text, range: all)
            if !matches.isEmpty {
                var parts: [String] = []
                var lastEnd = text.startIndex
                for match in matches {
                    // Split point = end of the whitespace capture group
                    let splitOffset = match.range(at: 2).upperBound
                    guard splitOffset <= ns.length else { continue }
                    let splitIdx = text.index(text.startIndex,
                                              offsetBy: splitOffset,
                                              limitedBy: text.endIndex) ?? text.endIndex
                    let piece = String(text[lastEnd..<splitIdx])
                        .trimmingCharacters(in: .whitespaces)
                    if !piece.isEmpty { parts.append(piece) }
                    lastEnd = splitIdx
                }
                let tail = String(text[lastEnd...]).trimmingCharacters(in: .whitespaces)
                if !tail.isEmpty { parts.append(tail) }
                if parts.count > 1 { return parts.flatMap { presplit($0) } }
            }
        }

        // ── 3. Callsign re-address — word(s) + digits + comma not at position 0 ─
        // e.g. "…copy. Viper 1-1, standby for nine line" → split before "Viper 1-1,"
        let csPattern = #"(?<=\s)([A-Za-z]+(?:\s[A-Za-z]+)?\s\d[\d-]*\s*,\s*)"#
        if let regex = try? NSRegularExpression(pattern: csPattern) {
            let ns = text as NSString
            let all = NSRange(location: 0, length: ns.length)
            let matches = regex.matches(in: text, range: all)
            if !matches.isEmpty {
                var parts: [String] = []
                var lastEnd = text.startIndex
                for match in matches {
                    guard match.range.lowerBound > 0 else { continue }
                    let splitIdx = text.index(text.startIndex,
                                              offsetBy: match.range.lowerBound,
                                              limitedBy: text.endIndex) ?? text.endIndex
                    let piece = String(text[lastEnd..<splitIdx])
                        .trimmingCharacters(in: .whitespaces)
                    if !piece.isEmpty { parts.append(piece) }
                    lastEnd = splitIdx
                }
                let tail = String(text[lastEnd...]).trimmingCharacters(in: .whitespaces)
                if !tail.isEmpty { parts.append(tail) }
                if parts.count > 1 { return parts }
            }
        }

        return [text]
    }

    // MARK: - Content-Based Section Inference

    // Each indicator is assigned a weight:
    //   3 — unique to this section; near-conclusive on its own
    //   2 — strong signal; rarely appears outside this section
    //   1 — weak / shared; contributes only when combined with other signals
    //
    // A section wins when its total score reaches the threshold AND beats all
    // other sections. The current section gets a tie-breaking bonus so that
    // genuine continuations stay put.
    private let inferThreshold = 3

    /// Scores and returns the most likely section for `text`, or nil when
    /// no section reaches the confidence threshold.
    private func inferSection(for text: String) -> Section? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let lower = text.lowercased()

        var scores: [Section: Int] = [
            .cas:            scoreCAS(lower),
            .situationUpdate: scoreSitrep(lower),
            .nineLine:       scoreNineLine(lower),
            .bda:            scoreBDA(lower),
            .remarks:        scoreRemarks(lower),
            .restrictions:   scoreRestrictions(lower),
            .gamePlan:       scoreGamePlan(lower),
        ]

        // Continuation bonus: current section gets +1 to break ties toward staying.
        if currentSection != .unknown {
            scores[currentSection, default: 0] += 1
        }

        guard let best = scores.max(by: { $0.value < $1.value }),
              best.value >= inferThreshold else { return nil }

        // If .remarks wins AND we are currently in .nineLine, it could be a
        // post-brief clearance phrase — return .remarks to close the 9-line context.
        return best.key
    }

    // ── CAS Check-In ──────────────────────────────────────────────────────────
    private func scoreCAS(_ lower: String) -> Int {
        var score = 0
        // High-confidence unique indicators
        let strong = ["checking in", "check in", "on station",
                      "playtime", "abort criteria", "abort code",
                      "type one control", "type two control", "type three control",
                      "type 1 control",   "type 2 control",   "type 3 control"]
        for t in strong where lower.contains(t) { score += 3 }

        // Platform/ordnance → strongly implies a check-in brief
        let platforms = ["a-10", "f-16", "f-18", "f/a-18", "f-15", "b-52", "b-1",
                         "ah-64", "ac-130", "mq-9", "reaper", "apache",
                         "warthog", "hawg", "viper", "hornet"]
        for p in platforms where lower.contains(p) { score += 2 }

        let ordnance = ["gbu-12", "gbu-31", "gbu-38", "gbu-54", "jdam", "paveway",
                        "hellfire", "brimstone", "apkws",
                        "twenty mike mike", "thirty mike mike",
                        "mk-82", "mk-83", "mk-84"]
        for o in ordnance where lower.contains(o) { score += 2 }

        // Crew/formation hints
        let formation = ["two ship", "four ship", "single ship", "flight of",
                         "dual ship", "two-ship"]
        for f in formation where lower.contains(f) { score += 2 }

        // Weaker shared terms
        let weak = ["type one", "type two", "type three", "requesting", "request cas"]
        for t in weak where lower.contains(t) { score += 1 }

        return score
    }

    // ── Situation Update / SITREP ─────────────────────────────────────────────
    private func scoreSitrep(_ lower: String) -> Int {
        var score = 0
        let strong = ["troops in contact", "contact report",
                      "taking fire", "receiving fire", "under fire",
                      "small arms fire", "machine gun fire",
                      "ied", "rpg", "vbied",
                      "enemy forces", "enemy positioned", "hostile forces"]
        for t in strong where lower.contains(t) { score += 3 }

        let medium = ["small arms", "machine gun", "mortar", "indirect fire",
                      "enemy position", "enemy moving", "enemy vehicle",
                      "engaged by", "contact at", "hostile", "insurgent",
                      "taking contact", "in contact", "forces pinned"]
        for t in medium where lower.contains(t) { score += 2 }

        let weak = ["vicinity", "located at", "grid", "moving toward",
                    "currently", "at this time", "we have"]
        for t in weak where lower.contains(t) { score += 1 }

        return score
    }

    // ── Nine-Line ─────────────────────────────────────────────────────────────
    private func scoreNineLine(_ lower: String) -> Int {
        var score = 0

        // Opening markers
        let openings = ["nine line", "9 line", "niner line", "initial point"]
        for t in openings where lower.contains(t) { score += 3 }

        // Bare "IP" at the front of a transmission
        if lower.hasPrefix("ip ") || lower.hasPrefix("i.p.") { score += 3 }

        // Numbered line callouts: each one is strong evidence we're in a 9-line
        let lineCount = countLineMatches(lower)
        score += lineCount * 3

        // Field-specific keywords that appear almost exclusively in 9-line briefs
        let fieldTerms = ["egress", "attack heading", "final attack heading",
                          "offset left", "offset right",
                          "say when tally", "say when ready",
                          "mark type", "laser code", "sparkle",
                          "danger close", "friendlies within",
                          "target elevation", "target description"]
        for t in fieldTerms where lower.contains(t) { score += 2 }

        // Supporting terms (present in 9-line but also possible elsewhere)
        let supporting = ["heading", "egress direction", "friendlies",
                          "smoke", "laser", "mark", "mgrs", "grid",
                          "elevation", "tally", "no joy", "distance"]
        for t in supporting where lower.contains(t) { score += 1 }

        // Dense phonetic readout bonus
        if looksLikeReadout(lower) { score += 2 }

        // Post-brief closing phrases — still nine-line context but signals end
        let closing = ["authentication", "authenticate", "read back", "how copy",
                       "ready to copy"]
        for t in closing where lower.contains(t) { score += 2 }

        return score
    }

    // ── BDA ───────────────────────────────────────────────────────────────────
    private func scoreBDA(_ lower: String) -> Int {
        var score = 0
        let strong = ["splash", "shack", "direct hit",
                      "rounds complete", "battle damage", "bda follows",
                      "secondary explosion", "secondary fire",
                      "target destroyed", "no effect", "assessed destroyed",
                      "gun off target", "off target rounds complete"]
        for t in strong where lower.contains(t) { score += 3 }

        let medium = ["assessed", "neutralized", "suppressed", "destroyed",
                      "damaged", "kill zone", "confirmed kill",
                      "effects on target", "ordnance impact"]
        for t in medium where lower.contains(t) { score += 2 }

        let weak = ["confirmed", "fire", "impact"]
        for t in weak where lower.contains(t) { score += 1 }

        return score
    }

    // ── Remarks / Clearance ───────────────────────────────────────────────────
    private func scoreRemarks(_ lower: String) -> Int {
        var score = 0
        let strong = ["cleared hot", "not cleared hot", "abort abort abort",
                      "guns guns guns", "in hot", "in cold",
                      "abort abort", "negative clearance",
                      "off dry", "in dry", "off target"]
        for t in strong where lower.contains(t) { score += 3 }

        let medium = ["rifle", "pickle", "guns", "laser on",
                      "cleared to engage", "cleared to fire",
                      "abort", "go around", "no joy abort"]
        for t in medium where lower.contains(t) { score += 2 }

        let weak = ["cleared", "negative", "approved"]
        for t in weak where lower.contains(t) { score += 1 }

        return score
    }

    // ── Restrictions ─────────────────────────────────────────────────────────
    private func scoreRestrictions(_ lower: String) -> Int {
        var score = 0
        let strong = ["restrictions follow", "no restrictions",
                      "do not engage", "do not fire", "hold fire",
                      "restricted fire area", "no fire area",
                      "friendlies within", "civilians in area"]
        for t in strong where lower.contains(t) { score += 3 }

        let medium = ["safe area", "exclusion zone", "avoid", "do not target",
                      "collateral damage", "protected site"]
        for t in medium where lower.contains(t) { score += 2 }

        return score
    }

    // ── Game Plan ────────────────────────────────────────────────────────────
    private func scoreGamePlan(_ lower: String) -> Int {
        var score = 0
        let strong = ["game plan follows", "attack from", "axis of attack",
                      "time on target", "tot", "sequence of events",
                      "first pass", "second pass", "multiple passes"]
        for t in strong where lower.contains(t) { score += 3 }

        let medium = ["attack heading", "ingress route", "egress route",
                      "flight will", "aircraft will", "planned"]
        for t in medium where lower.contains(t) { score += 2 }

        return score
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /// Counts how many explicit "line N" markers appear in the text.
    private func countLineMatches(_ lower: String) -> Int {
        let pattern = #"(?i)\bline\s+(one|two|three|four|five|fife|six|seven|eight|nine|niner|\d)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return regex.numberOfMatches(in: lower, range: NSRange(lower.startIndex..., in: lower))
    }

    /// Returns true when the text is predominantly phonetic-alphabet words and
    /// digits — the hallmark of a coordinate/grid readout or 9-line field values.
    private func looksLikeReadout(_ lower: String) -> Bool {
        let phoneticSet: Set<String> = [
            "alpha","bravo","charlie","delta","echo","foxtrot","golf",
            "hotel","india","juliet","kilo","lima","mike","november",
            "oscar","papa","quebec","romeo","sierra","tango","uniform",
            "victor","whiskey","xray","yankee","zulu",
            "zero","one","two","three","four","five","fife",
            "six","seven","eight","nine","niner"
        ]
        let words = lower
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard words.count >= 3 else { return false }
        let scored = words.filter { w in
            phoneticSet.contains(w) || w.allSatisfy({ $0.isNumber })
        }.count
        return Double(scored) / Double(words.count) >= 0.55
    }

    // MARK: - Chunk Splitting

    private struct Chunk {
        let section: Section?   // nil = no keyword → continuation of current section
        let text: String        // full text from this keyword to the next keyword
        let trailing: String    // text after the keyword itself (empty for continuations)
    }

    /// Splits `original` on every keyword boundary and returns ordered chunks.
    /// This lets a single audio segment that spans multiple transmissions
    /// (e.g. "checking in… situation update… nine line line 1…") be fully parsed.
    private func splitIntoChunks(_ original: String) -> [Chunk] {
        let lower = original.lowercased()

        struct KMatch {
            let section: Section
            let keywordStart: String.Index   // in `lower`
            let keywordEnd:   String.Index
        }

        // IMPORTANT: same order and keywords as detectSection so priorities are respected.
        let rules: [(Section, [String])] = [
            (.cas,            ["type one control",  "type 1 control",
                               "type two control",  "type 2 control",
                               "type three control","type 3 control",
                               "checking in",       "check in"]),
            (.situationUpdate,["situation update",  "sitrep"]),
            (.nineLine,       ["nine line",         "9 line",
                               "9-line",            "niner line",
                               "initial point"]),          // IP = line 1 → implies nine-line
            (.bda,            ["battle damage assessment", "bda"]),
            (.gamePlan,       ["game plan",         "gameplan"]),
            (.restrictions,   ["restrictions"]),
            (.remarks,        ["remarks"]),
        ]

        var kmatches: [KMatch] = []
        for (section, keywords) in rules {
            for keyword in keywords {
                var searchFrom = lower.startIndex
                while let range = lower.range(of: keyword, options: .literal,
                                              range: searchFrom..<lower.endIndex) {
                    kmatches.append(KMatch(section: section,
                                           keywordStart: range.lowerBound,
                                           keywordEnd:   range.upperBound))
                    searchFrom = range.upperBound
                }
            }
        }

        // Sort by start position; on ties prefer the longer (more-specific) match.
        kmatches.sort {
            if $0.keywordStart != $1.keywordStart { return $0.keywordStart < $1.keywordStart }
            return $0.keywordEnd > $1.keywordEnd   // longer keyword wins
        }

        // Deduplicate: drop any match that starts inside the previous match.
        var deduped: [KMatch] = []
        for m in kmatches {
            if let last = deduped.last, m.keywordStart < last.keywordEnd { continue }
            deduped.append(m)
        }

        guard !deduped.isEmpty else {
            return [Chunk(section: nil, text: original, trailing: "")]
        }

        // Map a lower-string index to the same offset in `original`.
        // Safe for JTAC transcripts (all ASCII). Falls back to endIndex.
        func origIdx(_ idx: String.Index) -> String.Index {
            let offset = lower.distance(from: lower.startIndex, to: idx)
            return original.index(original.startIndex,
                                  offsetBy: offset,
                                  limitedBy: original.endIndex) ?? original.endIndex
        }

        var result: [Chunk] = []

        // Any text before the first keyword = continuation of the current section.
        let beforeFirst = String(original[original.startIndex..<origIdx(deduped[0].keywordStart)])
            .trimmingCharacters(in: .whitespaces)
        if !beforeFirst.isEmpty {
            result.append(Chunk(section: nil, text: beforeFirst, trailing: ""))
        }

        for (i, km) in deduped.enumerated() {
            let nextKeywordStart = i + 1 < deduped.count ? deduped[i + 1].keywordStart
                                                          : lower.endIndex
            let trailingStart = origIdx(km.keywordEnd)
            let trailingEnd   = origIdx(nextKeywordStart)

            let trailing = String(original[trailingStart..<trailingEnd])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:-"))

            let fullText = String(original[origIdx(km.keywordStart)..<trailingEnd])

            result.append(Chunk(section: km.section, text: fullText, trailing: trailing))
        }

        return result
    }



    /// Corrects common speech-to-text mis-recognitions for JTAC vocabulary.
    /// Runs before section detection so the parser always sees canonical forms.
    private func normalize(_ input: String) -> String {
        var s = input

        // Each entry: (pattern, replacement, isRegex)
        // Ordered carefully — multi-word patterns before their sub-words.
        let rules: [(String, String, Bool)] = [

            // ── 9-Line trigger variants ──────────────────────────────────────
            (#"(?i)\b9[- ]?lin(er|ed|e?s)\b"#,          "9 line",              true),
            (#"(?i)\bnine[- ]?lin(er|ed|e?s)\b"#,        "nine line",           true),
            (#"(?i)\bniner[- ]?lin(er|ed|e?s)?\b"#,      "nine line",           true),

            // ── CAS type variants ────────────────────────────────────────────
            (#"(?i)\btype[- ]?1\b"#,                     "type one",            true),
            (#"(?i)\btype[- ]?2\b"#,                     "type two",            true),
            (#"(?i)\btype[- ]?3\b"#,                     "type three",          true),
            (#"(?i)\btype[- ]?won\b"#,                   "type one",            true),
            (#"(?i)\btype[- ]?to\b"#,                    "type two",            true),

            // ── Brevity codes ─────────────────────────────────────────────────
            (#"(?i)\bclear(?:ed)?[- ]?the[- ]?hot\b"#,  "cleared hot",         true),
            (#"(?i)\bclear[- ]?hot\b"#,                  "cleared hot",         true),
            (#"(?i)\bdanger[- ]?clos(?:e|ed|ure|s)\b"#, "danger close",        true),
            (#"(?i)\bdanger[- ]?cloth\w*\b"#,            "danger close",        true),
            (#"(?i)\bdanger[- ]?claus\w*\b"#,            "danger close",        true),
            (#"(?i)\bin[- ]?hot\b"#,                     "in hot",              true),
            (#"(?i)\bin[- ]?dry\b"#,                     "in dry",              true),
            (#"(?i)\boff[- ]?dry\b"#,                    "off dry",             true),
            (#"(?i)\bbreak[- ]break\b"#,                 "break break",         true),

            // ── Radio procedure ───────────────────────────────────────────────
            (#"(?i)\bstand[- ]by\b"#,                    "standby",             true),
            (#"(?i)\bsay[- ]again\b"#,                   "say again",           true),
            (#"(?i)\browl?[- ]?co(?:py|pie)?\b"#,        "good copy",           true),
            (#"(?i)\blima[- ]charlie\b"#,                "lima charlie",        true),
            (#"(?i)\blame[- ]charlie\b"#,                "lima charlie",        true),
            (#"(?i)\bcheck(?:ing)?[- ]in\b"#,            "checking in",         true),

            // ── Troop contact ─────────────────────────────────────────────────
            (#"(?i)\btroops?[- ](?:and|in)[- ]contact\b"#, "troops in contact", true),

            // ── Situation update ──────────────────────────────────────────────
            (#"(?i)\bsit(?:[- ])?(?:rep|wrap|wrep)\b"#, "situation update",    true),

            // ── Weapons ───────────────────────────────────────────────────────
            (#"(?i)\b(?:30|thirty)[- ]?millimeter\b"#,  "thirty mike mike",    true),
            (#"(?i)\b(?:20|twenty)[- ]?millimeter\b"#,  "twenty mike mike",    true),
            (#"(?i)\bgbu[- ]?12\b"#,                     "GBU-12",              true),
            (#"(?i)\bgbu[- ]?31\b"#,                     "GBU-31",              true),
            (#"(?i)\bgbu[- ]?32\b"#,                     "GBU-32",              true),
            (#"(?i)\bgbu[- ]?38\b"#,                     "GBU-38",              true),
            (#"(?i)\bgbu[- ]?54\b"#,                     "GBU-54",              true),

            // ── Phonetic number words ─────────────────────────────────────────
            // Only in clearly numeric/readout contexts to avoid clobbering
            // natural English (e.g. "tree" in "tree line" should stay).
            (#"(?i)\bniner\b"#,                          "niner",               true), // keep
            (#"(?i)\bfife\b"#,                           "five",                true),
            (#"(?i)\b(?<=\d )tree\b"#,                   "three",               true),

            // ── Acronym spacing ───────────────────────────────────────────────
            (#"(?i)\bj[- ]?tac\b"#,                      "JTAC",                true),
            (#"(?i)\bb[- ]?d[- ]?a\b"#,                  "BDA",                 true),
            (#"(?i)\bc[- ]?a[- ]?s\b"#,                  "CAS",                 true),
            (#"(?i)\bm[- ]?g[- ]?r[- ]?s\b"#,            "MGRS",                true),
            (#"(?i)\bi[- ]?p\b"#,                         "IP",                  true),

            // ── Game plan ─────────────────────────────────────────────────────
            (#"(?i)\bgame[- ]?plan\b"#,                  "game plan",           true),
        ]

        for (pattern, replacement, isRegex) in rules {
            if isRegex {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let range = NSRange(s.startIndex..., in: s)
                s = regex.stringByReplacingMatches(in: s, range: range,
                                                   withTemplate: replacement)
            } else {
                s = s.replacingOccurrences(of: pattern, with: replacement,
                                           options: .caseInsensitive)
            }
        }
        return s
    }

    // MARK: - Section Detection

    // Returns the matched section and the text that follows the keyword in the
    // original segment (preserving original casing).
    private func detectSection(in lower: String,
                                originalSegment: String) -> (Section, String)? {

        // Ordered: most-specific first so "type one control" beats "remarks"
        let rules: [(Section, [String])] = [
            (.cas,            ["type one control",  "type 1 control",
                               "type two control",  "type 2 control",
                               "type three control","type 3 control",
                               "checking in",       "check in"]),
            (.situationUpdate,["situation update",  "sitrep"]),
            (.nineLine,       ["nine line",         "9 line",
                               "9-line",            "niner line",
                               "initial point"]),          // IP = line 1 → implies nine-line
            (.bda,            ["battle damage assessment", "bda"]),
            (.gamePlan,       ["game plan",         "gameplan"]),
            (.restrictions,   ["restrictions"]),
            (.remarks,        ["remarks"]),
        ]

        for (section, keywords) in rules {
            for keyword in keywords {
                if let range = lower.range(of: keyword) {
                    // Map the end of the keyword range back to the original string
                    // (safe because lowercasing preserves UTF-8 offsets)
                    let offset = lower.distance(from: lower.startIndex, to: range.upperBound)
                    let origIdx = originalSegment.index(originalSegment.startIndex,
                                                        offsetBy: offset,
                                                        limitedBy: originalSegment.endIndex)
                                  ?? originalSegment.endIndex
                    let trailing = String(originalSegment[origIdx...])
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:-"))
                    return (section, trailing)
                }
            }
        }
        return nil
    }

    // MARK: - Section Transitions

    private func transition(to section: Section,
                            trailing: String,
                            fullSegment: String) {
        currentSection = section

        switch section {

        case .cas:
            if report.cas == nil { report.cas = CASData() }
            extractCASType(from: fullSegment.lowercased())
            // If "checking in" is the trigger, store the whole segment as check-in
            if fullSegment.lowercased().contains("checking in") ||
               fullSegment.lowercased().contains("check in") {
                report.cas?.checkIn = join(report.cas?.checkIn, fullSegment)
            } else if !trailing.isEmpty {
                report.cas?.checkIn = join(report.cas?.checkIn, trailing)
            }

        case .situationUpdate:
            report.situationUpdate = join(report.situationUpdate, trailing)

        case .nineLine:
            if report.nineLine == nil { report.nineLine = NineLine() }
            if !trailing.isEmpty { parseNineLineText(trailing) }

        case .remarks:
            report.remarks = join(report.remarks, trailing)

        case .restrictions:
            report.restrictions = join(report.restrictions, trailing)

        case .bda:
            report.bda = join(report.bda, trailing)

        case .gamePlan:
            report.gamePlan = join(report.gamePlan, trailing)

        case .unknown:
            break
        }
    }

    private func appendToCurrentSection(_ segment: String) {
        switch currentSection {
        case .cas:
            report.cas?.checkIn = join(report.cas?.checkIn, segment)

        case .situationUpdate:
            report.situationUpdate = join(report.situationUpdate, segment)

        case .nineLine:
            if report.nineLine == nil { report.nineLine = NineLine() }
            parseNineLineText(segment)

        case .remarks:
            report.remarks = join(report.remarks, segment)

        case .restrictions:
            report.restrictions = join(report.restrictions, segment)

        case .bda:
            report.bda = join(report.bda, segment)

        case .gamePlan:
            report.gamePlan = join(report.gamePlan, segment)

        case .unknown:
            break
        }
    }

    // MARK: - CAS Type Extraction

    private func extractCASType(from lower: String) {
        if lower.contains("type one") || lower.contains("type 1") {
            report.cas?.type    = "Type 1"
            report.cas?.control = "Type 1 Control"
        } else if lower.contains("type two") || lower.contains("type 2") {
            report.cas?.type    = "Type 2"
            report.cas?.control = "Type 2 Control"
        } else if lower.contains("type three") || lower.contains("type 3") {
            report.cas?.type    = "Type 3"
            report.cas?.control = "Type 3 Control"
        }
    }

    // MARK: - Nine-Line Parsing

    // Word → line number. Supports both word and digit forms.
    private static let lineNumbers: [(words: [String], number: Int)] = [
        (["one",   "1"],          1),
        (["two",   "2"],          2),
        (["three", "3"],          3),
        (["four",  "4"],          4),
        (["five",  "fife", "5"],  5),
        (["six",   "6"],          6),
        (["seven", "7"],          7),
        (["eight", "8"],          8),
        (["nine",  "niner", "9"], 9),
    ]

    /// Builds a regex that matches "line <number-word-or-digit>" for all variants.
    private static let lineRegex: NSRegularExpression = {
        let alts = lineNumbers
            .flatMap { $0.words }
            .sorted { $0.count > $1.count }   // longer first avoids partial matches
            .joined(separator: "|")
        // Matches e.g. "line one", "line 1", "line niner" optionally followed by : or ,
        let pattern = #"(?i)\bline\s+(?:"# + alts + #")\b[:\s,]*"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    /// Splits the text by "line N" markers and assigns each chunk to the right field.
    private func parseNineLineText(_ text: String) {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = JTACParser.lineRegex.matches(in: text, range: fullRange)

        if matches.isEmpty {
            // No explicit line labels — try keyword heuristics
            assignNineLineByKeyword(text)
            return
        }

        for (i, match) in matches.enumerated() {
            // Determine which line number this label represents
            let label = nsText.substring(with: match.range).lowercased()
            guard let lineNum = lineNumberFor(label: label) else { continue }

            // Chunk = from end of this label to start of next label (or end of string)
            let chunkStart = match.range.upperBound
            let chunkEnd   = i + 1 < matches.count
                             ? matches[i + 1].range.lowerBound
                             : nsText.length
            guard chunkStart < chunkEnd else { continue }

            let chunk = nsText
                .substring(with: NSRange(location: chunkStart,
                                         length: chunkEnd - chunkStart))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:-"))

            guard !chunk.isEmpty else { continue }
            assignNineLine(number: lineNum, text: chunk)
        }
    }

    private func lineNumberFor(label: String) -> Int? {
        for entry in JTACParser.lineNumbers {
            for word in entry.words {
                if label.contains(word) { return entry.number }
            }
        }
        return nil
    }

    /// Fallback: assign a plain segment to the most likely 9-line field by keyword.
    private func assignNineLineByKeyword(_ text: String) {
        let lower = text.lowercased()
        if lower.hasPrefix("ip") || lower.contains("initial point") {
            report.nineLine?.ip = join(report.nineLine?.ip, text)
        } else if lower.contains("heading") || lower.hasPrefix("hdg") {
            report.nineLine?.heading = join(report.nineLine?.heading, text)
        } else if lower.contains("elevation") || lower.contains("elev") {
            report.nineLine?.targetElevation = join(report.nineLine?.targetElevation, text)
        } else if lower.contains("friendl") {
            report.nineLine?.friendlies = join(report.nineLine?.friendlies, text)
        } else if lower.hasPrefix("egress") {
            report.nineLine?.egress = join(report.nineLine?.egress, text)
        } else if lower.contains("mark") || lower.contains("smoke") || lower.contains("laser") {
            report.nineLine?.targetMark = join(report.nineLine?.targetMark, text)
        } else if lower.contains("grid") || lower.contains("mgrs") {
            report.nineLine?.targetDescription = join(report.nineLine?.targetDescription, text)
        } else {
            // Unknown context: accumulate in description as catch-all
            report.nineLine?.targetDescription = join(report.nineLine?.targetDescription, text)
        }
    }

    private func assignNineLine(number: Int, text: String) {
        switch number {
        case 1: report.nineLine?.ip               = text
        case 2: report.nineLine?.heading          = text
        case 3: report.nineLine?.distance         = text
        case 4: report.nineLine?.targetElevation  = text
        case 5: report.nineLine?.targetDescription = text
        case 6: report.nineLine?.targetMark       = text
        case 7: report.nineLine?.friendlies       = text
        case 8: report.nineLine?.egress           = text
        case 9: report.nineLine?.remarksLine      = text
        default: break
        }
    }

    // MARK: - String Helpers

    /// Appends new text to an optional field, space-separated.
    private func join(_ existing: String?, _ new: String) -> String {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return existing ?? "" }
        guard let existing, !existing.isEmpty else { return trimmed }
        return existing + " " + trimmed
    }
}
