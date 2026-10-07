import Foundation

/// Safe arithmetic expression evaluator (recursive descent).
///
/// NSExpression is avoided on purpose: it raises Objective-C exceptions (which
/// crash the app) on malformed input like "2+" or "foo".
///
/// Supports + − × ÷ ^ %, parentheses, unary minus, implicit multiplication
/// ("2pi", "3(4+1)"), constants pi/π and e, and functions sqrt, abs, sin, cos,
/// tan (radians), ln, log (base 10), round, floor, ceil.
struct ExpressionEvaluator {
    enum EvalError: LocalizedError, Equatable {
        case unexpected(String), unknown(String), empty, divisionByZero
        var errorDescription: String? {
            switch self {
            case .unexpected(let token): "Unexpected “\(token)”"
            case .unknown(let name): "Unknown “\(name)”"
            case .empty: "Type an expression"
            case .divisionByZero: "Can't divide by zero"
            }
        }
    }

    private let chars: [Character]
    private var index = 0

    static func evaluate(_ text: String) throws -> Double {
        let normalized = text
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: ",", with: "")
        var parser = ExpressionEvaluator(chars: Array(normalized))
        parser.skipSpaces()
        guard !parser.atEnd else { throw EvalError.empty }
        let value = try parser.parseExpression()
        parser.skipSpaces()
        guard parser.atEnd else { throw EvalError.unexpected(String(parser.chars[parser.index])) }
        return value
    }

    private init(chars: [Character]) { self.chars = chars }

    private var atEnd: Bool { index >= chars.count }
    private var current: Character? { atEnd ? nil : chars[index] }

    private mutating func skipSpaces() {
        while let c = current, c.isWhitespace { index += 1 }
    }

    // expression := term (('+' | '-') term)*
    private mutating func parseExpression() throws -> Double {
        var value = try parseTerm()
        while true {
            skipSpaces()
            guard let c = current, c == "+" || c == "-" else { return value }
            index += 1
            let rhs = try parseTerm()
            value = c == "+" ? value + rhs : value - rhs
        }
    }

    // term := factor (('*' | '/' | '%') factor | implicit factor)*
    private mutating func parseTerm() throws -> Double {
        var value = try parseFactor()
        while true {
            skipSpaces()
            guard let c = current else { return value }
            if c == "*" || c == "/" || c == "%" {
                index += 1
                let rhs = try parseFactor()
                switch c {
                case "*": value *= rhs
                case "/":
                    guard rhs != 0 else { throw EvalError.divisionByZero }
                    value /= rhs
                default:
                    guard rhs != 0 else { throw EvalError.divisionByZero }
                    value = value.truncatingRemainder(dividingBy: rhs)
                }
            } else if c == "(" || c.isLetter || c == "π" {
                // Implicit multiplication: 2pi, 3(4+1)
                value *= try parseFactor()
            } else {
                return value
            }
        }
    }

    // factor := unary ('^' factor)?
    private mutating func parseFactor() throws -> Double {
        let base = try parseUnary()
        skipSpaces()
        if current == "^" {
            index += 1
            return pow(base, try parseFactor()) // right-associative
        }
        return base
    }

    private mutating func parseUnary() throws -> Double {
        skipSpaces()
        if current == "-" { index += 1; return -(try parseUnary()) }
        if current == "+" { index += 1; return try parseUnary() }
        return try parsePrimary()
    }

    private mutating func parsePrimary() throws -> Double {
        skipSpaces()
        guard let c = current else { throw EvalError.unexpected("end") }
        if c == "(" {
            index += 1
            let value = try parseExpression()
            skipSpaces()
            guard current == ")" else { throw EvalError.unexpected(current.map(String.init) ?? "end") }
            index += 1
            return value
        }
        if c.isNumber || c == "." {
            let start = index
            while let d = current, d.isNumber || d == "." { index += 1 }
            // Scientific notation: 1e3, 2.5e-4
            if let e = current, e == "e" || e == "E",
               index + 1 < chars.count, chars[index + 1].isNumber || ((chars[index + 1] == "-" || chars[index + 1] == "+") && index + 2 < chars.count && chars[index + 2].isNumber) {
                index += 2
                while let d = current, d.isNumber { index += 1 }
            }
            let text = String(chars[start..<index])
            guard let value = Double(text) else { throw EvalError.unexpected(text) }
            return value
        }
        if c == "π" { index += 1; return .pi }
        if c.isLetter {
            let start = index
            while let l = current, l.isLetter { index += 1 }
            let name = String(chars[start..<index]).lowercased()
            switch name {
            case "pi": return .pi
            case "e": return M_E
            default: break
            }
            let functions: [String: (Double) -> Double] = [
                "sqrt": { $0.squareRoot() }, "abs": { Swift.abs($0) }, "sin": { Foundation.sin($0) },
                "cos": { Foundation.cos($0) }, "tan": { Foundation.tan($0) }, "ln": { Foundation.log($0) },
                "log": { Foundation.log10($0) }, "round": { $0.rounded() }, "floor": { $0.rounded(.down) },
                "ceil": { $0.rounded(.up) },
            ]
            guard let function = functions[name] else { throw EvalError.unknown(name) }
            return function(try parseFactor())
        }
        throw EvalError.unexpected(String(c))
    }
}
