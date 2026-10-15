# Shopkeeper Pro Brand and UI Implementation Rules

**Reference:** `Shopkeeper_Pro_Theme_Logo_Brand_Guide.pdf` (visual concept; not a live-app screenshot).

## Canonical palette

| Token | HEX | Use |
|---|---|---|
| Navy Blue | `#0B3D91` | Primary structure, titles, navigation and key totals |
| Teal Green | `#14B8A6` | Primary actions, selected states and positive status |
| Gold | `#FFBF24` | Important totals, premium highlights and attention states |
| Light Gray | `#F3F4F6` | Page backgrounds and quiet surfaces |
| Dark Navy | `#082B4C` | Dark theme surfaces |

## Shared UI rules

- Use `lib/utils/theme.dart` tokens instead of new one-off brand colours.
- Use white cards on a light-gray canvas, rounded corners, subtle borders and comfortable spacing.
- Keep headings bold and clear; make totals and Pakistani Rupee (Rs.) amounts easy to scan.
- Prefer readable form labels and visible validation errors; avoid dense tables on phone screens.
- Use teal for primary action/selected state, navy for structure, and gold only as a highlight—not as the only indicator of an error.
- Keep invoice PDF colours aligned with the guide; thermal receipts may be monochrome for printer compatibility.
- New screens must use the same shared theme, components and spacing patterns. Existing screens still need a screen-by-screen audit for hard-coded colors and visual differences.
- The logo direction is a shopping cart with a rising chart/arrow. Do not treat a concept image as proof that a production logo asset or app icon has been integrated.

## Mobile Shop screen rules

- Use the same navy header/card, teal action controls, gold highlights and light-gray page background.
- Show separate, clearly labelled device and repair-job views.
- Use status labels with text as well as colour.
- Keep IMEI and customer data private; only show them to signed-in shop staff who have access.
- A used device starts at `inspection_pending`; it must not be treated as sale-ready until inspected.
- Never mark a device sold by merely editing its status. The next phase must connect an exact IMEI device to the POS bill and enforce a transactional sale/return workflow.

## Implementation status

The central Flutter theme was aligned to the reference palette and the first Mobile Shop screens use the shared tokens. This is not yet a claim that every existing screen, logo asset, invoice, app icon or dark-mode screen has been visually audited or device-tested.
