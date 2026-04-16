import Foundation
import SwiftUI

enum TranscriptBodySegment: Equatable, Sendable {
    case text(String)
    case code(languageHint: String?, code: String)
}

enum TranscriptBodyDisplayMode: Equatable, Sendable {
    case prose
    case automaticCode(languageHint: String?)
}

enum TranscriptCodeLanguage: String, Equatable, Sendable {
    case swift
    case python
    case javascript
    case typescript
    case json
    case shell
    case yaml

    init?(hint: String?) {
        guard let hint else {
            return nil
        }

        switch hint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "swift":
            self = .swift
        case "py", "python":
            self = .python
        case "js", "javascript", "jsx":
            self = .javascript
        case "ts", "typescript", "tsx":
            self = .typescript
        case "json":
            self = .json
        case "bash", "shell", "sh", "zsh":
            self = .shell
        case "yaml", "yml":
            self = .yaml
        default:
            return nil
        }
    }

    var label: String {
        switch self {
        case .swift: "Swift"
        case .python: "Python"
        case .javascript: "JavaScript"
        case .typescript: "TypeScript"
        case .json: "JSON"
        case .shell: "Shell"
        case .yaml: "YAML"
        }
    }
}

enum TranscriptBodyParser {
    static func segments(from text: String) -> [TranscriptBodySegment] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var segments: [TranscriptBodySegment] = []
        var textLines: [String] = []
        var codeLines: [String]? = nil
        var codeLanguage: String?

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if codeLines == nil, trimmedLine.hasPrefix("```") {
                flushTextLines(textLines, into: &segments)
                textLines = []
                codeLines = []
                let infoString = String(trimmedLine.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                codeLanguage = infoString.split(whereSeparator: \.isWhitespace).first.map(String.init)
                continue
            }

            if var existingCodeLines = codeLines {
                if trimmedLine.hasPrefix("```") {
                    flushCodeLines(existingCodeLines, languageHint: codeLanguage, into: &segments)
                    codeLines = nil
                    codeLanguage = nil
                } else {
                    existingCodeLines.append(line)
                    codeLines = existingCodeLines
                }
                continue
            }

            textLines.append(line)
        }

        if let danglingCodeLines = codeLines {
            var reopenedText = ["```" + (codeLanguage.map { " \($0)" } ?? "")]
            reopenedText.append(contentsOf: danglingCodeLines)
            textLines.append(reopenedText.joined(separator: "\n"))
        }

        flushTextLines(textLines, into: &segments)
        return segments.isEmpty ? [.text(normalized)] : segments
    }

    private static func flushTextLines(_ lines: [String], into segments: inout [TranscriptBodySegment]) {
        let text = lines.joined(separator: "\n")
        guard !text.isEmpty else {
            return
        }

        segments.append(.text(text))
    }

    private static func flushCodeLines(
        _ lines: [String],
        languageHint: String?,
        into segments: inout [TranscriptBodySegment]
    ) {
        let code = lines.joined(separator: "\n")
        segments.append(.code(languageHint: languageHint, code: code))
    }
}

struct TranscriptBodyView: View {
    let text: String
    let font: Font
    let foregroundColor: Color
    let textAlignment: TextAlignment
    let frameAlignment: Alignment
    var displayMode: TranscriptBodyDisplayMode = .prose

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let text):
                    TranscriptMarkdownTextView(
                        text: text,
                        font: font,
                        foregroundColor: foregroundColor,
                        textAlignment: textAlignment
                    )

                case .code(let languageHint, let code):
                    TranscriptCodeBlockView(
                        code: code,
                        languageHint: languageHint,
                        frameAlignment: frameAlignment
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    private var segments: [TranscriptBodySegment] {
        let parsedSegments = TranscriptBodyParser.segments(from: text)

        guard case .automaticCode(let languageHint) = displayMode,
              parsedSegments.allSatisfy({
                  if case .text = $0 { return true }
                  return false
              }) else {
            return parsedSegments
        }

        let inferredLanguage = TranscriptCodeDetector.inferLanguageHint(
            preferredHint: languageHint,
            body: text
        )

        guard TranscriptCodeDetector.shouldRenderAsCode(
            text,
            preferredLanguageHint: inferredLanguage
        ) else {
            return parsedSegments
        }

        return [.code(languageHint: inferredLanguage, code: text)]
    }
}

