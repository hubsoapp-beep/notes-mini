import Foundation

/// One place for "compare text the way a person expects".
///
/// Search fields must find `zolc` when the user types `żółć`, and `usmiech` when they type
/// `uśmiech`. Foundation's `folding(options: .diacriticInsensitive)` handles most of it, but not
/// `ł`, `đ` and `ø` — those are distinct letters rather than accented ones, so they survive the
/// fold and have to be transliterated first. Every search in the app goes through here.
public enum TextFold {
    public static func fold(_ s: String) -> String {
        let transliterated = s.replacingOccurrences(of: "ł", with: "l")
            .replacingOccurrences(of: "Ł", with: "L")
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "ø", with: "o")
        return transliterated.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US")
        )
    }
}
