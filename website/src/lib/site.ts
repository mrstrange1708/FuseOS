/** Addresses the whole site links to, in one place. */
export const CONTACT = 'fuseos@theshaik.dev';
export const GITHUB = 'https://github.com/mrstrange1708/FuseOS';
export const ISSUES = `${GITHUB}/issues`;
/** The control-plane server (the reset page posts to it). Overridable per Vercel environment. */
export const API = process.env.NEXT_PUBLIC_API_URL ?? 'https://fuseos-api.theshaik.dev';