struct TranscriptMarkdownRenderer {
    static func attributedText(from markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )

        guard var attributed = try? AttributedString(markdown: markdown, options: options) else {
            return AttributedString(markdown)
        }

        for run in attributed.runs {
            guard let inlineIntent = run.inlinePresentationIntent else {
                continue
            }

            if inlineIntent.contains(.code) {
                attributed[run.range].font = .system(.body, design: .monospaced)
                attributed[run.range].backgroundColor = Color.primary.opacity(0.08)
            }
        }

        return attributed
    }
}

private struct TranscriptMarkdownTextView: View {
    let text: String
    let font: Font
    let foregroundColor: Color
    let textAlignment: TextAlignment

    var body: some View {
        Text(markdownText)
            .font(font)
            .foregroundStyle(foregroundColor)
            .lineSpacing(4)
            .multilineTextAlignment(textAlignment)
            .fixedSize(horizontal: false, vertical: true)
            .tint(.accentColor)
            .textSelection(.enabled)
    }

    private var markdownText: AttributedString {
        TranscriptMarkdownRenderer.attributedText(from: text)
    }
}

enum TranscriptCodeDetector {
    static func inferLanguageHint(
        preferredHint: String?,
        title: String? = nil,
        body: String
    ) -> String? {
        if TranscriptCodeLanguage(hint: preferredHint) != nil {
            return preferredHint
        }

        for source in [preferredHint, title].compactMap({ $0?.lowercased() }) {
            if source.contains(".swift") { return "swift" }
            if source.contains(".py") { return "python" }
            if source.contains(".ts") || source.contains(".tsx") { return "typescript" }
            if source.contains(".js") || source.contains(".jsx") { return "javascript" }
            if source.contains(".json") { return "json" }
            if source.contains(".yml") || source.contains(".yaml") { return "yaml" }
            if source.contains("zsh") || source.contains("bash") || source.contains(" sh ") { return "shell" }
        }

        let normalizedBody = textWithoutLineNumberPrefixes(body)
        if normalizedBody.contains("import SwiftUI") || normalizedBody.contains("struct ") || normalizedBody.contains("enum ") {
            return "swift"
        }
        if normalizedBody.contains("def ") || normalizedBody.contains("import ") && normalizedBody.contains(":") {
            return "python"
        }
        if normalizedBody.contains("const ") || normalizedBody.contains("function ") || normalizedBody.contains("=>") {
            return "javascript"
        }
        if normalizedBody.contains("interface ") || normalizedBody.contains(": string") || normalizedBody.contains(": number") {
            return "typescript"
        }
        if normalizedBody.contains("{") && normalizedBody.contains("}") && normalizedBody.contains("\"") {
            return "json"
        }

        return preferredHint
    }

    static func shouldRenderAsCode(_ text: String, preferredLanguageHint: String?) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }

        if trimmed.contains("```") {
            return false
        }

        let lines = trimmed.components(separatedBy: "\n")
        guard lines.count >= 2 else {
            return false
        }

        if TranscriptCodeLanguage(hint: preferredLanguageHint) != nil {
            return true
        }

        let normalized = textWithoutLineNumberPrefixes(trimmed)
        let codeSignalCount = [
            normalized.contains("{"),
            normalized.contains("}"),
            normalized.contains("import "),
            normalized.contains("func "),
            normalized.contains("struct "),
            normalized.contains("enum "),
            normalized.contains("class "),
            normalized.contains("let "),
            normalized.contains("var "),
            normalized.contains("def "),
            normalized.contains("return "),
            normalized.contains("const "),
            normalized.contains("=>"),
            normalized.contains(":")
        ]
        .filter { $0 }
        .count

        let numberedLineCount = lines.filter {
            $0.range(of: #"^\s*\d+\s+"#, options: .regularExpression) != nil
        }.count

        return codeSignalCount >= 2 || numberedLineCount >= max(2, lines.count / 2)
    }

    private static func textWithoutLineNumberPrefixes(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"(?m)^\s*\d+\s+"#,
            with: "",
            options: .regularExpression
        )
    }
}

