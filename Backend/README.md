# Company Lookup Backend

Small local-first backend for country-specific company lookup adapters.

The Apple app should eventually talk to this backend instead of calling every country registry directly. The backend owns registry quirks, request shaping, result ranking, API keys, rate limiting, and deployment concerns.

## Run Locally

```sh
cd Backend
npm start
```

Default URL:

```text
http://localhost:3000
```

Use a different port:

```sh
PORT=4000 npm start
```

## Endpoints

### Health

```http
GET /health
```

Response:

```json
{ "ok": true }
```

### Automatic Lookup Countries

```http
GET /v1/countries
```

Response:

```json
{
  "automaticLookup": [
    { "code": "SK", "name": "Slovakia", "dataSource": "ORSF" },
    { "code": "CZ", "name": "Czech Republic", "dataSource": "ARES" },
    { "code": "NO", "name": "Norway", "dataSource": "Brønnøysund Register Centre" },
    { "code": "FI", "name": "Finland", "dataSource": "PRH/YTJ Open Data" }
  ]
}
```

### Search Companies

```http
GET /v1/companies/search?country=SK&q=slovensko.digital
GET /v1/companies/search?country=CZ&q=Miska%20des
GET /v1/companies/search?country=NO&q=signicat
GET /v1/companies/search?country=FI&q=nokia
```

Response:

```json
{
  "results": [
    {
      "companyId": "21520160",
      "name": "Miska design s.r.o.",
      "legalForm": "společnost s ručením omezeným",
      "kind": null,
      "register": "ROS",
      "status": "active",
      "city": "Brno",
      "establishedYear": 2024
    }
  ]
}
```

### Company Details

```http
GET /v1/companies/details?country=CZ&id=21520160
GET /v1/companies/details?country=SK&id=50158635
GET /v1/companies/details?country=NO&id=989584022
GET /v1/companies/details?country=FI&id=0112038-9
```

Response:

```json
{
  "company": {
    "name": "Miska design s.r.o.",
    "companyId": "21520160",
    "taxId": "CZ21520160",
    "vatId": "CZ21520160",
    "legalForm": "společnost s ručením omezeným",
    "status": "active",
    "street": "Mezírka 775/1",
    "city": "Brno",
    "postalCode": "60200",
    "country": "Česká republika",
    "establishedOn": "2024-04-29",
    "register": "ROS",
    "industryCode": "68200, 00",
    "vatPayer": "Yes",
    "businessActivities": "",
    "source": "ARES"
  }
}
```

## Adding a Country

Add one adapter file in `src/adapters/`, then register it in `src/adapters/index.js`.

Each adapter must expose:

```js
{
  countryCode: "SK",
  countryName: "Slovakia",
  dataSource: "ORSF",
  search(query),
  details(id)
}
```

Keep country-specific behavior inside the adapter. Do not force every country into the same search rules.

## Deployment Notes

This backend is dependency-free and runs on standard Node.js 20+.

Good deployment targets:

- Fly.io
- Render
- Railway
- Hetzner
- DigitalOcean
- AWS / Google Cloud / Azure

Set `PORT` if the host requires it. Set `CORS_ORIGIN` to the app/web origin when exposing this publicly.
