import Foundation
import NaturalLanguage

/// Local-only PII anonymization layer. When `AppConfig.privacyMode` is on,
/// `LLMRouter.rewrite(...)` pipes the user's text through `anonymize(_:)` on the
/// way out and through `deanonymize(_:)` on the way back, so:
///
///   - names / company names / places are detected with Apple's built-in
///     `NLTagger(.nameType)` and replaced with stable placeholders
///     (`[NAME_1]`, `[UNTERNEHMEN_1]`, `[ORT_1]`);
///   - phone numbers and URLs come from `NSDataDetector`;
///   - emails and IPv4 addresses come from a minimal regex;
///
/// and the reverse pass rewrites the LLM's response back into the user's real
/// terms before it's displayed. No external service is involved — the whole
/// detection stack is macOS system frameworks, so the privacy mode can't leak
/// while trying to be private.
///
/// Mapping lifetime: memory only. Reset on toggle-off and on app quit. Never
/// written to disk (that would create the exact PII database we're trying to
/// avoid).
final class PrivacyEngine: ObservableObject {

    /// Placeholder prefix — deliberately in German caps to match the UI language
    /// and reduce collision risk with normal text.
    enum EntityKind: String, CaseIterable {
        case person       = "NAME"
        case organization = "UNTERNEHMEN"
        case place        = "ORT"
        case address      = "ADRESSE"
        case email        = "EMAIL"
        case ip           = "IP"
        case url          = "URL"
        case phone        = "TELEFON"
        case iban         = "IBAN"
        case creditCard   = "KREDITKARTE"
        case mac          = "MAC"
    }

    private var original2placeholder: [String: String] = [:]
    private var placeholder2original: [String: String] = [:]
    private var counters: [EntityKind: Int] = [:]
    private let lock = NSLock()

