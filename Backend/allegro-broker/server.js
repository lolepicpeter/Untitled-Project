import crypto from "node:crypto";
import express from "express";
import pg from "pg";

const app = express();
app.use(express.json());

const port = Number(process.env.PORT || 3001);
const publicBaseURL = requiredEnv("PUBLIC_BASE_URL");
const appCallbackURL = process.env.APP_CALLBACK_URL || "invoiceflow://allegro/connected";
const clientID = requiredEnv("ALLEGRO_CLIENT_ID");
const clientSecret = requiredEnv("ALLEGRO_CLIENT_SECRET");
const environment = process.env.ALLEGRO_ENV === "sandbox" ? "sandbox" : "production";
const databaseURL = process.env.DATABASE_URL?.trim();

const allegroAuthBaseURL = environment === "sandbox"
  ? "https://allegro.pl.allegrosandbox.pl"
  : "https://allegro.pl";

const allegroAPIBaseURL = environment === "sandbox"
  ? "https://api.allegro.pl.allegrosandbox.pl"
  : "https://api.allegro.pl";

const pendingStates = new Map();
const connections = new Map();
const pool = databaseURL ? new pg.Pool({
  connectionString: databaseURL,
  ssl: process.env.DATABASE_SSL === "false" ? false : { rejectUnauthorized: false }
}) : undefined;

const scopes = [
  "allegro:api:orders:read",
  "allegro:api:profile:read"
];

app.get("/health", (request, response) => {
  response.json({
    ok: true,
    service: "invoiceflow-allegro-broker",
    environment,
    storage: pool ? "postgres" : "memory"
  });
});

