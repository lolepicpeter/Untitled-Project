import { fetchJSON } from "../lib/http.js";

const baseURL = "https://ares.gov.cz/ekonomicke-subjekty-v-be/rest";
const ignoredSearchPrefixes = new Set([
  "ing",
  "mgr",
  "bc",
  "mudr",
  "judr",
  "phdr",
  "mga",
  "mvdr",
  "doc",
  "prof"
]);

export const czechAresAdapter = {
  countryCode: "CZ",
  countryName: "Czech Republic",
  dataSource: "ARES",
  search,
  details
};

async function search(query) {
  const trimmedQuery = query.trim();

  if (isICO(trimmedQuery)) {
    const company = await economicSubject(trimmedQuery);
    return [mapSearchResult(company)];
  }

  const exactResults = await searchByName(trimmedQuery);
  const rankedExactResults = rankedResults(exactResults, trimmedQuery);
  if (rankedExactResults.length > 0) {
    return rankedExactResults.slice(0, 10);
  }

  for (const fallbackQuery of fallbackSearchTerms(trimmedQuery)) {
    const fallbackResults = await searchByName(fallbackQuery, 100);
    const rankedFallbackResults = rankedResults(fallbackResults, trimmedQuery);
    if (rankedFallbackResults.length > 0) {
      return rankedFallbackResults.slice(0, 10);
    }
  }

  return [];
}

async function details(ico) {
  const company = await economicSubject(ico);
  const address = company.sidlo ?? {};
  const registrations = company.seznamRegistraci ?? {};

  return {
    name: company.obchodniJmeno ?? "",
    companyId: resolvedIco(company),
    taxId: company.dic ?? "",
    vatId: company.dic ?? "",
    legalForm: legalFormDisplayName(company.pravniForma),
    status: isActive(registrations) ? "active" : "",
    street: streetLine(address),
    city: address.nazevObce ?? "",
    postalCode: stringify(address.psc),
    country: address.nazevStatu ?? "CZ",
    establishedOn: company.datumVzniku ?? "",
    register: company.primarniZdroj?.toUpperCase() ?? "ARES",
    industryCode: (company.czNace ?? company.czNace2008 ?? []).join(", "),
    vatPayer: registrations.stavZdrojeDph === "AKTIVNI" ? "Yes" : "",
    businessActivities: "",
    source: "ARES"
  };
}

async function economicSubject(ico) {
  return fetchJSON(`${baseURL}/ekonomicke-subjekty/${encodeURIComponent(ico)}`);
}

async function searchByName(query, limit = 10) {
  try {
    const response = await fetchJSON(`${baseURL}/ekonomicke-subjekty/vyhledat`, {
      method: "POST",
      body: JSON.stringify({ obchodniJmeno: query, pocet: limit })
    });

    return (response.ekonomickeSubjekty ?? []).map(mapSearchResult);
  } catch (error) {
    if (isTooManyResults(error)) {
      return [];
    }

    throw error;
  }
}

function mapSearchResult(company) {
  return {
    companyId: resolvedIco(company),
    name: company.obchodniJmeno,
    legalForm: legalFormDisplayName(company.pravniForma),
    kind: null,
    register: company.primarniZdroj?.toUpperCase() ?? null,
    status: isActive(company.seznamRegistraci ?? {}) ? "active" : null,
    city: company.sidlo?.nazevObce ?? null,
    establishedYear: yearPrefix(company.datumVzniku)
  };
}

function rankedResults(results, query) {
  const tokens = searchTokens(query);
  if (tokens.length === 0) {
    return results;
  }

  return results
    .filter((result) => {
      const nameWords = normalizedWords(result.name);

      if (tokens.length === 1) {
        return firstSearchableWord(result.name)?.startsWith(tokens[0]);
      }

      return tokens.every((token) => nameWords.some((word) => word.startsWith(token)));
    })
    .sort((first, second) => {
      const firstName = normalizeForSearch(first.name);
      const secondName = normalizeForSearch(second.name);
      const normalizedQuery = normalizeForSearch(query);
      const firstHasPrefix = firstName.startsWith(normalizedQuery);
      const secondHasPrefix = secondName.startsWith(normalizedQuery);

      if (firstHasPrefix !== secondHasPrefix) {
        return firstHasPrefix ? -1 : 1;
      }

      return firstName.localeCompare(secondName, "cs-CZ");
    });
}

function searchTokens(query) {
  return query
    .split(/\s+/)
    .map(normalizeForSearch)
    .filter((token) => token.length >= 2);
}

function fallbackSearchTerms(query) {
  const candidates = [];
  const words = query.split(/\s+/).filter((word) => word.length >= 3);

  const appendCandidate = (candidate) => {
    if (candidate !== query && !candidates.includes(candidate)) {
      candidates.push(candidate);
    }
  };

  for (const word of words) {
    appendCandidate(word);
    if (word.length >= 4) {
      appendCandidate(`${word}a`);
    }
  }

  const baseQuery = words[0] ?? query;
  if (baseQuery.length > 3) {
    for (let length = baseQuery.length - 1; length >= 3; length -= 1) {
      appendCandidate(baseQuery.slice(0, length));
    }
  }

  return candidates;
}

function normalizeForSearch(value) {
  return value
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .toLocaleLowerCase("cs-CZ");
}

function normalizedWords(value) {
  return normalizeForSearch(value).split(/[^\p{Letter}\p{Number}]+/u).filter(Boolean);
}

function firstSearchableWord(value) {
  return normalizedWords(value).find((word) => !ignoredSearchPrefixes.has(word));
}

function resolvedIco(company) {
  return company.ico || company.icoId?.replace("ARES_", "") || "";
}

function isActive(registrations) {
  return [
    registrations.stavZdrojeRos,
    registrations.stavZdrojeVr,
    registrations.stavZdrojeRes,
    registrations.stavZdrojeRzp
  ].includes("AKTIVNI");
}

function legalFormDisplayName(value) {
  switch (value) {
    case "101":
      return "sole trader";
    case "112":
      return "společnost s ručením omezeným";
    case "121":
      return "akciová společnost";
    case undefined:
    case null:
      return null;
    default:
      return `Legal form ${value}`;
  }
}

function streetLine(address) {
  if (address.nazevUlice && address.cisloDomovni) {
    if (address.cisloOrientacni) {
      return `${address.nazevUlice} ${address.cisloDomovni}/${address.cisloOrientacni}`;
    }

    return `${address.nazevUlice} ${address.cisloDomovni}`;
  }

  return address.textovaAdresa ?? "";
}

function stringify(value) {
  return value == null ? "" : String(value);
}

function yearPrefix(value) {
  if (!value || value.length < 4) {
    return null;
  }

  const year = Number(value.slice(0, 4));
  return Number.isFinite(year) ? year : null;
}

function isICO(value) {
  return /^\d{6,10}$/.test(value);
}

function isTooManyResults(error) {
  return error.status === 400
    && (error.message?.toLocaleLowerCase("cs-CZ").includes("příliš mnoho výsledků")
      || error.message?.includes("maximálně 1 000"));
}
