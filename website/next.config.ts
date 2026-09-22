import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  // Static HTML, so GitHub Pages can host it for free. PAGES_BASE_PATH is set by the
  // deploy workflow (the site lives at /FuseOS there) and is empty locally.
  output: 'export',
  basePath: process.env.PAGES_BASE_PATH || undefined,
};

export default nextConfig;
