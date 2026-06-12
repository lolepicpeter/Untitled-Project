import { fetchJSON } from "../lib/http.js";

const baseURL = "https://api.orsf.sk/v1";

export const slovakiaOrsfAdapter = {
  countryCode: "SK",
  countryName: "Slovakia",
  dataSource: "ORSF",
  search,
  details
};

async function search(query) {
  const url = new URL(`${baseURL}/search`);
  url.searchParams.set("q", query);
  url.searchParams.set("limit", "10");

  const response = await fetchJSON(url);
  return (response.hits ?? []).map(mapSearchResult);
}

async function details(ico) {
  const company = await fetchJSON(`${baseURL}/companies/${encodeURIComponent(ico)}`);
  return {
    name: company.name ?? "",
    companyId: company.nationalId ?? company.ico ?? "",
    taxId: company.taxId ?? company.dic ?? "",
    vatId: company.vatId ?? company.icdph ?? "",
    legalForm: company.legalForm ?? "",
    status: company.statusCode ?? company.status ?? "",
    street: company.address?.street ?? company.street ?? "",
    city: company.address?.city ?? company.city ?? "",
    postalCode: company.address?.postalCode ?? company.psc ?? "",
    country: company.address?.country ?? company.countryCode ?? "SK",
    establishedOn: company.establishedOn ?? "",
    register: displayRegister(company),
    industryCode: company.nace ?? "",
    vatPayer: company.vatRegistration ? "Yes" : "",
    businessActivities: (company.activities ?? [])
      .map((activity) => activity.description ?? activity.economicActivityDescription ?? "")
      .filter(Boolean)
      .join("\n"),
    source: "ORSF"
  };
}

function mapSearchResult(result) {
  return {
    companyId: result.ico,
    name: result.name,
    legalForm: result.legalForm ?? null,
    kind: result.kind ?? null,
    register: result.register ?? null,
    status: result.status ?? null,
    city: result.city ?? null,
    establishedYear: result.establishedYear ?? null
  };
}

function displayRegister(company) {
  if (company.register) {
    return company.register;
  }

  if (company.registerCode && company.registerCode !== "unknown") {
    return company.registerCode;
  }

  return "Not available in ORSF";
}
