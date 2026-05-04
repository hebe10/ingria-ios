// IngredientParserTests
//
// Unit tests for the paren-aware tokenizer in IngredientExtractor and the
// coverage-gated verdict logic in ProductAuditor. To run these:
//   1. In Xcode, File > New > Target… > iOS Unit Testing Bundle named
//      "INGRIATests" pointing at this folder.
//   2. Add this file + IngredientExtractor.swift + ProductAuditor.swift +
//      IngredientGuideStore.swift + IngriaModels.swift to the test target.
//
// These tests cover the cases called out in the audit brief.

import XCTest
@testable import INGRIA

final class IngredientParserTests: XCTestCase {

    // MARK: - Top-level tokenization with parentheses

    func testSimpleListSplitsOnTopLevelCommas() {
        let tokens = IngredientExtractor.tokenize("Water, Glycerin (and) Phenoxyethanol")
        let normalized = tokens.map { IngredientExtractor.normalize($0) }
        XCTAssertTrue(normalized.contains("water"))
        XCTAssertTrue(normalized.contains("glycerin and phenoxyethanol")
                      || normalized.contains("glycerin and  phenoxyethanol")
                      || normalized.contains("phenoxyethanol"))
    }

    func testNestedSubIngredientsAreEmittedSeparately() {
        let tokens = IngredientExtractor.tokenize("Modified starch (tapioca, corn, wheat)")
        let normalized = Set(tokens.map { IngredientExtractor.normalize($0) })
        XCTAssertTrue(normalized.contains("tapioca"))
        XCTAssertTrue(normalized.contains("corn"))
        XCTAssertTrue(normalized.contains("wheat"))
    }

    func testDeeplyNestedParenthesesDoNotSplitAtInteriorCommas() {
        let text = "Chocolate coating (sugar, cocoa butter, cocoa mass, emulsifier: lecithin (soya))"
        let tokens = IngredientExtractor.tokenize(text)
        let normalized = Set(tokens.map { IngredientExtractor.normalize($0) })
        XCTAssertTrue(normalized.contains("sugar"))
        XCTAssertTrue(normalized.contains("cocoa butter"))
        XCTAssertTrue(normalized.contains("cocoa mass"))
        XCTAssertTrue(normalized.contains("soya"))
    }

    func testPercentagesAreStripped() {
        let tokens = IngredientExtractor.tokenize("Palm oil (50%), Water (30%)")
        let normalized = tokens.map { IngredientExtractor.normalize($0) }
        XCTAssertTrue(normalized.contains(where: { $0.contains("palm oil") }))
        XCTAssertTrue(normalized.contains(where: { $0.contains("water") }))
        for token in normalized {
            XCTAssertFalse(token.contains("%"))
        }
    }

    func testGermanLabelMarkerIsStripped() {
        let tokens = IngredientExtractor.tokenize("Zutaten: Zucker, Palmöl, Aroma")
        let normalized = Set(tokens.map { IngredientExtractor.normalize($0) })
        XCTAssertTrue(normalized.contains("zucker"))
        XCTAssertTrue(normalized.contains("palmol"))
        XCTAssertTrue(normalized.contains("aroma"))
        XCTAssertFalse(normalized.contains("zutaten"))
    }

    func testENumberRangeExpands() {
        let tokens = IngredientExtractor.tokenize("E471-E473")
        let normalized = Set(tokens.map { IngredientExtractor.normalize($0) })
        XCTAssertTrue(normalized.contains("e471"))
        XCTAssertTrue(normalized.contains("e472"))
        XCTAssertTrue(normalized.contains("e473"))
    }

    func testSlashVariantsSplit() {
        let tokens = IngredientExtractor.tokenize("Aqua/Water, Glycerin, Phenoxyethanol")
        let normalized = Set(tokens.map { IngredientExtractor.normalize($0) })
        XCTAssertTrue(normalized.contains("aqua"))
        XCTAssertTrue(normalized.contains("water"))
        XCTAssertTrue(normalized.contains("glycerin"))
        XCTAssertTrue(normalized.contains("phenoxyethanol"))
    }

    func testFootnoteAsterisksAreStripped() {
        let tokens = IngredientExtractor.tokenize("Sunflower oil*, rapeseed oil*")
        let normalized = tokens.map { IngredientExtractor.normalize($0) }
        for token in normalized {
            XCTAssertFalse(token.contains("*"))
        }
        XCTAssertTrue(normalized.contains(where: { $0.contains("sunflower oil") }))
        XCTAssertTrue(normalized.contains(where: { $0.contains("rapeseed oil") }))
    }

    func testBracketedPrefixIsStripped() {
        let tokens = IngredientExtractor.tokenize("[Zutaten: Zucker, Palmöl] Hinweis: kann Spuren enthalten")
        let normalized = Set(tokens.map { IngredientExtractor.normalize($0) })
        XCTAssertTrue(normalized.contains("zucker"))
        XCTAssertTrue(normalized.contains("palmol"))
        // The "Hinweis…" portion should be cut by the end-marker logic.
        XCTAssertFalse(normalized.contains(where: { $0.contains("hinweis") }))
    }

    // MARK: - Verdict / coverage gating

    func testEmptyTextReturnsInsufficientData() {
        var store = IngredientGuideStore()
        try? store.load()
        let auditor = ProductAuditor(guide: store)
        let audit = auditor.auditLabelText("", productName: "Empty", category: "food")
        XCTAssertEqual(audit.finalStatus, .insufficientData)
    }

    func testAvoidIngredientOverridesCoverage() {
        var store = IngredientGuideStore()
        try? store.load()
        let auditor = ProductAuditor(guide: store)
        let audit = auditor.auditLabelText(
            "Zutaten: Zucker, Wasser, mysteryunknownX, anotherunknownY",
            productName: "Avoid override",
            category: "food"
        )
        // Sugar is a direct AVOID rule; it must win regardless of unknowns.
        XCTAssertEqual(audit.finalStatus, .avoid)
    }

    func testLowCoveragePreventsClean() {
        var store = IngredientGuideStore()
        try? store.load()
        let auditor = ProductAuditor(guide: store)
        // None of these tokens are in the database — coverage will be 0.
        let audit = auditor.auditLabelText(
            "Ingredients: alphaUnknownA, betaUnknownB, gammaUnknownC, deltaUnknownD",
            productName: "Low coverage",
            category: "food"
        )
        XCTAssertNotEqual(audit.finalStatus, .clean)
        XCTAssertEqual(audit.finalStatus, .insufficientData)
        XCTAssertGreaterThan(audit.unknownIngredientCount, 0)
        XCTAssertTrue(audit.isPartialResult)
    }

    func testUnknownIngredientsAreTracked() {
        var store = IngredientGuideStore()
        try? store.load()
        let auditor = ProductAuditor(guide: store)
        let audit = auditor.auditLabelText(
            "Zutaten: Wasser, weirdNonexistentIngredientZZ",
            productName: "Unknown tracking",
            category: "food"
        )
        XCTAssertGreaterThan(audit.unknownIngredients.count, 0)
        XCTAssertEqual(audit.totalIngredientCount, audit.recognizedIngredientCount + audit.unknownIngredientCount)
    }
}
