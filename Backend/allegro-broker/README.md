# Allegro OAuth Broker

This broker exists because Allegro requires an HTTP/HTTPS redirect URI in the Developer Portal. The native app opens this backend, the backend redirects the seller to Allegro, Allegro redirects back to the backend, and the backend returns the seller to the app with a connection ID.

## Allegro Developer Portal

Use this application type:

- Browser-access application
- Grant type: `authorization_code`
- Redirect URI: `https://your-domain.example/allegro/oauth/callback`

The redirect URI must match `PUBLIC_BASE_URL + /allegro/oauth/callback`.

## Environment

Copy `.env.example` into your hosting provider's environment variables.

Required values:

- `PUBLIC_BASE_URL`: public HTTPS URL where this broker is reachable
- `APP_CALLBACK_URL`: app callback URL, usually `invoiceflow://allegro/connected`
- `ALLEGRO_CLIENT_ID`: Allegro app client ID
- `ALLEGRO_CLIENT_SECRET`: Allegro app client secret
- `ALLEGRO_ENV`: `production` or `sandbox`
- `DATABASE_URL`: Postgres connection string for persistent Allegro connections

## Local Run

```sh
npm install
npm start
```

For real Allegro login, the broker must be reachable through HTTPS. For local testing, expose it with a tunnel and use that HTTPS URL in `PUBLIC_BASE_URL` and Allegro Developer Portal.

## Deploy

Use Render first unless you already have another hosting provider. Follow:

```text
DEPLOY_RENDER.md
```

## Storage

When `DATABASE_URL` is set, the broker creates an `allegro_connections` table and stores seller Allegro tokens in Postgres. It refreshes expired access tokens before fetching orders.

When `DATABASE_URL` is missing, the broker falls back to in-memory storage. That is only useful for local development because every restart, deploy, or free-hosting sleep clears the connection and forces the seller to reconnect.
