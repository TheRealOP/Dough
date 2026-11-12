import Foundation

/// Keyword-based category guesses for receipt line items.
enum Categorizer {
    static func category(forItem name: String, merchant: String?) -> SpendingCategory {
        let merchant = merchant ?? ""
        if matches(merchant, keywords: diningMerchants) { return .dining }
        for (category, keywords) in itemKeywords where matches(name, keywords: keywords) {
            return category
        }
        for (category, keywords) in merchantKeywords where matches(merchant, keywords: keywords) {
            return category
        }
        return .other
    }

    /// Word-token match: keywords of 4+ characters may prefix a token ("banana" matches "bananas"),
    /// shorter ones must equal a token ("tea" doesn't match "steak"); multi-word keywords match as a phrase.
    static func matches(_ text: String, keywords: [String]) -> Bool {
        let tokens = text.lowercased().split(whereSeparator: { !$0.isLetter }).map { String($0) }
        let phrase = " " + tokens.joined(separator: " ")
        return keywords.contains { keyword in
            if keyword.contains(" ") { return phrase.contains(" " + keyword) }
            if keyword.count >= 4 { return tokens.contains { $0.hasPrefix(keyword) } }
            return tokens.contains(keyword)
        }
    }

    private static let diningMerchants = [
        "restaurant", "cafe", "café", "coffee", "diner", "grill", "pizza", "pizzeria", "burger", "taco", "sushi",
        "bistro", "bar", "pub", "tavern", "kitchen", "eatery", "starbucks", "mcdonald", "chipotle", "subway",
        "dunkin", "wendy", "chick fil a",
    ]

    private static let itemKeywords: [(SpendingCategory, [String])] = [
        (.groceries, [
            "banana", "apple", "orange", "lemon", "grape", "berries", "avocado", "tomato", "potato", "onion",
            "carrot", "lettuce", "produce", "milk", "cheese", "butter", "yogurt", "egg", "eggs", "bread", "bagel",
            "flour", "sugar", "rice", "pasta", "cereal", "chicken", "beef", "pork", "steak", "fish", "salmon",
            "juice", "soda", "cola", "coke", "water", "tea", "coffee", "chips", "cookie", "cracker", "snack",
            "beer", "wine",
        ]),
        (.household, [
            "paper towel", "toilet paper", "towel", "tissue", "napkin", "detergent", "laundry", "bleach", "dish",
            "sponge", "cleaner", "trash", "foil", "battery", "batteries", "bulb", "candle",
        ]),
        (.personalCare, [
            "shampoo", "conditioner", "toothpaste", "toothbrush", "floss", "deodorant", "lotion", "razor",
            "soap", "body wash", "sunscreen", "makeup", "cosmetic",
        ]),
        (.health, [
            "vitamin", "ibuprofen", "advil", "tylenol", "aspirin", "allergy", "bandage", "band aid", "medicine",
            "cough", "antacid", "supplement", "prescription", "rx",
        ]),
        (.transport, ["unleaded", "diesel", "fuel", "gasoline", "parking", "toll", "fare", "transit", "metro"]),
        (.entertainment, ["movie", "cinema", "ticket", "concert", "game", "netflix", "spotify", "dvd"]),
        (.shopping, [
            "shirt", "pants", "jeans", "dress", "jacket", "sock", "socks", "shoe", "hat", "toy", "greeting card",
            "gift", "charger", "cable", "headphone",
        ]),
    ]

    private static let merchantKeywords: [(SpendingCategory, [String])] = [
        (.groceries, [
            "grocer", "market", "supermarket", "foods", "bakery", "trader joe", "safeway", "kroger", "aldi",
            "costco", "publix", "wegmans",
        ]),
        (.health, ["pharmacy", "drug", "cvs", "walgreens", "rite aid"]),
        (.transport, ["shell", "chevron", "exxon", "mobil", "gas", "fuel", "parking", "uber", "lyft"]),
        (.household, ["home depot", "lowe", "ikea", "hardware"]),
        (.personalCare, ["salon", "barber", "sephora", "ulta"]),
        (.entertainment, ["cinema", "theater", "theatre", "amc"]),
        (.shopping, ["amazon", "mall", "apparel", "best buy"]),
    ]
}
