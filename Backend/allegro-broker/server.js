import crypto from "node:crypto";
import express from "express";

const app = express();
app.use(express.json());

const port = Number(process.env.PORT || 3001);
const publicBaseURL = requiredEnv("PUBLIC_BASE_URL");
const appCallbackURL = process.env.APP_CALLBACK_URL || "invoiceflow://allegro/connected";
const clientID = requiredEnv("ALLEGRO_CLIENT_ID");
const clientSecret = requiredEnv("ALLEGRO_CLIENT_SECRET");
const environment = process.env.ALLEGRO_ENV === "sandbox" ? "sandbox" : "production";

const allegroBaseURL = environment === "sandbox"
  ? "https://allegro.pl.allegrosandbox.pl"
  : "https://allegro.pl";

const pendingStates = new Map();
const connections = new Map();

const scopes = [
  "allegro:api:orders:read",
  "allegro:api:profile:read"
];

app.get("/health", (request, response) => {
  response.json({ ok: true, service: "invoiceflow-allegro-broker", environment });
});

app.get("/allegro/oauth/start", (request, response) => {
  const state = crypto.randomUUID();
  const callbackURL = new URL(appCallbackURL);
  callbackURL.searchParams.set("state", state);

  pendingStates.set(state, {
    createdAt: Date.now(),
    appCallbackURL: callbackURL.toString()
  });

  const authorizationURL = new URL("/auth/oauth/authorize", allegroBaseURL);
  authorizationURL.searchParams.set("response_type", "code");
  authorizationURL.searchParams.set("client_id", clientID);
  authorizationURL.searchParams.set("redirect_uri", oauthCallbackURL());
  authorizationURL.searchParams.set("state", state);
  authorizationURL.searchParams.set("scope", scopes.join(" "));

  response.redirect(authorizationURL.toString());
});

app.get("/allegro/oauth/callback", async (request, response) => {
  const { code, state, error } = request.query;
  const pending = typeof state === "string" ? pendingStates.get(state) : undefined;

  if (!pending) {
    response.status(400).send("Invalid or expired Allegro OAuth state.");
    return;
  }

  pendingStates.delete(state);

  if (typeof error === "string" && error.length > 0) {
    response.redirect(appCallbackWithError(pending.appCallbackURL, error));
    return;
  }

  if (typeof code !== "string" || code.length === 0) {
    response.redirect(appCallbackWithError(pending.appCallbackURL, "missing_authorization_code"));
    return;
  }

  try {
    const token = await exchangeAuthorizationCode(code);
    const connectionID = crypto.randomUUID();
    connections.set(connectionID, {
      createdAt: Date.now(),
      token
    });

    const callbackURL = new URL(pending.appCallbackURL);
    callbackURL.searchParams.set("connection_id", connectionID);
    response.redirect(callbackURL.toString());
  } catch (tokenError) {
    response.redirect(appCallbackWithError(pending.appCallbackURL, "token_exchange_failed"));
  }
});

app.get("/allegro/connections/:connectionID", (request, response) => {
  const connection = connections.get(request.params.connectionID);
  if (!connection) {
    response.status(404).json({ error: { message: "Connection not found." } });
    return;
  }

  response.json({
    id: request.params.connectionID,
    connected: true,
    createdAt: new Date(connection.createdAt).toISOString(),
    expiresAt: new Date(connection.token.expiresAt).toISOString()
  });
});

app.get("/allegro/connections/:connectionID/orders", async (request, response) => {
  const connection = connections.get(request.params.connectionID);
  if (!connection) {
    response.status(404).json({ error: { message: "Connection not found." } });
    return;
  }

  const limit = clampNumber(Number(request.query.limit || 25), 1, 100);

  try {
    const orders = await recentCheckoutForms(connection.token.access_token, limit);
    response.json({ orders });
  } catch (error) {
    response.status(502).json({
      error: {
        message: error instanceof Error ? error.message : "Could not fetch Allegro orders."
      }
    });
  }
});

app.delete("/allegro/connections/:connectionID", (request, response) => {
  connections.delete(request.params.connectionID);
  response.status(204).end();
});

app.listen(port, () => {
  console.log(`Allegro broker listening on port ${port}`);
});

function requiredEnv(name) {
  const value = process.env[name];
  if (!value || value.trim().length === 0) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value.trim();
}

function oauthCallbackURL() {
  return new URL("/allegro/oauth/callback", publicBaseURL).toString();
}

function appCallbackWithError(callback, error) {
  const callbackURL = new URL(callback);
  callbackURL.searchParams.set("error", error);
  return callbackURL.toString();
}

function clampNumber(value, min, max) {
  if (!Number.isFinite(value)) {
    return min;
  }
  return Math.min(Math.max(Math.trunc(value), min), max);
}

async function exchangeAuthorizationCode(code) {
  const body = new URLSearchParams({
    grant_type: "authorization_code",
    code,
    redirect_uri: oauthCallbackURL()
  });

  const response = await fetch(new URL("/auth/oauth/token", allegroBaseURL), {
    method: "POST",
    headers: {
      "Authorization": `Basic ${Buffer.from(`${clientID}:${clientSecret}`).toString("base64")}`,
      "Content-Type": "application/x-www-form-urlencoded",
      "Accept": "application/json"
    },
    body
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Allegro token exchange failed (${response.status}): ${text}`);
  }

  const token = await response.json();
  return {
    ...token,
    savedAt: Date.now(),
    expiresAt: Date.now() + Number(token.expires_in || 0) * 1000
  };
}

async function recentCheckoutForms(accessToken, limit) {
  const eventsURL = new URL("/order/events", allegroBaseURL);
  eventsURL.searchParams.set("limit", String(limit));

  const eventsResponse = await allegroRequest(eventsURL, accessToken);
  const checkoutFormIDs = uniqueCheckoutFormIDs(eventsResponse.events || []).slice(0, limit);

  const orders = [];
  for (const checkoutFormID of checkoutFormIDs) {
    try {
      const order = await allegroRequest(new URL(`/order/checkout-forms/${checkoutFormID}`, allegroBaseURL), accessToken);
      orders.push(order);
    } catch (error) {
      console.error(`Could not fetch checkout form ${checkoutFormID}`, error);
    }
  }

  return orders;
}

function uniqueCheckoutFormIDs(events) {
  const ids = [];
  const seen = new Set();

  for (const event of events) {
    const checkoutFormID = event?.checkoutForm?.id || event?.order?.checkoutForm?.id;
    if (typeof checkoutFormID !== "string" || checkoutFormID.length === 0 || seen.has(checkoutFormID)) {
      continue;
    }
    seen.add(checkoutFormID);
    ids.push(checkoutFormID);
  }

  return ids;
}

async function allegroRequest(url, accessToken) {
  const response = await fetch(url, {
    headers: {
      "Authorization": `Bearer ${accessToken}`,
      "Accept": "application/vnd.allegro.public.v1+json"
    }
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Allegro request failed (${response.status}): ${text}`);
  }

  return response.json();
}
