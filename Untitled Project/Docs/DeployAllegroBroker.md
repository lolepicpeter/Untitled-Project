# Deploy Allegro Broker on Render

Use this guide to make `https://api.snapbuy.sk` work for Allegro login.

## What You Are Building

The app cannot send users directly back from Allegro with `invoiceflow://...` because Allegro requires an HTTP/HTTPS redirect URL. So you need a tiny backend broker:

```text
https://api.snapbuy.sk/allegro/oauth/start
https://api.snapbuy.sk/allegro/oauth/callback
https://api.snapbuy.sk/health
```

The backend source is on disk at:

```text
Backend/allegro-broker
```

## Step 1: Push Project to GitHub

Render deploys from GitHub. Push this project repository to GitHub first.

## Step 2: Create Render Web Service

In Render:

1. Create a new Web Service.
2. Connect your GitHub repository.
3. Set Root Directory:

```text
Backend/allegro-broker
```

4. Set Build Command:

```text
npm install
```

5. Set Start Command:

```text
npm start
```

## Step 3: Add Render Environment Variables

Create a Render Postgres database first. In the database's **Connect** menu, copy the **Internal Database URL** and add it to the web service as `DATABASE_URL`.

Add these in Render Environment settings:

```text
PUBLIC_BASE_URL=https://api.snapbuy.sk
APP_CALLBACK_URL=invoiceflow://allegro/connected
ALLEGRO_ENV=production
ALLEGRO_CLIENT_ID=your-allegro-client-id
ALLEGRO_CLIENT_SECRET=your-allegro-client-secret
DATABASE_URL=your-render-postgres-internal-database-url
```

Use your real Allegro Developer Portal values for `ALLEGRO_CLIENT_ID` and `ALLEGRO_CLIENT_SECRET`.

Do not run production users without `DATABASE_URL`. Without Postgres, the broker stores Allegro connections in memory, so Render restarts, redeploys, or service sleep can force users to disconnect and reconnect.

## Step 4: Add Custom Domain in Render

In Render, add this custom domain:

```text
api.snapbuy.sk
```

Render will show a DNS target, usually something ending with:

```text
.onrender.com
```

## Step 5: Add FORPSI DNS Record

In FORPSI DNS for `snapbuy.sk`, add:

```text
Type: CNAME
Hostname: api
TTL: 1800
Hodnota: the-render-target.onrender.com
```

Do not include `https://` in the DNS value.

## Step 6: Register Allegro Redirect URL

In Allegro Developer Portal, set the redirect/application path to:

```text
https://api.snapbuy.sk/allegro/oauth/callback
```

## Step 7: Configure the App

In the app:

```text
Integrations -> Allegro -> Broker URL
```

enter:

```text
https://api.snapbuy.sk
```

Then tap Connect Allegro.

## Test

After DNS and HTTPS are ready, open:

```text
https://api.snapbuy.sk/health
```

It should return JSON.

Confirm the JSON includes:

```json
{
  "storage": "postgres"
}
```

Then open:

```text
https://api.snapbuy.sk/allegro/oauth/start
```

After connecting Allegro, the app imports orders through:

```text
https://api.snapbuy.sk/allegro/connections/{connectionID}/orders
```

Render must be redeployed after backend changes before order import works.

It should redirect to Allegro login.
