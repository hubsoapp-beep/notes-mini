import Foundation

/// Polish noun inflection for counts, which has three forms rather than two:
/// `1 znak`, `2 znaki`, `5 znaków`. Only exactly one takes the singular — 21 and 101 use the
/// plural — and the 12–14 range irregularly takes the plural despite ending in 2, 3 or 4.
public enum CountText {

    /// - Parameters:
    ///   - one: the singular form, e.g. `znak`
    ///   - few: the 2–4 form, e.g. `znaki`
    ///   - many: the genitive plural, e.g. `znaków`
    public static func polish(_ count: Int, one: String, few: String, many: String) -> String {
        let n = abs(count)
        let mod100 = n % 100
        let mod10 = n % 10
        let noun: String
        if n == 1 {
            noun = one
        } else if (12...14).contains(mod100) {
            noun = many
        } else if (2...4).contains(mod10) {
            noun = few
        } else {
            noun = many
        }
        return "\(count) \(noun)"
    }

    /// `123 znaki`, `1 znak`, `5 znaków`.
    public static func characters(_ count: Int) -> String {
        polish(count, one: "znak", few: "znaki", many: "znaków")
    }
}
