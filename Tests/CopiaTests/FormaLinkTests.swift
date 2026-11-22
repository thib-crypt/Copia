import XCTest

final class FormaLinkTests: XCTestCase {
    private let all = CaptureOptions()

    func testFormaImageWithFileIsImageNotFiles() {
        // Forma écrit l'image optimisée ET son fichier : c'est une image, pas une copie de fichier.
        let types = ["public.file-url", "org.webmproject.webp", FormaStamp.pasteboardType, "org.nspasteboard.source"]
        XCTAssertEqual(ContentClassifier.classify(types: types, plainText: nil, options: all),
                       .image(type: "org.webmproject.webp"))
    }

    func testFormaFileOnlyStaysFiles() {
        // Réglage Forma « Fichier seulement » : aucune image, on garde le fichier.
        let types = ["public.file-url", FormaStamp.pasteboardType]
        XCTAssertEqual(ContentClassifier.classify(types: types, plainText: nil, options: all), .files)
    }

    func testAVIFIsAnImage() {
        XCTAssertEqual(ContentClassifier.classify(types: ["public.avif"], plainText: nil, options: all),
                       .image(type: "public.avif"))
        XCTAssertEqual(ContentClassifier.fileExtension(forImageType: "public.avif"), "avif")
    }

    func testStampDecodesFormaJSON() throws {
        let json = #"{"version":1,"originalHash":"img:00ff","originalBytes":1000,"bytes":250,"format":"WebP","ext":"webp","rule":"Captures d'écran","savingsPercent":75,"sourceApp":"com.apple.Safari","file":"/tmp/x.webp"}"#
        let s = try XCTUnwrap(FormaStamp.decode(Data(json.utf8)))
        XCTAssertEqual(s.originalHash, "img:00ff")
        XCTAssertEqual(s.savingsPercent, 75)
        XCTAssertEqual(s.sourceApp, "com.apple.Safari")
        XCTAssertNil(FormaStamp.decode(Data("pas du json".utf8)))
    }

    func testMetaRoundTripKeepsFormaInfo() {
        var m = ClipMeta(width: 10, height: 10, format: "webp")
        m.forma = FormaInfo(savingsPercent: 62, format: "WebP", rule: "Photos", originalBlob: "a.png", originalHash: "img:1")
        let back = ClipMeta.decode(m.encoded())
        XCTAssertEqual(back.forma?.originalBlob, "a.png")
        XCTAssertEqual(back.forma?.badge, "−62 %")
        XCTAssertTrue(back.forma?.hasOriginal == true)
    }

    func testHashMatchesFormaDigest() {
        // Forma calcule le même hash (SHA-256, 16 premiers octets, préfixe img:) pour retrouver la copie d'origine.
        XCTAssertEqual(ClipHasher.hash(data: Data("abc".utf8), prefix: "img:"), "img:ba7816bf8f01cfea414140de5dae2223")
    }
}
