# Country Lookup Candidates

This file is the implementation queue for automatic company lookup.

The app can show every country in the picker, but a country should only move from manual entry to automatic lookup when it has a practical adapter in the backend.

## Already Implemented

| Country | Code | Adapter | Source | Notes |
|---|---:|---|---|---|
| Slovakia | SK | `sk-orsf.js` | ORSF | Public Slovak-register API, good enough for autocomplete and detail fill. |
| Czech Republic | CZ | `cz-ares.js` | ARES | Official Czech economic-subject API. Name search needs backend ranking/fallback. |
| Norway | NO | `no-brreg.js` | Brønnøysund Register Centre | Official open API for Enhetsregisteret/organisation data. |
| Finland | FI | `fi-prh.js` | PRH/YTJ Open Data | Official Finnish open data under CC BY 4.0. |

## Practical Candidates

These are good candidates for backend adapters because they have official/open sources that look usable for commercial-product style lookup. Terms still need a final review before production deployment.

| Priority | Country | Code | Source | Implementation Shape | Notes |
|---:|---|---:|---|---|---|
| 1 | United Kingdom | GB | Companies House API | Live API adapter | Official API, free to use, API key required. Good search/detail coverage for UK companies. |
| 2 | Estonia | EE | RIK e-Business Register open data | Dataset adapter | Machine-readable open data exists. Likely better as backend-indexed lookup rather than direct live autocomplete. |
| 3 | Denmark | DK | CVR / Danish Central Business Register | API adapter, likely more work | Official register data is available programmatically, but integration may be SOAP/legacy or require extra source verification. |
| 4 | EU VAT | EU | VIES | Validation-only adapter | Useful for VAT ID validation across EU, but not a company-name lookup source. Add as a separate validation feature. |

## Manual For Now

Do not add automatic lookup for these until we confirm practical commercial API access.

| Country | Reason |
|---|---|
| Netherlands | KVK has APIs, but practical search/profile APIs appear paid/subscription-oriented. Keep manual unless using a paid provider. |
| Sweden | Official Bolagsverket data exists, but API access appears agreement/fee based for richer access. Keep manual unless using paid access. |
| Germany | Company data is fragmented across registers and official access/search is not as simple as one free autocomplete API. Needs deeper research or paid provider. |
| Austria | Needs deeper review for free commercial API suitability. Keep manual until confirmed. |
| France | Has SIRENE data/API options, but implementation and terms should be reviewed separately before adding. |
| Italy | Needs deeper review for free commercial API suitability. Keep manual until confirmed. |
| Spain | Needs deeper review for free commercial API suitability. Keep manual until confirmed. |
| Other countries | Manual entry by default until a reliable source is confirmed and an adapter exists. |

## Adapter Acceptance Checklist

Before adding a country to automatic lookup:

1. Source is official, open, or commercially licensed.
2. Terms allow commercial app/backend usage.
3. Search by company name or national ID is practical.
4. Detail lookup returns enough fields for `CompanyFormData`.
5. Rate limits and API keys can be handled in the backend.
6. Attribution requirements are documented in the app/backend.
7. The adapter has live smoke checks for search and detail endpoints.

## Backend Adapter Naming

Use this pattern:

```text
Backend/src/adapters/{country-code-lowercase}-{source}.js
```

Examples:

```text
gb-companies-house.js
no-brreg.js
fi-prh.js
ee-rik.js
dk-cvr.js
eu-vies.js
```

Register adapters in:

```text
Backend/src/adapters/index.js
```
