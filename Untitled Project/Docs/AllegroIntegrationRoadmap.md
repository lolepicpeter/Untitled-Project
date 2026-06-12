# Allegro Integration Roadmap

## Goal

Build marketplace invoicing around a reviewable import flow:

1. Connect a seller's Allegro account with OAuth.
2. Pull paid or invoice-requested orders from Allegro.
3. Convert each order into an invoice draft.
4. Let the user review VAT, buyer details, delivery, and payment data.
5. Export the PDF from the app.
6. Later upload the issued invoice back to Allegro and prepare structured e-invoice export.

This keeps the first release useful without taking on fully automatic issuing risk before credentials, policies, and tax edge cases are verified.

## Implemented Foundation

- `MarketplaceOrderReference` stores the source, Allegro order ID, import time, and external status on invoices.
- Duplicating an invoice clears marketplace metadata so a copied invoice is not linked to the same Allegro order.
- `AllegroConnectionSettings` stores the public OAuth configuration: environment, client ID, redirect URI, and connected account label.
- `AllegroClient` can build a PKCE OAuth authorization URL, exchange an authorization code for tokens, refresh tokens, and call order event / checkout-form endpoints with a bearer token.
- `AllegroOAuthConnector` opens the Allegro login page with `ASWebAuthenticationSession`, validates callback state, exchanges the code, and stores tokens in Keychain.
- The app had a custom URL scheme callback prepared, but Allegro Developer Portal rejects non-HTTP(S) redirect protocols. Production OAuth needs an HTTPS callback URL, usually handled by a backend token broker.
- `AllegroCheckoutForm` and related models decode the order data needed for invoice drafts.
- `AllegroInvoiceMapper` converts an Allegro order into an `Invoice` draft and can create a matching `Client`.
- Backup/restore includes Allegro connection settings while older backups still decode. Tokens are intentionally excluded from backups.
- The main app includes an Integrations section with an Allegro tile that opens a Baselinker-style Connect / Disconnect screen. Settings links to the same screen.
- `Backend/allegro-broker` contains a Node/Express OAuth broker scaffold. Register `https://your-domain.example/allegro/oauth/callback` in Allegro Developer Portal, with the domain matching the broker `PUBLIC_BASE_URL`.
- The app can open the broker, receive `invoiceflow://allegro/connected?connection_id=...`, and store the broker connection ID locally.

## Next Backend/Auth Work

Do not store an Allegro client secret in the app. The native app now uses PKCE and Keychain storage, but it still needs real Allegro Developer Portal credentials before live login can succeed.

Required pieces:

- registered production and sandbox Allegro apps
- an HTTPS OAuth callback URL registered in Allegro Developer Portal
- a small backend token broker to receive Allegro's authorization code and exchange it using the app credentials
- app-side handling for a backend-issued connection/session result after the seller grants access
- connected account identity lookup after login, replacing the temporary "Allegro account" label
- token refresh scheduling and expired-token recovery in import flows
- account disconnect and token revocation handling
- last imported event ID per seller account

## Import Workflow

Recommended first app workflow:

- Add an "Import from Allegro" action in Invoices.
- Fetch order events since the last cursor.
- Resolve checkout forms for relevant paid/order-ready events.
- Filter orders that already have an invoice with the same `MarketplaceOrderReference.orderID`.
- Show an import review list.
- Generate invoice drafts only after user confirmation.

## Invoice Mapping Rules

Current draft mapping assumes Allegro item prices are gross and converts them to net using the decoded VAT rate or app default VAT rate. This must be verified against real Allegro payloads before automatic issuing.

Review before release:

- gross vs net source values
- delivery VAT treatment
- discounts and surcharges
- invoice-requested vs receipt-only orders
- B2B buyer tax ID formats
- cross-border currency and VAT cases
- cancelled/refunded orders and credit notes

## Later Product Scope

After manual import works reliably:

- upload issued PDF invoices back to Allegro
- generate invoices automatically after paid order events
- add payment reminders outside Allegro orders
- add credit notes for refunds
- add EN 16931/UBL export for Slovakia e-invoicing readiness
- add additional marketplaces only after Allegro order import is stable
