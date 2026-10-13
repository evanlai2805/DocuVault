import XCTest
@testable import DocuVaultCore

/// Wordings the keyboard's hold menu offers for nationality and sex (checkpoint 15 follow-up).
final class FillVariantsTests: XCTestCase {

    func testSingaporeCodeGivesFourWordings() {
        XCTAssertEqual(FillVariants.nationality("SGP").map(\.text), ["Singaporean", "Singapore", "Singapore citizen", "SGP"])
    }

    func testNRICWordingResolvesToTheSameSet() {
        XCTAssertEqual(FillVariants.nationality("SINGAPORE CITIZEN").map(\.text), ["Singaporean", "Singapore", "Singapore citizen", "SGP"])
        XCTAssertEqual(FillVariants.nationality("singaporean").map(\.id), ["demonym", "country", "citizen", "code"])
    }

    func testUnknownNationalityPassesThrough() {
        XCTAssertEqual(FillVariants.nationality("Ruritanian").map(\.text), ["Ruritanian"])
        XCTAssertEqual(FillVariants.nationality("").count, 0)
    }

    func testSexOffersLetterAndWord() {
        XCTAssertEqual(FillVariants.sex("F").map(\.text), ["F", "Female"])
        XCTAssertEqual(FillVariants.sex("male").map(\.text), ["M", "Male"])
        XCTAssertEqual(FillVariants.sex("女").map(\.text), ["F", "Female"])
        XCTAssertEqual(FillVariants.sex("X").map(\.text), ["X"])
    }

    func testOnlyNationalityCountryAndSexHaveVariants() {
        XCTAssertEqual(FillVariants.variants(fieldKey: "issuingCountry", value: "MYS").map(\.text), ["Malaysian", "Malaysia", "Malaysia citizen", "MYS"])
        XCTAssertTrue(FillVariants.variants(fieldKey: "surname", value: "CHAI").isEmpty)
    }

    func testVariantIDsAreStableForRemembering() {
        let a = FillVariants.nationality("SGP"), b = FillVariants.nationality("Singapore")
        XCTAssertEqual(a.map(\.id), b.map(\.id))
    }
}
