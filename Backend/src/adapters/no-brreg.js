import { fetchJSON } from "../lib/http.js";

const baseURL = "https://data.brreg.no/enhetsregisteret/api";

export const norwayBrregAdapter = {
  countryCode: "NO",
  countryName: "Norway",
  dataSource: "Brønnøysund Register Centre",
  search,
  details
};

async function search(query) {
  const trimmedQuery = query.trim();

  if (isOrganisationNumber(trimmedQuery)) {
    const company = await entity(trimmedQuery);
    return [mapSearchResult(company)];
  }

  const url = new URL(`${baseURL}/enheter`);
  url.searchParams.set("navn", trimmedQuery);
  url.searchParams.set("navnMetodeForSoek", "FORTLOEPENDE");
  url.searchParams.set("size", "10");

  const response = await fetchJSON(url);
  return (response._embedded?.enheter ?? []).map(mapSearchResult);
}

async function details(id) {
  const company = await entity(id);
  const address = company.forretningsadresse ?? company.postadresse ?? {};

  return {
    name: company.navn ?? "",
    companyId: company.organisasjonsnummer ?? "",
    taxId: company.organisasjonsnummer ?? "",
    vatId: company.registrertIMvaregisteret ? `NO${company.organisasjonsnummer}MVA` : "",
    legalForm: company.organisasjonsform?.beskrivelse ?? company.organisasjonsform?.kode ?? "",
    status: statusText(company),
    street: (address.adresse ?? []).join(", "),
    city: address.poststed ?? address.kommune ?? "",
    postalCode: address.postnummer ?? "",
    country: address.land ?? "Norway",
    establishedOn: company.stiftelsesdato ?? company.registreringsdatoEnhetsregisteret ?? "",
    register: company.registrertIForetaksregisteret ? "Foretaksregisteret" : "Enhetsregisteret",
    industryCode: company.naeringskode1?.kode ?? "",
    vatPayer: company.registrertIMvaregisteret ? "Yes" : "",
    businessActivities: [
      ...(company.aktivitet ?? []),
      ...(company.vedtektsfestetFormaal ?? [])
    ].filter(Boolean).join("\n"),
    source: "Brønnøysund Register Centre"
  };
}

async function entity(id) {
  return fetchJSON(`${baseURL}/enheter/${encodeURIComponent(id)}`);
}

function mapSearchResult(company) {
  return {
    companyId: company.organisasjonsnummer,
    name: company.navn,
    legalForm: company.organisasjonsform?.beskrivelse ?? company.organisasjonsform?.kode ?? null,
    kind: null,
    register: company.registrertIForetaksregisteret ? "Foretaksregisteret" : "Enhetsregisteret",
    status: statusText(company),
    city: company.forretningsadresse?.poststed ?? company.postadresse?.poststed ?? null,
    establishedYear: yearPrefix(company.stiftelsesdato ?? company.registreringsdatoEnhetsregisteret)
  };
}

function statusText(company) {
  if (company.konkurs) {
    return "bankrupt";
  }
  if (company.underAvvikling) {
    return "under liquidation";
  }
  if (company.underTvangsavviklingEllerTvangsopplosning) {
    return "forced liquidation";
  }
  return "active";
}

function yearPrefix(value) {
  if (!value || value.length < 4) {
    return null;
  }

  const year = Number(value.slice(0, 4));
  return Number.isFinite(year) ? year : null;
}

function isOrganisationNumber(value) {
  return /^\d{9}$/.test(value);
}
