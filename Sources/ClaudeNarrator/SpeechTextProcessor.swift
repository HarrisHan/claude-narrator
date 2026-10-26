import Foundation

enum SpeechTextProcessor {
  private static let maximumSpokenCharacters = 360

  static func prepareForSummarization(_ input: String) -> String {
    var text = input
    text = replace(#"(?s)```.*?```"#, in: text, with: "\n")
    text = replace(#"!\[([^\]]*)\]\([^)]*\)"#, in: text, with: "")
    text = replace(#"\[([^\]]+)\]\((?:https?://|/)[^)]*\)"#, in: text, with: "$1")
    text = replace(#"<https?://[^>]+>"#, in: text, with: "")
    text = replace(#"(?i)https?://[^\s<>()]+"#, in: text, with: "")
    text = replace(#"(?m)^\s{0,3}#{1,6}\s*"#, in: text, with: "")
    text = replace(#"(?m)^\s*>\s?"#, in: text, with: "")
    text = replace(#"(?m)^\s*[-*+]\s+"#, in: text, with: "")
    text = replace(#"(?m)^\s*\d+[.)]\s+"#, in: text, with: "")
    text = replace(#"(?m)^\s*[-:| ]{4,}\s*$"#, in: text, with: "")
    text = replace(#"<[^>]+>"#, in: text, with: "")
    text = text.replacingOccurrences(of: "`", with: "")
    text = text.replacingOccurrences(of: "**", with: "")
    text = text.replacingOccurrences(of: "__", with: "")
    text = text.replacingOccurrences(of: "~~", with: "")
    text = text.replacingOccurrences(of: "|", with: "，")
    text = normalizeWhitespace(text)
    return text
  }

  // Preserve the complete reply and its order; only adapt formatting for speech.
  static func narration(_ input: String) -> String {
    let text = makeSpeechSafe(input)
    return text.isEmpty ? "Claude 的这次回复主要是代码或链接，具体内容请看终端。" : text
  }

  static func heuristicSummary(_ input: String) -> String {
    let cleaned = prepareForSummarization(input)
    guard !cleaned.isEmpty else {
      return "Claude Code 已完成本轮任务，详细结果请查看终端。"
    }

    let sentences = sentenceCandidates(cleaned)
      .filter { $0.count >= 2 }
      .filter { !isNoise($0) }

    guard !sentences.isEmpty else {
      return "Claude Code 已完成本轮任务，详细结果请查看终端。"
    }

    let ranked = sentences.enumerated().map { index, sentence in
      (index: index, sentence: sentence, score: score(sentence, index: index))
    }
    let selected =
      ranked
      .sorted {
        if $0.score == $1.score { return $0.index < $1.index }
        return $0.score > $1.score
      }
      .prefix(4)
      .sorted { $0.index < $1.index }
      .map(\.sentence)

    var result = selected.joined(separator: "。")
    result = makeSpeechSafe(result)
    if result.count > maximumSpokenCharacters {
      result = String(result.prefix(maximumSpokenCharacters))
      if let lastStop = result.lastIndex(where: { "。！？".contains($0) }) {
        result = String(result[...lastStop])
      } else {
        result += "。"
      }
    }
    return result
  }

  static func makeSpeechSafe(_ input: String) -> String {
    var text = prepareForSummarization(input)
    text = replace(#"(?i)\bhttps?\b"#, in: text, with: "")
    text = replacingLongPaths(in: text)
    text = replace(#"\b[0-9a-fA-F]{12,}\b"#, in: text, with: "版本标识")
    text = replace(#"[*_~#<>\[\]{}]"#, in: text, with: "")
    text = replace(#"\s*[:：]\s*/+"#, in: text, with: "，")
    text = replace(#"[[:blank:]]+"#, in: text, with: " ")
    text = replace(#"\s*\n\s*"#, in: text, with: "\n")
    text = replace(#"[。]{2,}"#, in: text, with: "。")
    text = replace(#"[，]{2,}"#, in: text, with: "，")
    return text.trimmingCharacters(
      in: .whitespacesAndNewlines)
  }

  private static func sentenceCandidates(_ text: String) -> [String] {
    let withBreaks = replace(#"([。！？!?；;])"#, in: text, with: "$1\n")
    return
      withBreaks
      .components(separatedBy: .newlines)
      .map {
        $0.trimmingCharacters(
          in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "。！？!?；;")))
      }
      .filter { !$0.isEmpty }
  }

  private static func score(_ sentence: String, index: Int) -> Int {
    var value = max(0, 5 - index)
    let highPriority = ["失败", "错误", "无法", "未通过", "需要", "注意", "风险"]
    let outcome = ["完成", "成功", "修复", "解决", "通过", "实现", "已创建", "已更新"]
    let evidence = ["测试", "构建", "编译", "修改", "新增", "删除", "下一步", "文件"]
    value += highPriority.filter(sentence.contains).count * 8
    value += outcome.filter(sentence.contains).count * 6
    value += evidence.filter(sentence.contains).count * 3
    if sentence.range(of: #"\d+"#, options: .regularExpression) != nil { value += 2 }
    if ["我先", "接下来我会", "我准备", "让我"].contains(where: sentence.contains) { value -= 8 }
    if sentence.count > 180 { value -= 3 }
    return value
  }

  private static func isNoise(_ sentence: String) -> Bool {
    if sentence.range(
      of: #"^(?:https?|www\.|/Users/|/tmp/)"#, options: [.regularExpression, .caseInsensitive])
      != nil
    {
      return true
    }
    if sentence.range(of: #"^[\W_]+$"#, options: .regularExpression) != nil { return true }
    let lowercased = sentence.lowercased()
    return lowercased == "sources" || lowercased == "source" || lowercased == "参考链接"
  }

  private static func replacingLongPaths(in input: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: #"(?:/[A-Za-z0-9_.~%+@-]+){2,}(?::\d+)?"#)
    else {
      return input
    }
    var result = input
    let matches = regex.matches(in: input, range: NSRange(input.startIndex..., in: input))
    for match in matches.reversed() {
      guard let range = Range(match.range, in: result) else { continue }
      let path = String(result[range])
      let withoutLine = path.replacingOccurrences(
        of: #":\d+$"#, with: "", options: .regularExpression)
      let filename = URL(fileURLWithPath: withoutLine).lastPathComponent
      result.replaceSubrange(range, with: filename.isEmpty ? "文件" : filename)
    }
    return result
  }

  private static func normalizeWhitespace(_ input: String) -> String {
    var text = replace(#"[[:blank:]]+"#, in: input, with: " ")
    text = replace(#"\n[[:blank:]]+"#, in: text, with: "\n")
    text = replace(#"\n{3,}"#, in: text, with: "\n\n")
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func replace(_ pattern: String, in input: String, with template: String) -> String
  {
    input.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
  }
}
