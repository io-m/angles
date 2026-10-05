import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  output: 'export',
  images: {
    unoptimized: true,
  },
  poweredByHeader: false,
};

// `next dev` only. The static export does not apply rewrites; production uses web/worker.ts.
if (process.env.NODE_ENV === 'development') {
  nextConfig.rewrites = async () => [
    {
      source: '/api/admin/:path*',
      destination: 'http://127.0.0.1:8787/admin/:path*',
    },
  ];
}

export default nextConfig;
