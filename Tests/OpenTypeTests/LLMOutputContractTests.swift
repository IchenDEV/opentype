import XCTest
@testable import OpenType

final class LLMOutputContractTests: XCTestCase {
    func testVoiceCommandPromptsAdvertiseFinalTextJSONContract() {
        for language in InputLanguage.allCases {
            let prompt = PromptBuilder.buildCommandSystemPrompt(
                screenContext: "",
                inputLanguage: language
            )

            XCTAssertTrue(prompt.contains("final_text"), "\(language)")
        }
    }

    func testSelectionEditPromptsAdvertiseFinalTextJSONContract() {
        let processor = TextProcessor()
        for language in InputLanguage.allCases {
            let prompt = processor.selectionEditSystemPrompt(inputLanguage: language)

            XCTAssertTrue(prompt.contains("final_text"), "\(language)")
        }
    }

    func testVoiceCommandOutputExtractsWrappedFinalText() {
        let processor = TextProcessor()
        let output = """
        I will use the requested format:
        {"final_text":"Sounds good, I will send the release notes today.","reason":"reply"}
        """

        XCTAssertEqual(
            processor.cleanCommandGeneratedOutput(output, inputLanguage: .english),
            "Sounds good, I will send the release notes today."
        )
    }

    func testSelectionEditOutputExtractsWrappedFinalText() {
        let processor = TextProcessor()
        let output = """
        {"final_text":"Please send the release notes today.","reason":"made it formal"}
        """

        XCTAssertEqual(
            processor.cleanSelectionEditOutput(output, inputLanguage: .english),
            "Please send the release notes today."
        )
    }
}
