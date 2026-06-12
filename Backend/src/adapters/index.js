import { czechAresAdapter } from "./cz-ares.js";
import { finlandPrhAdapter } from "./fi-prh.js";
import { norwayBrregAdapter } from "./no-brreg.js";
import { slovakiaOrsfAdapter } from "./sk-orsf.js";

export const lookupAdapters = {
  [slovakiaOrsfAdapter.countryCode]: slovakiaOrsfAdapter,
  [czechAresAdapter.countryCode]: czechAresAdapter,
  [norwayBrregAdapter.countryCode]: norwayBrregAdapter,
  [finlandPrhAdapter.countryCode]: finlandPrhAdapter
};
