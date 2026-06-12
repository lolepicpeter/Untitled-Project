# Deploy Allegro Broker on Render

This is the easiest path for the Allegro OAuth broker.

## 1. Put This Project on GitHub

Render deploys from a Git repository. Push this project to GitHub first.

## 2. Create a Render Web Service

In Render:

1. Create a new **Web Service**.
2. Connect the GitHub repository.
3. Set the root directory:

```text
Backend/allegro-broker
```

4. Set build command:

```text
npm install
```

5. Set start command:

```text
npm start
```

## 3. Add Environment Variables

Add these in Render's Environment settings:

```text
PUBLIC_BASE_URL=https://api.snapbuy.sk
APP_CALLBACK_URL=invoiceflow://allegro/connected
ALLEGRO_ENV=production
ALLEGRO_CLIENT_ID=your-allegro-client-id
ALLEGRO_CLIENT_SECRET=your-allegro-client-secret
```

Use the values from Allegro Developer Portal for `ALLEGRO_CLIENT_ID` and `ALLEGRO_CLIENT_SECRET`.

## 4. Add Custom Domain

In Render, add this custom domain:

```text
api.snapbuy.sk
```

Render will show a DNS target. It will usually be a hostname ending in `.onrender.com`.

## 5. Add DNS in FORPSI

In FORPSI DNS for `snapbuy.sk`, add a record:

```text
Type: CNAME
Hostname: api
TTL: 1800
Hodnota: the-target-render-gives-you.onrender.com
```

Do not include `https://` in the DNS value.

## 6. Register Allegro Redirect URL

In Allegro Developer Portal, set the application path / redirect URI to:

```text
https://api.snapbuy.sk/allegro/oauth/callback
```

## 7. Configure the App

In the app:

```text
Integrations -> Allegro -> Broker URL
```

enter:

```text
https://api.snapbuy.sk
```

Then tap **Connect Allegro**.

## Test URLs

After DNS and HTTPS are ready, this should return JSON:

```text
https://api.snapbuy.sk/health
```

This should redirect to Allegro login:

```text
https://api.snapbuy.sk/allegro/oauth/start
```
