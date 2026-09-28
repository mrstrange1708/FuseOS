import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  // Static HTML, so GitHub Pages can host it for free. PAGES_BASE_PATH is set by the
  // deploy workflow (the site lives at /FuseOS there) and is empty locally.
  output: 'export',
  basePath: process.env.PAGES_BASE_PATH || undefined,
  // The same prefix for plain asset URLs (the film), which basePath does not rewrite.
  env: { NEXT_PUBLIC_BASE_PATH: process.env.PAGES_BASE_PATH || '' },
};

export default nextConfig;
