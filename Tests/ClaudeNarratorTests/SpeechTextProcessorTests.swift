import XCTest

@testable import ClaudeNarrator

final class SpeechTextProcessorTests: XCTestCase {
  func testNarrationPreservesLongReplyAndFinalCaveat() {
    let input = Array(repeating: "这部分解释了处理流程以及原因。", count: 700).joined() + "但是还没有在生产环境验证。"
    let output = SpeechTextProcessor.narration(input)
    XCTAssertEqual(output, input)
    XCTAssertGreaterThan(output.count, 8_000)
  }

  func testNarrationPreservesQuestionsAndParagraphPauses() {
    let input = "## 处理方式\n先确认配置。\n\n- 可以继续吗？\n- 还不能确定！"
    XCTAssertEqual(SpeechTextProcessor.narration(input), "处理方式\n先确认配置。\n可以继续吗？\n还不能确定！")
  }

  func testNarrationWithoutModelDoesNotSelectFourSentences() async {
    let input = "第一件事。第二件事。第三件事。第四件事。第五件事。第六件事。"
    let result = await SpokenSummarizer.summarize(input, preferModel: false)
    XCTAssertEqual(result.text, input)
  }

  func testMarkdownLinkKeepsLabelButDropsURL() {
    let input = "任务完成。请查看 [官方文档](https://example.com/a/b?q=1)。"
    let output = SpeechTextProcessor.makeSpeechSafe(input)

    XCTAssertTrue(output.contains("官方文档"))
    XCTAssertFalse(output.lowercased().contains("https"))
    XCTAssertFalse(output.contains("example.com"))
  }

  func testBareURLIsNotSpoken() {
    let input = "任务完成，详情：https://example.com/reports/123 。测试已通过。"
    let output = SpeechTextProcessor.makeSpeechSafe(input)

    XCTAssertFalse(output.lowercased().contains("http"))
    XCTAssertFalse(output.contains("example.com"))
    XCTAssertTrue(output.contains("测试已通过"))
  }

  func testFencedCodeIsRemoved() {
    let input = "已修复登录问题。\n```swift\nlet url = \"https://example.com\"\n```\n全部测试通过。"
    let output = SpeechTextProcessor.heuristicSummary(input)

    XCTAssertFalse(output.contains("let url"))
    XCTAssertTrue(output.contains("修复登录问题"))
    XCTAssertTrue(output.contains("测试通过"))
  }

  func testLongFilePathIsShortened() {
    let input = "修改了 /Users/harris/projects/demo/Sources/App.swift:42，构建成功。"
    let output = SpeechTextProcessor.makeSpeechSafe(input)

    XCTAssertFalse(output.contains("/Users/harris"))
    XCTAssertTrue(output.contains("App.swift"))
  }

  func testSummaryIsBounded() {
    let input = Array(repeating: "已经完成一项重要修改并且测试通过。", count: 100).joined()
    let output = SpeechTextProcessor.heuristicSummary(input)

    XCTAssertLessThanOrEqual(output.count, 361)
  }
}