    /// Persistent list from `AppConfig.privacyCustomTerms` — always anonymized
    /// as organizations (the most common use case: company abbreviations, project
    /// code names). Updated by `AppConfig` on every change so this stays live.
    var customTerms: [String] = [] {
        didSet { customTerms = customTerms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
    }

    /// Observable for the Settings UI — total unique entities in the current session.
    @Published private(set) var totalEntities: Int = 0

    /// Read-only snapshot of a session mapping — `placeholder ↔ original`. Used
    /// by the Privacy popover in Office Mode to show the user exactly what's
    /// been substituted. Kind is derived from the placeholder's prefix.
    struct MappingEntry: Identifiable {
        let placeholder: String
        let original: String
        let kind: EntityKind
        var id: String { placeholder }
    }

    /// Current session mapping sorted by kind then by number (`NAME_1`, `NAME_2`, …).
    /// Snapshot is taken under the lock; safe to call from any thread.
    func orderedMappings() -> [MappingEntry] {
        lock.lock()
        let snapshot = placeholder2original
        lock.unlock()
        return snapshot.compactMap { (placeholder, original) -> MappingEntry? in
            for kind in EntityKind.allCases {
                if placeholder.hasPrefix("[\(kind.rawValue)_") {
                    return MappingEntry(placeholder: placeholder, original: original, kind: kind)
                }
            }
            return nil
        }
        .sorted { a, b in
            if a.kind.rawValue != b.kind.rawValue { return a.kind.rawValue < b.kind.rawValue }
            // Numeric sort by trailing index so NAME_10 comes after NAME_2.
            func index(_ s: String) -> Int {
                guard let open = s.firstIndex(of: "_") else { return 0 }
                let num = s[s.index(after: open)..<s.index(before: s.endIndex)]
                return Int(num) ?? 0
            }
            return index(a.placeholder) < index(b.placeholder)
        }
    }

    // MARK: - Public API

    /// Scans `text`, substitutes detected PII with stable placeholders, and returns
    /// the rewritten string. Safe to call with an empty string.
    func anonymize(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var matches: [Match] = []
        matches.append(contentsOf: findEmails(in: text))
        matches.append(contentsOf: findIBANs(in: text))
        matches.append(contentsOf: findCreditCards(in: text))
        matches.append(contentsOf: findMACAddresses(in: text))
        matches.append(contentsOf: findIPs(in: text))
        matches.append(contentsOf: findURLs(in: text))
        matches.append(contentsOf: findAddresses(in: text))
        matches.append(contentsOf: findPhones(in: text))
        matches.append(contentsOf: findNames(in: text))
        matches.append(contentsOf: findCustomTerms(in: text))
        let accepted = dedupe(matches)
        guard !accepted.isEmpty else { return text }

        lock.lock()
        var result = text as NSString
        var perKindInThisCall: [EntityKind: Int] = [:]
        // Apply replacements back-to-front so earlier NSRanges stay valid.
        for match in accepted.sorted(by: { $0.range.location > $1.range.location }) {
            let placeholder = placeholderForLocked(original: match.text, kind: match.kind)
            result = result.replacingCharacters(in: match.range, with: placeholder) as NSString
            perKindInThisCall[match.kind, default: 0] += 1
        }
        let snapshot = placeholder2original.count
        lock.unlock()

        DispatchQueue.main.async { self.totalEntities = snapshot }
        Log.write("Privacy: anonymized " + perKindInThisCall
                    .map { "\($0.key.rawValue.lowercased())=\($0.value)" }
                    .sorted()
                    .joined(separator: " ")
                  + " (total unique=\(snapshot))")
        return result as String
    }

    /// Rewrites `text` back into the user's real terms by swapping any placeholder
    /// that appears in it with the original value we stored during `anonymize(_:)`.
    /// Unknown placeholders pass through unchanged.
    func deanonymize(_ text: String) -> String {
        lock.lock()
        let snapshot = placeholder2original
        lock.unlock()
        guard !snapshot.isEmpty else { return text }
        // Replace longer keys first so `[NAME_10]` doesn't get matched as `[NAME_1]` + "0]".
        let keys = snapshot.keys.sorted { $0.count > $1.count }
        var result = text
        for key in keys {
            if let original = snapshot[key] {
                result = result.replacingOccurrences(of: key, with: original)
            }
        }
        return result
    }

    /// Drops the entire session mapping. Called from `AppConfig.privacyMode` when
    /// the toggle goes from true → false (defense-in-depth: if the user turns
    /// privacy off we don't keep a PII table lying around) and on app quit.
    func reset() {
        lock.lock()
        let hadAny = !original2placeholder.isEmpty
        original2placeholder.removeAll()
        placeholder2original.removeAll()
        counters.removeAll()
        lock.unlock()
        DispatchQueue.main.async { self.totalEntities = 0 }
        if hadAny { Log.write("Privacy: mapping reset") }
    }

    // MARK: - Mapping

    /// Must be called with `lock` held.
    private func placeholderForLocked(original: String, kind: EntityKind) -> String {
        if let existing = original2placeholder[original] { return existing }
        let c = (counters[kind] ?? 0) + 1
        counters[kind] = c
        let placeholder = "[\(kind.rawValue)_\(c)]"
        original2placeholder[original] = placeholder
        placeholder2original[placeholder] = original
        return placeholder
    }

    // MARK: - Detection

    private struct Match {
        let range: NSRange
        let text: String
        let kind: EntityKind
    }

    private func findNames(in text: String) -> [Match] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        var found: [Match] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                             unit: .word,
                             scheme: .nameType,
                             options: options) { tag, tokenRange in
            guard let tag else { return true }
            let kind: EntityKind?
            switch tag {
            case .personalName:     kind = .person
            case .organizationName: kind = .organization
            case .placeName:        kind = .place
            default:                kind = nil
            }
            if let kind {
                let substring = String(text[tokenRange])
                // Skip single-character "names" — NLTagger occasionally flags
                // initials or punctuation residue, and a placeholder for one char
                // would garble the text.
                if substring.count >= 2 {
                    found.append(Match(range: NSRange(tokenRange, in: text),
                                       text: substring,
                                       kind: kind))
                }
            }
            return true
        }
        return found
    }

    /// Case-insensitive whole-word match for user-supplied terms. Categorized as
    /// `.organization` by default since that's the most common intent (short
    /// company abbreviations NLTagger misses). Using word boundaries avoids a
    /// short term eating the middle of a longer unrelated word.
    private func findCustomTerms(in text: String) -> [Match] {
        guard !customTerms.isEmpty else { return [] }
        var matches: [Match] = []
        let nsText = text as NSString
        for term in customTerms {
            // Escape regex metacharacters in the term itself.
            let escaped = NSRegularExpression.escapedPattern(for: term)
            let pattern = #"\b"# + escaped + #"\b"#
            guard let regex = try? NSRegularExpression(pattern: pattern,
                                                       options: .caseInsensitive) else { continue }
            let found = regex.matches(in: text,
                                      range: NSRange(location: 0, length: nsText.length))
            for m in found {
                matches.append(Match(range: m.range,
                                     text: nsText.substring(with: m.range),
                                     kind: .organization))
            }
        }
        return matches
    }

    private func findEmails(in text: String) -> [Match] {
        let pattern = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
        return regexMatches(in: text, pattern: pattern, kind: .email)
    }

    private func findIPs(in text: String) -> [Match] {
        // IPv4 + IPv6 (the full `a:b:c:d:e:f:g:h` form — shorthand `::`
        // notation is left for later; it's uncommon in dictation).
        let v4 = #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#
        let v6 = #"\b(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}\b"#
        return regexMatches(in: text, pattern: v4, kind: .ip)
            + regexMatches(in: text, pattern: v6, kind: .ip)
    }

    /// Postal addresses — street + house number + ZIP + city, in any locale
    /// Apple's system parser understands. `NSDataDetector(.address)` does the
    /// heavy lifting here so we don't maintain a country-specific regex.
    private func findAddresses(in text: String) -> [Match] {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.address.rawValue
        ) else { return [] }
        let nsText = text as NSString
        let matches = detector.matches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        )
        return matches.map {
            Match(range: $0.range,
                  text: nsText.substring(with: $0.range),
                  kind: .address)
        }
    }

    /// International Bank Account Numbers. Format: two-letter country + two
    /// check digits + 11–30 alphanumeric (often displayed in blocks of four).
    /// We don't run the mod-97 check — for PII detection matching the shape
    /// and length window is enough; false-positive risk is low because the
    /// `XX00…` prefix rarely occurs accidentally.
    private func findIBANs(in text: String) -> [Match] {
        let pattern = #"\b[A-Z]{2}\d{2}(?:[ ]?[A-Z0-9]{4}){3,7}(?:[ ]?[A-Z0-9]{1,4})?\b"#
        let raw = regexMatches(in: text, pattern: pattern, kind: .iban)
        return raw.filter { m in
            let stripped = m.text.filter { $0.isLetter || $0.isNumber }
            return stripped.count >= 15 && stripped.count <= 34
        }
    }

    /// Credit / debit card numbers. Regex catches 13–19 digit sequences
    /// (optionally in 4-digit groups), then a Luhn check filters out random
    /// long numbers that happen to match the shape (order numbers, reference
    /// IDs, etc.) — essential to keep false-positives down.
    private func findCreditCards(in text: String) -> [Match] {
        let pattern = #"\b(?:\d[ -]?){12,18}\d\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        )
        return matches.compactMap { m -> Match? in
            let substr = nsText.substring(with: m.range)
            let digits = substr.filter(\.isNumber)
            guard (13...19).contains(digits.count) else { return nil }
            guard luhn(digits) else { return nil }
            return Match(range: m.range, text: substr, kind: .creditCard)
        }
    }

    /// MAC addresses in the `aa:bb:cc:dd:ee:ff` or dash-separated form.
    /// Cisco-style dotted-quad `aaaa.bbbb.cccc` not covered — add if demand.
    private func findMACAddresses(in text: String) -> [Match] {
        let pattern = #"\b(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b"#
        return regexMatches(in: text, pattern: pattern, kind: .mac)
    }

    /// Standard Luhn algorithm used for credit-card checksum validation.
    private func luhn(_ digits: String) -> Bool {
        let nums = digits.compactMap { $0.wholeNumberValue }
        guard nums.count >= 2 else { return false }
        var sum = 0
        for (idx, digit) in nums.reversed().enumerated() {
            if idx.isMultiple(of: 2) {
                sum += digit
            } else {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            }
        }
        return sum.isMultiple(of: 10)
    }

    private func findURLs(in text: String) -> [Match] {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else { return [] }
        let nsText = text as NSString
        let matches = detector.matches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        )
        return matches.compactMap { m in
            // Skip `mailto:` (already caught by email regex) and `tel:`
            // (caught by phone detector) so we don't double-substitute.
            if let scheme = m.url?.scheme?.lowercased(),
               scheme == "mailto" || scheme == "tel" {
                return nil
            }
            return Match(range: m.range,
                         text: nsText.substring(with: m.range),
                         kind: .url)
        }
    }

    private func findPhones(in text: String) -> [Match] {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue
        ) else { return [] }
        let nsText = text as NSString
        let matches = detector.matches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        )
        return matches.compactMap { m in
            let substr = nsText.substring(with: m.range)
            // Reject anything with fewer than 7 digits — filters out dates,
            // time ranges ("17:30–18:00"), version numbers, etc.
            guard substr.filter(\.isNumber).count >= 7 else { return nil }
            return Match(range: m.range, text: substr, kind: .phone)
        }
    }

    private func regexMatches(in text: String,
                              pattern: String,
                              kind: EntityKind) -> [Match] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        )
        return matches.map {
            Match(range: $0.range,
                  text: nsText.substring(with: $0.range),
                  kind: kind)
        }
    }

    // MARK: - Overlap resolution

    /// When two detectors flag overlapping ranges (e.g. URL + phone on the same
    /// token) the longer match wins. Greedy, one pass, O(n²) but `n` is tiny.
    private func dedupe(_ items: [Match]) -> [Match] {
        let sorted = items.sorted { $0.range.length > $1.range.length }
        var accepted: [Match] = []
        for item in sorted {
            let overlap = accepted.contains {
                NSIntersectionRange($0.range, item.range).length > 0
            }
            if !overlap { accepted.append(item) }
        }
        return accepted
    }
}
