import Foundation

struct NumberParser {
    private struct Token {
        let value: String
        let range: NSRange
    }

    private let units: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4,
        "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
        "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]

    private let digitWords: [String: String] = [
        "zero": "0", "one": "1", "two": "2", "three": "3",
        "four": "4", "five": "5", "six": "6", "seven": "7",
        "eight": "8", "nine": "9",
    ]

    private let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]

    private let scales: [String: Int] = [
        "thousand": 1_000,
        "million": 1_000_000,
    ]

    private let maximumWords = 12

    func suggestion(in text: String, globalOffset: Int = 0) -> NumberSuggestion? {
        let nsText = text as NSString
        let meaningfulEnd = trailingContentEnd(in: nsText)
        guard meaningfulEnd > 0 else { return nil }

        let content = nsText.substring(with: NSRange(location: 0, length: meaningfulEnd))
        let tokens = tokenize(content)
        guard !tokens.isEmpty else { return nil }

        let cappedStart = max(0, tokens.count - maximumWords)
        for start in cappedStart..<tokens.count {
            let slice = Array(tokens[start...])
            guard separatorsAreValid(between: slice, in: content) else { continue }
            let words = slice.map(\.value)

            let result: (String, [String], NumberSuggestion.Kind)?
            if let chunks = parseSpokenSequence(words) {
                result = (
                    chunks.joined(),
                    chunks.count > 1 ? [chunks.joined(separator: " ")] : [],
                    .digitSequence
                )
            } else if let value = parseCompound(words) {
                result = (String(value), [], .compound)
            } else {
                result = nil
            }

            guard let result else { continue }
            let localRange = NSRange(
                location: slice[0].range.location,
                length: NSMaxRange(slice[slice.count - 1].range) - slice[0].range.location
            )
            return NumberSuggestion(
                originalText: (content as NSString).substring(with: localRange),
                replacement: result.0,
                alternatives: result.1,
                range: NSRange(location: globalOffset + localRange.location, length: localRange.length),
                kind: result.2
            )
        }
        return nil
    }

    private func trailingContentEnd(in text: NSString) -> Int {
        var end = text.length
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        while end > 0 {
            let scalar = UnicodeScalar(text.character(at: end - 1))
            guard let scalar, separators.contains(scalar) else { break }
            end -= 1
        }
        return end
    }

    private func tokenize(_ text: String) -> [Token] {
        let regex = try! NSRegularExpression(pattern: "[A-Za-z]+")
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        return regex.matches(in: text, range: fullRange).map { match in
            Token(
                value: (text as NSString).substring(with: match.range).lowercased(),
                range: match.range
            )
        }
    }

    private func separatorsAreValid(between tokens: [Token], in text: String) -> Bool {
        guard tokens.count > 1 else { return true }
        let nsText = text as NSString
        for index in 1..<tokens.count {
            let previousEnd = NSMaxRange(tokens[index - 1].range)
            let gap = NSRange(location: previousEnd, length: tokens[index].range.location - previousEnd)
            let separator = nsText.substring(with: gap)
            // Newlines, tabs, and other layout whitespace separate phrases.
            // Only ordinary word spacing and hyphens may join number words.
            if separator.range(of: #"^[ \u00A0-]+$"#, options: .regularExpression) == nil {
                return false
            }
        }
        return true
    }

    // Without a scale word, interpret speech as a sequence of numeric chunks
    // rather than adding every word together. A tens word plus a following
    // non-zero digit is one conventional compound chunk (`twenty one` -> 21).
    // Everything else remains its own chunk (`one two ten` -> 1, 2, 10).
    private func parseSpokenSequence(_ words: [String]) -> [String]? {
        guard !words.isEmpty,
              !words.contains("and"),
              !words.contains("hundred"),
              !words.contains(where: { scales[$0] != nil }) else {
            return nil
        }

        var chunks: [String] = []
        var index = 0
        while index < words.count {
            let word = words[index]
            if let digit = digitWords[word] {
                chunks.append(digit)
                index += 1
                continue
            }

            if let value = units[word], value >= 10 {
                chunks.append(String(value))
                index += 1
                continue
            }

            if let ten = tens[word] {
                if index + 1 < words.count,
                   let digit = digitWords[words[index + 1]],
                   digit != "0" {
                    chunks.append(String(ten + Int(digit)!))
                    index += 2
                } else {
                    chunks.append(String(ten))
                    index += 1
                }
                continue
            }

            return nil
        }
        return chunks
    }

    private func parseCompound(_ words: [String]) -> Int? {
        guard !words.isEmpty else { return nil }
        var total = 0
        var current = 0
        var sawNumber = false

        for word in words {
            if word == "and" { continue }
            if let unit = units[word] {
                current += unit
                sawNumber = true
            } else if let ten = tens[word] {
                current += ten
                sawNumber = true
            } else if word == "hundred" {
                guard current > 0 else { return nil }
                current *= 100
            } else if let scale = scales[word] {
                guard current > 0 else { return nil }
                total += current * scale
                current = 0
            } else {
                return nil
            }
        }
        return sawNumber ? total + current : nil
    }
}
