import { lookupAdapters } from "./adapters/index.js";
import { sendError, sendJSON } from "./lib/http.js";
import { createServer } from "node:http";

const port = Number(process.env.PORT ?? 3000);

const server = createServer(async (nodeRequest, nodeResponse) => {
  const request = nodeRequestToRequest(nodeRequest);
  const response = await handleRequest(request);

  nodeResponse.writeHead(response.status, Object.fromEntries(response.headers));
  nodeResponse.end(Buffer.from(await response.arrayBuffer()));
});

server.listen(port, "0.0.0.0", () => {
  console.log(`Company lookup backend listening on http://localhost:${port}`);
});

async function handleRequest(request) {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders() });
  }

  try {
    const url = new URL(request.url, `http://${request.headers.host}`);

    if (request.method === "GET" && url.pathname === "/health") {
      return sendJSON({ ok: true });
    }

    if (request.method === "GET" && url.pathname === "/v1/countries") {
      return sendJSON({
        automaticLookup: Object.values(lookupAdapters).map((adapter) => ({
          code: adapter.countryCode,
          name: adapter.countryName,
          dataSource: adapter.dataSource
        }))
      });
    }

    if (request.method === "GET" && url.pathname === "/v1/companies/search") {
      const adapter = adapterFrom(url);
      const query = requiredQuery(url, "q");
      const results = await adapter.search(query);
      return sendJSON({ results });
    }

    if (request.method === "GET" && url.pathname === "/v1/companies/details") {
      const adapter = adapterFrom(url);
      const id = requiredQuery(url, "id");
      const company = await adapter.details(id);
      return sendJSON({ company });
    }

    return sendError(404, "Endpoint not found.");
  } catch (error) {
    const status = error.status ?? 500;
    return sendError(status, error.message ?? "Unexpected server error.");
  }
}

function adapterFrom(url) {
  const country = requiredQuery(url, "country").toUpperCase();
  const adapter = lookupAdapters[country];

  if (!adapter) {
    throw httpError(400, `Automatic lookup is not configured for country '${country}'.`);
  }

  return adapter;
}

function requiredQuery(url, name) {
  const value = url.searchParams.get(name)?.trim();

  if (!value) {
    throw httpError(400, `Missing required query parameter '${name}'.`);
  }

  return value;
}

function httpError(status, message) {
  const error = new Error(message);
  error.status = status;
  return error;
}

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": process.env.CORS_ORIGIN ?? "*",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type"
  };
}

function nodeRequestToRequest(nodeRequest) {
  const protocol = nodeRequest.socket.encrypted ? "https" : "http";
  const url = `${protocol}://${nodeRequest.headers.host}${nodeRequest.url}`;

  return new Request(url, {
    method: nodeRequest.method,
    headers: nodeRequest.headers,
    body: ["GET", "HEAD"].includes(nodeRequest.method) ? undefined : nodeRequest
  });
}
