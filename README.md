# INGRIA iOS

INGRIA is a SwiftUI ingredient screening app for food, supplements, beauty, personal-care, and household products. The active Xcode project is:

`INGRIA.xcodeproj`

Brand line:

`Kein Kompromiss. Nur Klarheit.`

INGRIA is an informational screening tool. It does not certify legal compliance, medical safety, or regulatory approval.

## Current Backend

Supabase is the only active backend.

Firebase files and packages have been removed from the active app. Do not add Firebase back unless there is a deliberate migration plan.

Main backend file:

`INGRIA/Services/SupabaseManager.swift`

Current Supabase tables expected by the app:

- `products`
- `scan_logs`
- `missing_product_submissions`
- `review_queue`
- `ingredient_rules`
- `product_store_availability`
- `product_alternatives`
- `ingredient_alternatives`
- `user_reports`

Current Supabase Storage bucket:

- `product-submissions`

Paste `SupabaseMigration.sql` into the Supabase SQL editor to create the starter schema.

## Product Flow

1. Scan or enter a barcode.
2. Check Supabase `products` first.
3. If the product is approved/admin-reviewed, show that trusted INGRIA result.
4. If not found, check local/public product sources.
5. If ingredient data is missing or unclear, create/update `missing_product_submissions` and mirror into `review_queue` when available.
6. Save the scan attempt to `scan_logs`.
7. Admin approves/rejects/requests more ingredients from the in-app admin review screen.
8. Approved products are written back to `products` and become the first result on future scans.

## Search Behaviour

Search now detects intent before querying:

- Mostly numeric input is treated as a barcode/GTIN first.
- Ingredient terms such as `sucralose`, `phenoxyethanol`, `parfum`, `maltodextrin`, or `glucose syrup` must match `ingredients_text`.
- Product and brand terms such as `Dove`, `Nivea`, or `Coca Cola` search product names and brands.

Search result rows show why the item matched:

- Product name match
- Brand match
- Barcode match
- Ingredient match
- Related product name match

Ingredient searches are intentionally strict. If an ingredient is not inside the product ingredient text, the app should not show it as an ingredient match.

## Upload Review Flow

When a product or ingredient photo is uploaded:

1. The image is compressed and uploaded to Supabase Storage bucket `product-submissions`.
2. The app writes/updates a row in `missing_product_submissions`.
3. The app mirrors that row into `review_queue` when the table is available.
4. The row uses `admin_review_status = pending_review`.
5. If OCR finds readable ingredients, the app may show a temporary photo/OCR-assisted result, but it is still queued for manual review.
6. If no readable ingredients are detected, the app does not classify Clean / Review / Avoid.

Manual review statuses:

- `pending_review`
- `needs_more_info`
- `approved_clean`
- `approved_review`
- `approved_avoid`
- `rejected_unusable`

Where to check uploads in Supabase:

- Images: `Storage` → bucket `product-submissions` → folder named by barcode.
- Pending rows: `Table Editor` → `missing_product_submissions`.
- Admin queue mirror: `Table Editor` → `review_queue`.
- Trusted products after approval: `Table Editor` → `products`.

Only approved/admin-reviewed products should be treated as trusted INGRIA results.

## Local Data

`INGRIA/Resources/food.json` is a large local test data dump and is intentionally ignored by git. Keep it locally for simulator testing, but do not commit it to GitHub.

Smaller bundled resources such as ingredient rules, aliases, beauty data, and German seed products are committed.

## Build

```bash
xcodebuild -project INGRIA.xcodeproj -scheme INGRIA -destination 'platform=iOS Simulator,name=iPhone 17' build
```

## App Store-Safe Copy

Use:

- EU-focused ingredient screening
- based on available ingredient data
- no obvious concern found
- more information or human review may be needed
- significant concern found based on INGRIA screening criteria
- source data may be incomplete
- informational screening only

Avoid:

- guaranteed safe
- EU approved
- legally compliant
- medically safe
- toxic
- dangerous
- causes disease
- officially approved

## TestFlight Checklist

- Build succeeds in Xcode.
- No Firebase references remain in the active app target.
- Supabase tables and Storage bucket exist.
- Barcode scan succeeds on device.
- Missing ingredient flow uploads front/ingredient photos.
- Admin approval writes approved products into `products`.
- German UI is the default and English is available as fallback.
