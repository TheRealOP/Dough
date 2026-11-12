# Roadmap

Things deliberately not in v1, roughly in priority order.

## 1. Card linking

- **Apple FinanceKit first** (Apple Card, Apple Cash, Apple Savings). Data stays on-device. Requires Apple's FinanceKit entitlement, which has to be requested.
- **Plaid (or similar) for other cards.** Needs a small backend to hold access tokens. That would be the one place data leaves the device, so it must be strictly opt-in and clearly explained.

## 2. Receipt ↔ transaction matching

Match a scanned receipt to a card transaction when:

- the amount is within a tolerance (tips, pre-authorization holds, currency rounding),
- the date is within ±3 days,
- the merchant name is a fuzzy match (card descriptors are often truncated or uppercased).

Card transactions with no matching receipt become "no receipt" entries, so totals stay complete.

## 3. Subscription detection

Flag a subscription when the same merchant charges a similar amount on a regular cadence (about weekly, monthly or yearly) for at least 3 charges.

## 4. Deeper analysis

- Rule-based "unusual purchase" flags, e.g. an item priced far above its usual price.
- Longer time ranges (period picker, year view, trends).
- Optional, opt-in cloud model for harder questions.
- Larger local models as devices allow.

## 5. Nice-to-haves

- iCloud sync
- Search across receipts and items
- Home-screen widget (budget remaining)
- JSON export
- Weight and unit-price parsing (e.g. "1.25 lb @ $3.99/lb")
