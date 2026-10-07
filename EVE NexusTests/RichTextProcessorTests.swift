import SwiftSoup
import XCTest
@testable import EVE_Nexus

final class RichTextProcessorTests: XCTestCase {
    func testEVELinkDoesNotIncludeFollowingSentence() throws {
        let input = "Reclamation of <url=showinfo:96789>Mutated Blood Samples</url> leads to glorification."
        let document = try SwiftSoup.parse(RichTextProcessor.normalizeEVELinks(input))
        let link = try XCTUnwrap(document.select("url").first())
        XCTAssertEqual(try link.attr("href"), "showinfo:96789")
        XCTAssertEqual(try link.text(), "Mutated Blood Samples")
        XCTAssertEqual(RichTextProcessor.plainText(from: input),
                       "Reclamation of Mutated Blood Samples leads to glorification.")
    }

    func testQuotedLinksAndExistingHTML() throws {
        let input = "中文 <URL='showinfo:96789'>样本</URL> <url=\"https://example.com/?a=1&amp;b=2\">外部</url> 后文"
        let document = try SwiftSoup.parse(RichTextProcessor.normalizeEVELinks(input))
        let links = try document.select("url").array()
        XCTAssertEqual(links.count, 2)
        XCTAssertEqual(try links[0].attr("href"), "showinfo:96789")
        XCTAssertEqual(try links[1].attr("href"), "https://example.com/?a=1&b=2")
        XCTAssertEqual(try links[1].text(), "外部")
        let standard = "<a href=\"showinfo:96789\">样本</a><url href=\"showinfo:96789\">样本</url>"
        XCTAssertEqual(RichTextProcessor.normalizeEVELinks(standard), standard)
    }
}
