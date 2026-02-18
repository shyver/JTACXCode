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
                    // For CAS, the callsign/aircraft often precede the keyword
                    // ("Axeman 2-1 this is Hawg 11 checking in...").  Run a
                    // full-transmission extract BEFORE the chunk-only extract so
                    // those pre-keyword fields are captured.
                    if section == .cas {
                        if report.cas == nil { report.cas = CASData() }
                        extractCASFields(from: transmission)
                    }
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

        // Explicit SITREP field labels — strongly indicate a structured update
        let fieldLabels = ["threats:", "threat:", "targets:", "target:",
                           "friendlies:", "arty:", "artillery:",
                           "clearance:", "clearance authority",
                           "ordnance:", "remarks:", "restrictions:"]
        for t in fieldLabels where lower.contains(t) { score += 4 }

        // High-confidence threat vocabulary
        let strong = ["troops in contact", "contact report",
                      "taking fire", "receiving fire", "under fire",
                      "small arms fire", "machine gun fire",
                      "manpads", "ied", "rpg", "vbied",
                      "enemy forces", "enemy positioned", "hostile forces",
                      "bmp", "btr", "technical", "dismounts"]
        for t in strong where lower.contains(t) { score += 3 }

        let medium = ["small arms", "machine gun", "mortar", "indirect fire",
                      "enemy position", "enemy moving", "enemy vehicle",
                      "engaged by", "contact at", "hostile", "insurgent",
                      "taking contact", "in contact", "forces pinned",
                      "cold", "hot arty", "arty cold", "arty hot"]
        for t in medium where lower.contains(t) { score += 2 }

        let weak = ["vicinity", "located at", "grid", "moving toward",
                    "currently", "at this time", "we have", "platoon",
                    "section", "company", "battalion", "km", "meters south",
                    "meters east", "meters west", "meters north"]
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



    // MARK: - Structural Comma Insertion

    /// Inserts commas at natural JTAC speech boundaries that the recognizer's
    /// `addsPunctuation` misses. Runs on the raw `formattedString` before any
    /// keyword detection or normalization rules.
    ///
    /// Targeted boundaries:
    ///  - Before every "line N" label when something precedes it
    ///  - After every "line N" label before its content
    ///  - Before section-opening keywords when something precedes them
    ///  - Between a number/phonetic word and the next distinct field group
    private func insertCommas(_ input: String) -> String {
        var s = input

        let lineWords = "one|two|three|four|five|fife|six|seven|eight|nine|niner|\\d"

        // 1. Before "line N" when preceded by non-whitespace, non-comma content.
        //    "bravo two one line two" → "bravo two one, line two"
        if let re = try? NSRegularExpression(
            pattern: #"(?i)(?<=[^\s,])(\s+)(line\s+(?:"# + lineWords + #")\b)"#) {
            s = re.stringByReplacingMatches(
                in: s, range: NSRange(s.startIndex..., in: s),
                withTemplate: ", $2")
        }

        // 2. After "line N" label, before its content (no comma already there).
        //    "line one bravo" → "line one, bravo"
        if let re = try? NSRegularExpression(
            pattern: #"(?i)\b(line\s+(?:"# + lineWords + #"))\s+(?!,)"#) {
            s = re.stringByReplacingMatches(
                in: s, range: NSRange(s.startIndex..., in: s),
                withTemplate: "$1, ")
        }

        // 3. Before major section keywords when something precedes them.
        //    "…roger situation update…" → "…roger, situation update…"
        let sectionKWs = [
            "situation update", "sitrep",
            "nine line", "9 line", "niner line",
            "initial point",
            "battle damage assessment", "bda",
            "game plan", "gameplan",
            "restrictions", "remarks",
            "checking in", "check in",
        ]
        for kw in sectionKWs {
            let escaped = NSRegularExpression.escapedPattern(for: kw)
            if let re = try? NSRegularExpression(
                pattern: "(?i)(?<=[^\\s,])(\\s+)(\(escaped))") {
                s = re.stringByReplacingMatches(
                    in: s, range: NSRange(s.startIndex..., in: s),
                    withTemplate: ", $2")
            }
        }

        // 4. Between a phonetic/number word and the next "line" keyword
        //    to clean up cases the above rules didn't catch due to ordering.
        //    "niner line one bravo, two one line two" — already handled above,
        //    but double-pass is safe because we never insert double-commas.
        //    Collapse any ",,"-style artefacts left by multiple passes.
        if let re = try? NSRegularExpression(pattern: #",\s*,"#) {
            s = re.stringByReplacingMatches(
                in: s, range: NSRange(s.startIndex..., in: s),
                withTemplate: ",")
        }
        // Collapse ", , " patterns too.
        if let re = try? NSRegularExpression(pattern: #",(\s*,)+"#) {
            s = re.stringByReplacingMatches(
                in: s, range: NSRange(s.startIndex..., in: s),
                withTemplate: ",")
        }

        return s
    }

    /// Corrects common speech-to-text mis-recognitions for JTAC vocabulary.
    /// Runs before section detection so the parser always sees canonical forms.
    private func normalize(_ input: String) -> String {
        var s = insertCommas(input)   // structural comma pass first

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

            // ── Known callsign STT mishearings ────────────────────────────────
            ("X-men",                                    "Axeman",              false),
            ("x-men",                                    "Axeman",              false),
            ("Xmen",                                     "Axeman",              false),
            ("xmen",                                     "Axeman",              false),
            ("asked man",                                "Axeman",              false),
            ("Axman",                                    "Axeman",              false),
            ("axman",                                    "Axeman",              false),
            ("Haug",                                     "Hawg",                false),
            ("haug",                                     "Hawg",                false),
            ("Hogg",                                     "Hawg",                false),
            ("hogg",                                     "Hawg",                false),
            ("Sabre",                                    "Saber",               false),

            // ── Aviation-specific word fixes ──────────────────────────────────
            // "two by" fusions — STT merges into "Dubai", "do buy", "do by" etc.
            (#"(?i)\bdubai\b"#,                          "2x ",                 true),
            (#"(?i)\bdo\s+bu?y\b"#,                      "2x ",                 true),
            (#"(?i)\bbuy\b"#,                            "by",                  true),

            // Phonetic mis-hearings of number words
            (#"(?i)\bwun\b"#,                            "one",                 true),
            (#"(?i)\bto(?=\s+(?:one|two|three|four|five|fife|six|seven|eight|nine|niner|zero|\d))"#,
                                                         "two",                 true),
            // "to" between two number-words is always the digit "two"
            // e.g. "one to one" → "one two one", "axeman to one" → "axeman two one"
            (#"(?i)(?<=(?:one|two|three|four|five|fife|six|seven|eight|nine|niner|zero))\s+to\s+(?=one|two|three|four|five|fife|six|seven|eight|nine|niner|zero|\d)"#,
                                                         " two ",               true),

            // Canonical ordnance count: "two by GBU-12" → "2x GBU-12"
            (#"(?i)\bone\s+by\s+"#,                      "1x ",                 true),
            (#"(?i)\btwo\s+by\s+"#,                      "2x ",                 true),
            (#"(?i)\bthree\s+by\s+"#,                    "3x ",                 true),
            (#"(?i)\bfour\s+by\s+"#,                     "4x ",                 true),
            (#"(?i)\bsix\s+by\s+"#,                      "6x ",                 true),
            (#"(?i)\beight\s+by\s+"#,                    "8x ",                 true),
            (#"(?i)\b(\d+)\s+by\s+"#,                    "$1x ",                true),
            // mike-mike spacing variants
            (#"(?i)\bmike\s+mike\b"#,                    "mike-mike",           true),

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
            extractCASFields(from: fullSegment)

        case .situationUpdate:
            if report.situationUpdate == nil { report.situationUpdate = SituationUpdate() }
            extractSitrepFields(from: fullSegment)

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
            if report.cas == nil { report.cas = CASData() }
            extractCASFields(from: segment)

        case .situationUpdate:
            extractSitrepFields(from: segment)

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

    // MARK: - SITREP Field Extraction

    /// Parses a free-text SITREP segment and populates SituationUpdate fields.
    /// Each call fills in blanks left by earlier calls — safe to invoke repeatedly.
    private func extractSitrepFields(from segment: String) {
        if report.situationUpdate == nil { report.situationUpdate = SituationUpdate() }
        let lower = segment.lowercased()

        // ── THREATS ───────────────────────────────────────────────────────────
        // Keywords: "threats", "threat", "MANPADS", "small arms", "heavy weapons"
        if report.situationUpdate?.threats == nil {
            let threatPatterns: [String] = [
                #"(?i)\bthreats?\s*[:\-]?\s*(.+?)(?:\.|,\s*(?:targets?|enemy|friendl|arty|clearance|ordnance|remarks)|$)"#,
                #"(?i)\b((?:small arms|heavy weapons?|machine gun|mortar|MANPADS|RPGS?|IED|VBIED|AAA|SAM|ZSU|anti[-\s]air|RPG)(?:[,\s]+(?:and|possible|with|plus))?\s*(?:small arms|heavy weapons?|machine gun|mortar|MANPADS|RPGS?|IED|VBIED|AAA|SAM|ZSU|anti[-\s]air|RPG)*)"#,
            ]
            for pat in threatPatterns {
                if let val = extractCapture(pat, in: segment, group: 1),
                   !val.trimmingCharacters(in: .whitespaces).isEmpty {
                    report.situationUpdate?.threats = val.trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
        }

        // ── TARGETS / ENEMY ───────────────────────────────────────────────────
        if report.situationUpdate?.targets == nil {
            let tgtPatterns: [String] = [
                #"(?i)\b(?:targets?|enemy)\s*[:\-\/]?\s*(.+?)(?:\.|,\s*(?:threats?|friendl|arty|clearance|ordnance|remarks)|$)"#,
                #"(?i)\b(\d+\s+(?:BMP|BTR|T-?\d+|truck|pickup|technical|armed vehicle|dismount|personnel|infantry|PKM|KIA|WIA)s?[^,\.]*?)(?:[,\.]|$)"#,
            ]
            for pat in tgtPatterns {
                if let val = extractCapture(pat, in: segment, group: 1),
                   !val.trimmingCharacters(in: .whitespaces).isEmpty {
                    report.situationUpdate?.targets = join(report.situationUpdate?.targets,
                                                          val.trimmingCharacters(in: .whitespacesAndNewlines))
                    break
                }
            }
        }

        // ── FRIENDLIES ────────────────────────────────────────────────────────
        // e.g. "1 Platoon South 400m, 1 Platoon East 1800m"
        if lower.contains("friendl") {
            if let val = extractCapture(
                #"(?i)\bfriendl(?:y|ies)?\s*[:\-]?\s*(.+?)(?:\.|,\s*(?:threats?|targets?|enemy|arty|clearance|ordnance|remarks)|$)"#,
                in: segment, group: 1),
               !val.trimmingCharacters(in: .whitespaces).isEmpty {
                report.situationUpdate?.friendlies = join(report.situationUpdate?.friendlies,
                                                         val.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        // ── ARTY ──────────────────────────────────────────────────────────────
        // e.g. "1 COLD South 13km", "arty cold", "arty hot", "no arty"
        if lower.contains("arty") || lower.contains("artillery") || lower.contains(" cold") || lower.contains(" hot ") {
            if let val = extractCapture(
                #"(?i)\b(?:arty|artillery)\s*[:\-]?\s*(.+?)(?:\.|,\s*(?:threats?|targets?|enemy|friendl|clearance|ordnance|remarks)|$)"#,
                in: segment, group: 1) {
                report.situationUpdate?.arty = val.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if lower.contains(" cold") || lower.contains(" hot") {
                // Bare "1 COLD South 13km" with no "arty" keyword
                if let val = extractCapture(
                    #"(?i)(\d+\s+(?:cold|hot)[^,\.]*?)(?:[,\.]|$)"#,
                    in: segment, group: 1) {
                    report.situationUpdate?.arty = val.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        // ── CLEARANCE ─────────────────────────────────────────────────────────
        // e.g. "clearance ODIN11", "clearance authority Widow 11"
        if report.situationUpdate?.clearance == nil,
           lower.contains("clearance") || lower.contains("clear by") || lower.contains("cleared by") {
            if let val = extractCapture(
                #"(?i)\bclearance(?:\s+authority)?\s*[:\-]?\s*(\S+(?:\s+\w{1,4})?)"#,
                in: segment, group: 1) {
                report.situationUpdate?.clearance = val.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // ── ORDNANCE (SITREP context) ─────────────────────────────────────────
        // Only capture when explicitly labelled — avoid pulling in CAS ordnance
        if report.situationUpdate?.ordnance == nil,
           lower.contains("ordnance:") || lower.contains("ord:") {
            if let val = extractCapture(
                #"(?i)\b(?:ordnance|ord)\s*[:\-]?\s*(.+?)(?:\.|,\s*(?:threats?|targets?|enemy|friendl|arty|clearance|remarks)|$)"#,
                in: segment, group: 1),
               !val.trimmingCharacters(in: .whitespaces).isEmpty,
               val.trimmingCharacters(in: .whitespaces) != "//" {
                report.situationUpdate?.ordnance = val.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // ── REMARKS / RESTRICTIONS ────────────────────────────────────────────
        if lower.contains("remarks") || lower.contains("restrictions") {
            if let val = extractCapture(
                #"(?i)\b(?:remarks?|restrictions?)\s*[:\/\-]?\s*(.+?)(?:\.|$)"#,
                in: segment, group: 1),
               !val.trimmingCharacters(in: .whitespaces).isEmpty,
               val.trimmingCharacters(in: .whitespaces) != "//" {
                report.situationUpdate?.remarks = join(report.situationUpdate?.remarks,
                                                      val.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    // MARK: - CAS Field Extraction

    /// Parses a free-text CAS check-in segment and populates CASData fields.
    /// Designed to work on partial/informal phrasing — later calls for the same
    /// session will fill in any blanks left by earlier ones.
    private func extractCASFields(from segment: String) {
        let lower = segment.lowercased()

        // ── Control type ──────────────────────────────────────────────────────
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

        // ── Callsign ──────────────────────────────────────────────────────────
        // Handles both digit form ("Viper 1-1") and word-number form
        // ("Hawg one-one", "Axeman two-one").
        // Also handles "<destination> this is <callsign>" structure where the
        // aircraft identifies itself after "this is".
        if report.cas?.callsign == nil {
            let numWord = "(?:one|two|three|four|five|six|seven|eight|nine|niner|zero)"
            let numPart = "(?:\\d[\\d-]*|\(numWord)(?:[- ]\(numWord))*)"
            // First priority: "this is <callsign>" — the transmitting aircraft
            let thisIsPattern = "(?i)\\bthis\\s+is\\s+([A-Za-z]+(?:[- ][A-Za-z]+)?)\\s+(\(numPart))\\b"
            if let regex = try? NSRegularExpression(pattern: thisIsPattern),
               let match = regex.firstMatch(in: segment,
                                            range: NSRange(segment.startIndex..., in: segment)) {
                let word = (segment as NSString).substring(with: match.range(at: 1))
                let num  = (segment as NSString).substring(with: match.range(at: 2))
                report.cas?.callsign = "\(word) \(num)"
            }

            // Second priority: first callsign-shaped token in the segment.
            // The name part must NOT be a number word, a common English word,
            // or a JTAC term — callsigns are always proper names.
            if report.cas?.callsign == nil {
                let csPattern = "(?i)\\b([A-Za-z]+(?:[- ][A-Za-z]+)?)\\s+(\(numPart))\\b"
                if let regex = try? NSRegularExpression(pattern: csPattern) {
                    let ns = segment as NSString
                    let matches = regex.matches(in: segment,
                                               range: NSRange(segment.startIndex..., in: segment))
                    // Words that must NOT be the name-part of a callsign
                    let blockedWords: Set<String> = [
                        // JTAC terms
                        "type","gbu","mk","line","laser","vdl","abort","code",
                        "fuel","playtime","this","checking","check","mission",
                        "aircraft","ordnance","altitude","heading","distance",
                        "elevation","remarks","restrictions","game","bda","cas",
                        "mgrs","grid","egress","ingress","attack","initial",
                        // Number words — a callsign name is never a bare number word
                        "one","two","three","four","five","fife","six","seven",
                        "eight","nine","niner","zero","ten","eleven","twelve",
                        "thirteen","fourteen","fifteen","sixteen","seventeen",
                        "eighteen","nineteen","twenty","thirty","forty","fifty",
                        // Common radio procedure words
                        "standby","roger","wilco","copy","over","out","break",
                        "affirm","negative","authentic","authenticate",
                    ]
                    for match in matches {
                        let word = ns.substring(with: match.range(at: 1))
                        let wordLower = word.lowercased()
                        // Reject if word itself is blocked or starts with a blocked prefix
                        let blocked = blockedWords.contains(wordLower) ||
                            blockedWords.contains(where: {
                                $0.count > 3 && wordLower.hasPrefix($0)
                            })
                        if !blocked {
                            let num = ns.substring(with: match.range(at: 2))
                            report.cas?.callsign = "\(word) \(num)"
                            break
                        }
                    }
                }
            }
        }

        // ── Aircraft type ─────────────────────────────────────────────────────
        if report.cas?.aircraftType == nil {
            // Regex patterns matched directly against the segment.
            let acRegexes: [String] = [
                #"(?i)\ba-?10[a-z]?\b"#,
                #"(?i)\bf-?16[a-z]?\b"#,
                #"(?i)\bf/?a-?18[a-z]?\b"#,
                #"(?i)\bf-?15[a-z]?\b"#,
                #"(?i)\bb-?52\b"#,
                #"(?i)\bb-?1[b]?\b"#,
                #"(?i)\bac-?130\b"#,
                #"(?i)\bah-?64[a-z]?\b"#,
                #"(?i)\bmq-?9\b"#,
            ]
            for pat in acRegexes {
                if let v = extractMatch(pat, in: segment), !v.isEmpty {
                    report.cas?.aircraftType = v.uppercased()
                    break
                }
            }
            // Nickname → designation aliases (only if regex pass found nothing).
            if report.cas?.aircraftType == nil {
                let aliases: [(String, String)] = [
                    (#"(?i)\b(?:warthog|hawg)\b"#, "A-10"),
                    (#"(?i)\bviper\b"#,             "F-16"),
                    (#"(?i)\bhornet\b"#,            "F/A-18"),
                    (#"(?i)\breaper\b"#,            "MQ-9"),
                    (#"(?i)\bapache\b"#,            "AH-64"),
                    (#"(?i)\b(?:spooky|ghostrider)\b"#, "AC-130"),
                ]
                for (pat, designation) in aliases {
                    if extractMatch(pat, in: segment) != nil {
                        report.cas?.aircraftType = designation
                        break
                    }
                }
            }
        }

        // ── Ordnance ──────────────────────────────────────────────────────────
        // Accumulate — multiple weapons can be called out across segments.
        var ordnanceParts: [String] = []
        let ordPatterns: [String] = [
            #"(?i)\bGBU[-\s]?\d+\b"#,
            #"(?i)\bJDAM\b"#,
            #"(?i)\bPaveway\b"#,
            #"(?i)\bHellfire\b"#,
            #"(?i)\bBrimstone\b"#,
            #"(?i)\bMaverick\b"#,
            #"(?i)\bAPKWS\b"#,
            #"(?i)\bMk[-\s]?\d+\b"#,
            #"(?i)\b(?:twenty|thirty|\d+)\s+mike[-\s]mike\b"#,
            #"(?i)\b\d+x\s*\w+"#,                         // "4x GBU-12" style
            #"(?i)\b(?:two|four|six|eight|\d+)\s+(?:GBU|Mk|JDAM|Hellfire)\b"#,
        ]
        for pat in ordPatterns {
            if let val = extractMatch(pat, in: segment), !val.isEmpty {
                ordnanceParts.append(val)
            }
        }
        if !ordnanceParts.isEmpty {
            let combined = ordnanceParts.joined(separator: ", ")
            report.cas?.ordnance = join(report.cas?.ordnance, combined)
        }

        // ── Playtime ──────────────────────────────────────────────────────────
        if report.cas?.playtime == nil {
            // e.g. "playtime 45 minutes", "playtime four five", "45 minutes playtime"
            let ptPatterns = [
                // "playtime 45 minutes" / "playtime four five minutes"
                #"(?i)\bplaytime\s+([\w\s]+?(?:minutes?|mins?|hours?))(?=[,. ]|$)"#,
                // "45 minutes" / "45 mins on station"
                #"(?i)\b(\d+)\s*(?:minutes?|mins?)\s*(?:playtime|on station|loiter)?"#,
                // "playtime fifteen" — single token, stop at comma/period/space-then-non-digit-word
                #"(?i)\bplaytime\s+(\w+)(?=[,. ]|$)"#,
            ]
            for pat in ptPatterns {
                if let val = extractCapture(pat, in: segment, group: 1) {
                    report.cas?.playtime = val.trimmingCharacters(in: .whitespaces)
                    break
                }
            }
        }

        // ── Laser code ────────────────────────────────────────────────────────
        if report.cas?.laserCode == nil {
            // 4-digit code, optionally preceded by "laser" or "code"
            let lcPatterns = [
                #"(?i)\blaser\s+code\s+(\d{4})\b"#,
                #"(?i)\blaser\s+(\d{4})\b"#,
                #"(?i)\bcode\s+(\d{4})\b"#,
                #"(?i)\b(1[0-9]{3}|[2-9]\d{3})\b"#,     // bare 4-digit number
            ]
            for pat in lcPatterns {
                if let val = extractCapture(pat, in: segment, group: 1) {
                    report.cas?.laserCode = val
                    break
                }
            }
        }

        // ── VDL code ──────────────────────────────────────────────────────────
        if report.cas?.vdlCode == nil {
            let vdlPatterns = [
                #"(?i)\bVDL\s+(?:code\s+)?(\w+)\b"#,
                #"(?i)\bdata\s*link\s+(?:code\s+)?(\w+)\b"#,
                #"(?i)\blink\s+(\d+)\b"#,
            ]
            for pat in vdlPatterns {
                if let val = extractCapture(pat, in: segment, group: 1) {
                    report.cas?.vdlCode = val
                    break
                }
            }
        }

        // ── Abort code ────────────────────────────────────────────────────────
        if report.cas?.abortCode == nil {
            let abPatterns = [
                #"(?i)\babort\s+(?:code\s+|word\s+)?(\w+(?:\s+\w+)?)\b"#,
                #"(?i)\babort\s+(?:code\s+is\s+)?(\w+)\b"#,
            ]
            for pat in abPatterns {
                if let val = extractCapture(pat, in: segment, group: 1) {
                    // Exclude bare "abort" calls which have no real code word following
                    if !["abort","criteria","code"].contains(val.lowercased()) {
                        report.cas?.abortCode = val
                        break
                    }
                }
            }
        }

        // ── Position and Altitude ─────────────────────────────────────────────
        if report.cas?.posAndAlt == nil {
            let altPatterns = [
                #"(?i)\b(\d{1,2}[,.]?\d{3}\s*(?:feet|ft|msl|agl))\b"#,
                #"(?i)\bat\s+(\d+\s*(?:feet|ft|thousand))\b"#,
                #"(?i)\b(flight\s+level\s+\d+)\b"#,
                #"(?i)\b(angels\s+\w+)\b"#,
            ]
            for pat in altPatterns {
                if let val = extractCapture(pat, in: segment, group: 1) {
                    report.cas?.posAndAlt = join(report.cas?.posAndAlt, val)
                    break
                }
            }
        }

        // ── CAPES (capabilities) ──────────────────────────────────────────────
        var capeParts: [String] = []
        let capeTokens: [(String, String)] = [
            (#"(?i)\bFLIR\b"#, "FLIR"), (#"(?i)\bTGP\b"#, "TGP"),
            (#"(?i)\bsniper\b"#, "Sniper"), (#"(?i)\blitening\b"#, "Litening"),
            (#"(?i)\bNVG\b"#, "NVG"), (#"(?i)\bNVDS\b"#, "NVDS"),
            (#"(?i)\blaser\b"#, "Laser"), (#"(?i)\bwing\s*born[e]?\b"#, "Wingborne"),
            (#"(?i)\bHMD\b"#, "HMD"), (#"(?i)\bSDL\b"#, "SDL"),
            (#"(?i)\bRWR\b"#, "RWR"),
        ]
        for (pat, label) in capeTokens {
            if let _ = extractMatch(pat, in: segment) { capeParts.append(label) }
        }
        if !capeParts.isEmpty {
            let combined = capeParts.joined(separator: ", ")
            report.cas?.capes = join(report.cas?.capes, combined)
        }
        // Also capture a free-text "capes:" callout
        if let val = extractCapture(#"(?i)\bcapes?\s*[:\-]?\s*(.+?)(?:\.|,|$)"#,
                                     in: segment, group: 1) {
            report.cas?.capes = join(report.cas?.capes, val)
        }

        // ── Mission number ────────────────────────────────────────────────────
        if report.cas?.mission == nil {
            let missPatterns = [
                #"(?i)\bmission\s+(?:number\s+)?(\w+)\b"#,
                #"(?i)\bmission\s+id\s+(\w+)\b"#,
            ]
            for pat in missPatterns {
                if let val = extractCapture(pat, in: segment, group: 1) {
                    report.cas?.mission = val
                    break
                }
            }
        }
    }

    // ── Regex helpers ─────────────────────────────────────────────────────────

    /// Returns the full matched string for `pattern` in `text`, or nil.
    private func extractMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text,
                                           range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (text as NSString).substring(with: match.range)
    }

    /// Returns capture group `group` for `pattern` in `text`, or nil.
    private func extractCapture(_ pattern: String, in text: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text,
                                           range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > group
        else { return nil }
        let r = match.range(at: group)
        guard r.location != NSNotFound else { return nil }
        return (text as NSString).substring(with: r)
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
