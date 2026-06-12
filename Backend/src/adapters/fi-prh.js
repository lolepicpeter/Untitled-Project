import { fetchJSON } from "../lib/http.js";

const baseURL = "https://avoindata.prh.fi/opendata-ytj-api/v3";

export const finlandPrhAdapter = {
  countryCode: "FI",
  countryName: "Finland",
  dataSource: "PRH/YTJ Open Data",
  search,
  details
};

async function search(query) {
  const trimmedQuery = query.trim();
  const url = new URL(`${baseURL}/companies`);

  if (isBusinessId(trimmedQuery)) {
    url.searchParams.set("businessId", trimmedQuery);
  } else {
    url.searchParams.set("name", trimmedQuery);
  }

  const response = await fetchJSON(url);
  const results = (response.companies ?? []).map(mapSearchResult);
  return rankResults(results, trimmedQuery).slice(0, 10);
}

async function details(id) {
  const url = new URL(`${baseURL}/companies`);
  url.searchParams.set("businessId", id);

  const response = await fetchJSON(url);
  const company = response.companies?.[0];

  if (!company) {
    const error = new Error(`No Finnish company found for Business ID '${id}'.`);
    error.status = 404;
    throw error;
  }

  const address = preferredAddress(company);
  const businessLine = preferredDescription(company.mainBusinessLine?.descriptions);

  return {
    name: primaryName(company),
    companyId: company.businessId?.value ?? "",
    taxId: company.businessId?.value ?? "",
    vatId: isVatRegistered(company) ? `FI${(company.businessId?.value ?? "").replace("-", "")}` : "",
    legalForm: preferredDescription(company.companyForms?.[0]?.descriptions),
    status: company.companySituations?.length ? "changed" : "active",
    street: streetLine(address),
    city: preferredPostOffice(address)?.city ?? "",
    postalCode: address?.postCode ?? "",
    country: "Finland",
    establishedOn: company.businessId?.registrationDate ?? "",
    register: "YTJ / PRH",
    industryCode: company.mainBusinessLine?.type ?? "",
    vatPayer: isVatRegistered(company) ? "Yes" : "",
    businessActivities: businessLine,
    source: "PRH/YTJ Open Data"
  };
}

function mapSearchResult(company) {
  return {
    companyId: company.businessId?.value ?? "",
    name: primaryName(company),
    legalForm: preferredDescription(company.companyForms?.[0]?.descriptions) || null,
    kind: null,
    register: "YTJ / PRH",
    status: company.companySituations?.length ? "changed" : "active",
    city: preferredPostOffice(preferredAddress(company))?.city ?? null,
    establishedYear: yearPrefix(company.businessId?.registrationDate)
  };
}

function rankResults(results, query) {
  if (isBusinessId(query)) {
    return results;
  }

  const normalizedQuery = normalizeForSearch(query);
  return results.sort((first, second) => {
    const firstName = normalizeForSearch(first.name);
    const secondName = normalizeForSearch(second.name);
    const firstPrefix = firstName.startsWith(normalizedQuery);
    const secondPrefix = secondName.startsWith(normalizedQuery);
    const firstContains = firstName.includes(normalizedQuery);
    const secondContains = secondName.includes(normalizedQuery);

    if (firstPrefix !== secondPrefix) {
      return firstPrefix ? -1 : 1;
    }
    if (firstContains !== secondContains) {
      return firstContains ? -1 : 1;
    }
    return firstName.localeCompare(secondName, "fi-FI");
  });
}

function primaryName(company) {
  const names = company.names ?? [];
  return names.find((name) => name.type === "1" && !name.endDate)?.name
    ?? names.find((name) => !name.endDate)?.name
    ?? names[0]?.name
    ?? "";
}

function preferredAddress(company) {
  const addresses = company.addresses ?? [];
  return addresses.find((address) => address.type === 1)
    ?? addresses.find((address) => address.type === 2)
    ?? addresses[0]
    ?? null;
}

function preferredPostOffice(address) {
  return address?.postOffices?.find((office) => office.languageCode === "3")
    ?? address?.postOffices?.find((office) => office.languageCode === "1")
    ?? address?.postOffices?.[0]
    ?? null;
}

function streetLine(address) {
  if (!address) {
    return "";
  }

  if (address.postOfficeBox) {
    return `P.O. Box ${address.postOfficeBox}`;
  }

  return [
    address.street,
    address.buildingNumber,
    address.entrance,
    address.apartmentNumber,
    address.apartmentIdSuffix
  ].filter(Boolean).join(" ");
}

function preferredDescription(descriptions = []) {
  return descriptions.find((description) => description.languageCode === "3")?.description
    ?? descriptions.find((description) => description.languageCode === "1")?.description
    ?? descriptions[0]?.description
    ?? "";
}

function isVatRegistered(company) {
  return (company.registeredEntries ?? []).some((entry) => entry.register === "6" && !entry.endDate);
}

function normalizeForSearch(value) {
  return value
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .toLocaleLowerCase("fi-FI");
}

function yearPrefix(value) {
  if (!value || value.length < 4) {
    return null;
  }

  const year = Number(value.slice(0, 4));
  return Number.isFinite(year) ? year : null;
}

function isBusinessId(value) {
  return /^\d{7}-\d$/.test(value);
}