app.get("/allegro/oauth/start", (request, response) => {
  const state = crypto.randomUUID();
  const callbackURL = new URL(appCallbackURL);
  callbackURL.searchParams.set("state", state);

  pendingStates.set(state, {
    createdAt: Date.now(),
    appCallbackURL: callbackURL.toString()
  });

  const authorizationURL = new URL("/auth/oauth/authorize", allegroAuthBaseURL);
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
    await saveConnection(connectionID, {
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

app.get("/allegro/connections/:connectionID", async (request, response) => {
  const connection = await getConnection(request.params.connectionID);
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
  const connection = await getConnection(request.params.connectionID);
  if (!connection) {
    response.status(404).json({ error: { message: "Connection not found." } });
    return;
  }

  const limit = clampNumber(Number(request.query.limit || 500), 1, 1000);
  const dateRange = orderDateRange(request.query);

  try {
    const token = await accessTokenForConnection(request.params.connectionID, connection);
    const result = await checkoutFormsByDateRange(token.access_token, {
      ...dateRange,
      limit
    });
    response.json(result);
  } catch (error) {
    response.status(502).json({
      error: {
        message: error instanceof Error ? error.message : "Could not fetch Allegro orders."
      }
    });
  }
});

app.delete("/allegro/connections/:connectionID", async (request, response) => {
  await deleteConnection(request.params.connectionID);
  response.status(204).end();
});

await initializeStorage();

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

function orderDateRange(query) {
  const now = new Date();
  const to = parseDate(query.to) || now;
  const days = clampNumber(Number(query.days || 30), 1, 365);
  const from = parseDate(query.from) || new Date(to.getTime() - days * 24 * 60 * 60 * 1000);

  return {
    from: from.toISOString(),
    to: to.toISOString()
  };
}

function parseDate(value) {
  if (typeof value !== "string" || value.trim().length === 0) {
    return undefined;
  }

  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? undefined : date;
}

async function exchangeAuthorizationCode(code) {
  const body = new URLSearchParams({
    grant_type: "authorization_code",
    code,
    redirect_uri: oauthCallbackURL()
  });

  const response = await fetch(new URL("/auth/oauth/token", allegroAuthBaseURL), {
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

async function refreshAccessToken(refreshToken) {
  const body = new URLSearchParams({
    grant_type: "refresh_token",
    refresh_token: refreshToken
  });

  const response = await fetch(new URL("/auth/oauth/token", allegroAuthBaseURL), {
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
    throw new Error(`Allegro token refresh failed (${response.status}): ${text}`);
  }

  const token = await response.json();
  return {
    ...token,
    refresh_token: token.refresh_token || refreshToken,
    savedAt: Date.now(),
    expiresAt: Date.now() + Number(token.expires_in || 0) * 1000
  };
}

async function accessTokenForConnection(connectionID, connection) {
  if (!isTokenExpiring(connection.token)) {
    return connection.token;
  }

  const refreshToken = connection.token.refresh_token;
  if (typeof refreshToken !== "string" || refreshToken.length === 0) {
    throw new Error("Allegro connection expired and has no refresh token. Reconnect Allegro.");
  }

  const refreshedToken = await refreshAccessToken(refreshToken);
  await saveConnection(connectionID, {
    ...connection,
    token: refreshedToken
  });
  return refreshedToken;
}

function isTokenExpiring(token) {
  const expiresAt = Number(token?.expiresAt || 0);
  return !Number.isFinite(expiresAt) || expiresAt <= Date.now() + 60_000;
}

async function initializeStorage() {
  if (!pool) {
    console.warn("DATABASE_URL is not set. Allegro connections will be stored in memory only.");
    return;
  }

  await pool.query(`
    CREATE TABLE IF NOT EXISTS allegro_connections (
      id TEXT PRIMARY KEY,
      created_at TIMESTAMPTZ NOT NULL,
      token JSONB NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
}

async function getConnection(connectionID) {
  if (!pool) {
    return connections.get(connectionID);
  }

  const result = await pool.query(
    "SELECT id, created_at, token FROM allegro_connections WHERE id = $1",
    [connectionID]
  );
  const row = result.rows[0];
  if (!row) {
    return undefined;
  }

  return {
    createdAt: new Date(row.created_at).getTime(),
    token: row.token
  };
}

async function saveConnection(connectionID, connection) {
  if (!pool) {
    connections.set(connectionID, connection);
    return;
  }

  await pool.query(
    `INSERT INTO allegro_connections (id, created_at, token, updated_at)
     VALUES ($1, $2, $3, NOW())
     ON CONFLICT (id)
     DO UPDATE SET token = EXCLUDED.token, updated_at = NOW()`,
    [connectionID, new Date(connection.createdAt), connection.token]
  );
}

async function deleteConnection(connectionID) {
  if (!pool) {
    connections.delete(connectionID);
    return;
  }

  await pool.query("DELETE FROM allegro_connections WHERE id = $1", [connectionID]);
}

async function checkoutFormsByDateRange(accessToken, options) {
  const pageSize = 100;
  const limit = clampNumber(Number(options.limit || 500), 1, 1000);
  const orders = [];
  let offset = 0;
  let filterMode = "lineItems.boughtAt";

  while (orders.length < limit) {
    const requestLimit = Math.min(pageSize, limit - orders.length);
    const page = await checkoutFormsPage(accessToken, {
      from: options.from,
      to: options.to,
      limit: requestLimit,
      offset,
      filterMode
    }).catch(async (error) => {
      if (filterMode === "lineItems.boughtAt" && isUnsupportedFilterError(error)) {
        filterMode = "updatedAt";
        offset = 0;
        orders.length = 0;
        return checkoutFormsPage(accessToken, {
          from: options.from,
          to: options.to,
          limit: requestLimit,
          offset,
          filterMode
        });
      }
      throw error;
    });

    if (page.length === 0) {
      break;
    }

    orders.push(...page);
    if (page.length < requestLimit) {
      break;
    }
    offset += page.length;
  }

  return {
    orders,
    meta: {
      from: options.from,
      to: options.to,
      limit,
      fetched: orders.length,
      filterMode
    }
  };
}

async function checkoutFormsPage(accessToken, options) {
  const checkoutFormsURL = new URL("/order/checkout-forms", allegroAPIBaseURL);
  checkoutFormsURL.searchParams.set("limit", String(options.limit));
  checkoutFormsURL.searchParams.set("offset", String(options.offset));
  if (options.filterMode === "lineItems.boughtAt") {
    checkoutFormsURL.searchParams.set("sort", "-lineItems.boughtAt");
  }
  checkoutFormsURL.searchParams.set(`${options.filterMode}.gte`, options.from);
  checkoutFormsURL.searchParams.set(`${options.filterMode}.lte`, options.to);

  const response = await allegroRequest(checkoutFormsURL, accessToken);
  return Array.isArray(response.checkoutForms) ? response.checkoutForms : [];
}

function isUnsupportedFilterError(error) {
  if (!(error instanceof Error)) {
    return false;
  }

  return error.message.includes("400") ||
    error.message.toLowerCase().includes("unsupported") ||
    error.message.toLowerCase().includes("invalid");
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
