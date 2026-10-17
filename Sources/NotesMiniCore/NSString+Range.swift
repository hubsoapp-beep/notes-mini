import Foundation

extension NSString {
    /// `substring(with:)` takes an NSRange; the whole markdown pipeline works with `Range<Int>`
    /// (UTF-16 offsets) because that is what `NSAttributedString` and TextKit use.
    func substring(with r: Range<Int>) -> String {
        let lo = max(0, min(r.lowerBound, length))
        let hi = max(lo, min(r.upperBound, length))
        return substring(with: NSRange(location: lo, length: hi - lo))
    }
}
/// `NSMaxRange` only accepts NSRange; the parser speaks `Range<Int>`.
func maxRange(_ r: Range<Int>) -> Int { max(0, r.upperBound) }
func maxRange(_ r: NSRange) -> Int { NSMaxRange(r) }
func nsRange(_ r: Range<Int>) -> NSRange {
    NSRange(location: max(0, r.lowerBound), length: max(0, r.upperBound - r.lowerBound))
}