private struct TranscriptCodeBlockView: View {
    @Environment(\.colorScheme) private var colorScheme

    let code: String
    let languageHint: String?
    let frameAlignment: Alignment

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let languageLabel {
                Text(languageLabel)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(highlightedCode)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(codePalette.base)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: frameAlignment)
        .background(codeBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(codeBorder, lineWidth: 1)
        }
    }

    private var languageLabel: String? {
        TranscriptCodeLanguage(hint: languageHint)?.label ?? languageHint?.nonEmpty?.uppercased()
    }

    private var highlightedCode: AttributedString {
        TranscriptCodeHighlighter.highlightedCode(
            code,
            languageHint: languageHint,
            colorScheme: colorScheme
        )
    }

    private var codeBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.09, green: 0.10, blue: 0.12)
            : Color(red: 0.96, green: 0.97, blue: 0.985)
    }

    private var codeBorder: Color {
        colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08)
    }

    private var codePalette: TranscriptCodePalette {
        TranscriptCodePalette(colorScheme: colorScheme)
    }
}

enum TranscriptCodeHighlighter {
    static func highlightedCode(
        _ code: String,
        languageHint: String?,
        colorScheme: ColorScheme
    ) -> AttributedString {
        var attributed = AttributedString(code)
        let palette = TranscriptCodePalette(colorScheme: colorScheme)
        attributed.font = .system(.callout, design: .monospaced)
        attributed.foregroundColor = palette.base

        let language = TranscriptCodeLanguage(hint: languageHint)
        let tokens = mergedTokens(in: code, language: language)

        for token in tokens {
            guard let stringRange = Range(token.range, in: code),
                  let attributedRange = Range(stringRange, in: attributed) else {
                continue
            }

            attributed[attributedRange].foregroundColor = palette.color(for: token.role)
        }

        return attributed
    }

    private static func mergedTokens(in code: String, language: TranscriptCodeLanguage?) -> [TranscriptHighlightToken] {
        let patterns = genericPatterns + patterns(for: language)
        let allTokens = patterns.flatMap { pattern in
            matches(
                for: pattern.regex,
                role: pattern.role,
                priority: pattern.priority,
                in: code
            )
        }

        var selected: [TranscriptHighlightToken] = []

        for token in allTokens.sorted(by: tokenSortComparator) where !selected.contains(where: { $0.range.overlaps(token.range) }) {
            selected.append(token)
        }

        return selected.sorted { $0.range.location < $1.range.location }
    }

