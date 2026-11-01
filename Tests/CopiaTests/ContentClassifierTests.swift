import XCTest

final class ContentClassifierTests: XCTestCase {
    private let all = CaptureOptions()

    func testFinderCopyIsFilesEvenWithNameAndIcon() {
        // Le Finder met le nom en texte et l'icône en TIFF : ce sont bien des fichiers.
        let types = ["public.file-url", "public.utf8-plain-text", "com.apple.icns", "public.tiff"]
        XCTAssertEqual(ContentClassifier.classify(types: types, plainText: "Rapport.pdf", options: all), .files)
    }

    func testFinderCopyFallsBackToTextWhenFilesDisabled() {
        var o = all; o.files = false
        let types = ["public.file-url", "public.utf8-plain-text", "public.tiff"]
        XCTAssertEqual(ContentClassifier.classify(types: types, plainText: "Rapport.pdf", options: o), .text)
    }

    func testScreenshotIsPNG() {
        XCTAssertEqual(ContentClassifier.classify(types: ["public.png"], plainText: nil, options: all),
                       .image(type: "public.png"))
    }

    func testBrowserCopyImageWithURLIsImage() {
        let types = ["public.html", "public.tiff", "public.utf8-plain-text"]
        XCTAssertEqual(ContentClassifier.classify(types: types, plainText: "https://ex.com/a.png", options: all),
                       .image(type: "public.tiff"))
    }

    func testPrefersPNGOverTIFF() {
        XCTAssertEqual(ContentClassifier.classify(types: ["public.tiff", "public.png"], plainText: "", options: all),
                       .image(type: "public.png"))
    }

    func testWordCopyWithPictureStaysRichText() {
        // Word / Numbers : texte + RTF + aperçu image → c'est du texte mis en forme.
        let types = ["public.rtf", "public.html", "public.utf8-plain-text", "public.png"]
        XCTAssertEqual(ContentClassifier.classify(types: types, plainText: "Bonjour le monde", options: all),
                       .richText(types: ["public.rtf", "public.html"]))
    }

    func testRichTextDisabledGivesPlainText() {
        var o = all; o.richText = false
        XCTAssertEqual(ContentClassifier.classify(types: ["public.rtf", "public.utf8-plain-text"], plainText: "x", options: o),
                       .text)
    }

    func testImagesDisabledIgnoresPureImage() {
        var o = all; o.images = false
        XCTAssertEqual(ContentClassifier.classify(types: ["public.png"], plainText: nil, options: o), .none)
    }

    func testWhitespaceOnlyIsNothing() {
        XCTAssertEqual(ContentClassifier.classify(types: ["public.utf8-plain-text"], plainText: "  \n ", options: all), .none)
    }

    func testMetaRoundTripAndEmpty() {
        XCTAssertNil(ClipMeta.empty.encoded())
        let m = ClipMeta(width: 1920, height: 1080, bytes: 1234, format: "heic", thumb: "a_t.png", hasOCR: true)
        XCTAssertEqual(ClipMeta.decode(m.encoded()), m)
        XCTAssertEqual(ClipMeta.decode(nil), .empty)
        XCTAssertEqual(ClipMeta.decode("pas du json"), .empty)
    }

    func testRichTextSharesHashWithPlainText() {
        // Indispensable pour reconnaître la restauration VoiceInk d'un texte mis en forme.
        XCTAssertEqual(ClipHasher.hash("Bonjour", trimWhitespace: true), ClipHasher.hash(" Bonjour\n", trimWhitespace: true))
        XCTAssertNotEqual(ClipHasher.hash(data: Data([1, 2, 3]), prefix: "img:"), ClipHasher.hash(data: Data([1, 2, 4]), prefix: "img:"))
    }
}
