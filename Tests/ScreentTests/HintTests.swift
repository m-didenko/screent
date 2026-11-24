import Testing
@testable import Screent

@Suite struct HintTests {
    @Test func parsesAllFields() {
        let h = Hint.parse("TIP: Обговорюють кешування.\nEN: \"Could we cache it per user?\"\nUA: Може, кешувати для кожного користувача?")
        #expect(h.tip == "Обговорюють кешування.")
        #expect(h.en == "Could we cache it per user?")
        #expect(h.ua == "Може, кешувати для кожного користувача?")
        #expect(!h.isEmpty)
    }

    @Test func multilineAndEnglishOnly() {
        let h = Hint.parse("TIP: They debate retries.\nNobody mentioned idempotency.\nEN: Are the endpoints idempotent?")
        #expect(h.tip == "They debate retries. Nobody mentioned idempotency.")
        #expect(h.ua.isEmpty)
    }

    @Test func nothingToAdd() {
        #expect(Hint.parse("TIP: —").isEmpty)
        #expect(Hint.parse("").isEmpty)
    }
}