    private static var genericPatterns: [TranscriptHighlightPattern] {
        [
            .init(#"(?m)\b\d+(?:\.\d+)?\b"#, role: .number, priority: 1)
        ]
    }

    private static func patterns(for language: TranscriptCodeLanguage?) -> [TranscriptHighlightPattern] {
        switch language {
        case .swift:
            return swiftPatterns
        case .python:
            return pythonPatterns
        case .javascript:
            return javaScriptPatterns
        case .typescript:
            return typeScriptPatterns
        case .json:
            return jsonPatterns
        case .shell:
            return shellPatterns
        case .yaml:
            return yamlPatterns
        case nil:
            return fallbackPatterns
        }
    }

    private static var swiftPatterns: [TranscriptHighlightPattern] {
        [
            .init(#"(?s)/\*.*?\*/|//.*$"#, options: [.anchorsMatchLines], role: .comment, priority: 7),
            .init(#"#?"(?:\\.|[^"\\])*""#, role: .string, priority: 6),
            .init(#"@\w+"#, role: .annotation, priority: 5),
            .init(#"\b(?:actor|any|as|async|await|break|case|catch|class|continue|default|defer|do|else|enum|extension|fallthrough|false|for|func|guard|if|import|in|init|inout|internal|is|let|nil|operator|precedencegroup|private|protocol|public|repeat|required|rethrows|return|self|Self|static|struct|subscript|super|switch|throw|throws|true|try|typealias|var|where|while)\b"#, role: .keyword, priority: 4),
            .init(#"\b(?:Int|String|Bool|Double|Float|Void|Any|Never|Result|Error|URL|Data|Date|UUID|Task|MainActor)\b|(?<!\.)\b[A-Z][A-Za-z0-9_]*\b"#, role: .type, priority: 3)
        ]
    }

    private static var pythonPatterns: [TranscriptHighlightPattern] {
        [
            .init(#"(?s)""".*?"""|'''.*?'''|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|#.*$"#, options: [.anchorsMatchLines], role: .commentOrString, priority: 7),
            .init(#"@\w+"#, role: .annotation, priority: 5),
            .init(#"\b(?:and|as|assert|async|await|break|class|continue|def|del|elif|else|except|False|finally|for|from|global|if|import|in|is|lambda|None|nonlocal|not|or|pass|raise|return|True|try|while|with|yield)\b"#, role: .keyword, priority: 4),
            .init(#"\b(?:dict|list|set|tuple|str|int|float|bool|None)\b|(?<!\.)\b[A-Z][A-Za-z0-9_]*\b"#, role: .type, priority: 3)
        ]
    }

    private static var javaScriptPatterns: [TranscriptHighlightPattern] {
        [
            .init(#"(?s)/\*.*?\*/|//.*$"#, options: [.anchorsMatchLines], role: .comment, priority: 7),
            .init(#"`(?:\\.|[^`\\])*`|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, role: .string, priority: 6),
            .init(#"\b(?:async|await|break|case|catch|class|const|continue|default|delete|else|export|extends|false|finally|for|from|function|if|import|in|instanceof|let|new|null|of|return|super|switch|this|throw|true|try|typeof|var|void|while|yield)\b"#, role: .keyword, priority: 4),
            .init(#"\b[A-Z][A-Za-z0-9_]*\b"#, role: .type, priority: 3)
        ]
    }

    private static var typeScriptPatterns: [TranscriptHighlightPattern] {
        javaScriptPatterns + [
            .init(#"\b(?:implements|interface|keyof|namespace|private|protected|public|readonly|satisfies|type|unknown)\b"#, role: .keyword, priority: 4)
        ]
    }

    private static var jsonPatterns: [TranscriptHighlightPattern] {
        [
            .init(#""(?:\\.|[^"\\])*"(?=\s*:)"#, role: .property, priority: 6),
            .init(#""(?:\\.|[^"\\])*""#, role: .string, priority: 5),
            .init(#"\b(?:true|false|null)\b"#, role: .keyword, priority: 4)
        ]
    }

    private static var shellPatterns: [TranscriptHighlightPattern] {
        [
            .init(#"(?m)#.*$"#, role: .comment, priority: 7),
            .init(#"`(?:\\.|[^`\\])*`|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, role: .string, priority: 6),
            .init(#"\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"#, role: .property, priority: 5),
            .init(#"\b(?:case|do|done|elif|else|esac|export|fi|for|function|if|in|local|readonly|select|source|then|until|while)\b"#, role: .keyword, priority: 4)
        ]
    }

    private static var yamlPatterns: [TranscriptHighlightPattern] {
        [
            .init(#"(?m)#.*$"#, role: .comment, priority: 7),
            .init(#""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, role: .string, priority: 6),
            .init(#"(?m)^\s*-?\s*[A-Za-z0-9_.\"'-]+(?=\s*:)"#, role: .property, priority: 5),
            .init(#"\b(?:true|false|null|yes|no|on|off)\b"#, role: .keyword, priority: 4)
        ]
    }

    private static var fallbackPatterns: [TranscriptHighlightPattern] {
        [
            .init(#"(?s)/\*.*?\*/|//.*$|#.*$"#, options: [.anchorsMatchLines], role: .comment, priority: 7),
            .init(#"`(?:\\.|[^`\\])*`|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, role: .string, priority: 6),
            .init(#"\b(?:false|nil|null|true)\b"#, role: .keyword, priority: 4)
        ]
    }

    private static func matches(
        for regex: NSRegularExpression,
        role: TranscriptHighlightRole,
        priority: Int,
        in code: String
    ) -> [TranscriptHighlightToken] {
        let nsRange = NSRange(code.startIndex..., in: code)
        return regex.matches(in: code, range: nsRange).map {
            TranscriptHighlightToken(range: $0.range, role: role, priority: priority)
        }
    }

    private static func tokenSortComparator(_ lhs: TranscriptHighlightToken, _ rhs: TranscriptHighlightToken) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority > rhs.priority
        }

        if lhs.range.location != rhs.range.location {
            return lhs.range.location < rhs.range.location
        }

        return lhs.range.length > rhs.range.length
    }
}

private struct TranscriptHighlightPattern {
    let regex: NSRegularExpression
    let role: TranscriptHighlightRole
    let priority: Int

    init(
        _ pattern: String,
        options: NSRegularExpression.Options = [],
        role: TranscriptHighlightRole,
        priority: Int
    ) {
        self.regex = try! NSRegularExpression(pattern: pattern, options: options)
        self.role = role
        self.priority = priority
    }
}

private struct TranscriptHighlightToken {
    let range: NSRange
    let role: TranscriptHighlightRole
    let priority: Int
}

private enum TranscriptHighlightRole {
    case comment
    case string
    case keyword
    case number
    case type
    case annotation
    case property
    case commentOrString
}

private extension TranscriptHighlightRole {
    var normalizedRole: TranscriptHighlightRole {
        switch self {
        case .commentOrString:
            .string
        default:
            self
        }
    }
}

private extension NSRange {
    func overlaps(_ other: NSRange) -> Bool {
        NSIntersectionRange(self, other).length > 0
    }
}

private struct TranscriptCodePalette {
    let base: Color
    let comment: Color
    let string: Color
    let keyword: Color
    let number: Color
    let type: Color
    let annotation: Color
    let property: Color

    init(colorScheme: ColorScheme) {
        if colorScheme == .dark {
            base = Color(red: 0.88, green: 0.90, blue: 0.95)
            comment = Color(red: 0.45, green: 0.72, blue: 0.53)
            string = Color(red: 0.96, green: 0.73, blue: 0.47)
            keyword = Color(red: 0.53, green: 0.73, blue: 0.98)
            number = Color(red: 0.90, green: 0.63, blue: 0.95)
            type = Color(red: 0.47, green: 0.87, blue: 0.83)
            annotation = Color(red: 0.98, green: 0.61, blue: 0.74)
            property = Color(red: 0.98, green: 0.86, blue: 0.54)
        } else {
            base = Color(red: 0.16, green: 0.19, blue: 0.25)
            comment = Color(red: 0.24, green: 0.52, blue: 0.31)
            string = Color(red: 0.72, green: 0.38, blue: 0.09)
            keyword = Color(red: 0.17, green: 0.39, blue: 0.80)
            number = Color(red: 0.64, green: 0.30, blue: 0.70)
            type = Color(red: 0.12, green: 0.56, blue: 0.56)
            annotation = Color(red: 0.78, green: 0.27, blue: 0.46)
            property = Color(red: 0.64, green: 0.47, blue: 0.04)
        }
    }

    func color(for role: TranscriptHighlightRole) -> Color {
        switch role.normalizedRole {
        case .comment:
            comment
        case .string:
            string
        case .keyword:
            keyword
        case .number:
            number
        case .type:
            type
        case .annotation:
            annotation
        case .property:
            property
        case .commentOrString:
            string
        }
    }
}
