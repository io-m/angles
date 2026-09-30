import type { Metadata, Viewport } from 'next';
import { DM_Sans, Fraunces } from 'next/font/google';
import type { ReactNode } from 'react';

import { SITE_DESCRIPTION, SITE_TITLE } from '@/lib/structuredData';

import './globals.css';

const dmSans = DM_Sans({
  subsets: ['latin'],
  variable: '--font-sans',
  display: 'swap',
});

const fraunces = Fraunces({
  subsets: ['latin'],
  variable: '--font-display',
  display: 'swap',
});

export const metadata: Metadata = {
  title: {
    default: SITE_TITLE,
    template: '%s — Angles',
  },
  description: SITE_DESCRIPTION,
  applicationName: 'Angles',
  metadataBase: new URL('https://useangles.app'),
  openGraph: {
    title: SITE_TITLE,
    description: SITE_DESCRIPTION,
    siteName: 'Angles',
    type: 'website',
  },
  twitter: {
    card: 'summary',
    title: SITE_TITLE,
    description: SITE_DESCRIPTION,
  },
  icons: {
    icon: [{ url: '/favicon.svg', type: 'image/svg+xml' }],
  },
};

export const viewport: Viewport = {
  colorScheme: 'light',
  themeColor: '#FDFBF8',
};

export default function RootLayout({
  children,
}: Readonly<{
  children: ReactNode;
}>) {
  return (
    <html className={`${dmSans.variable} ${fraunces.variable}`} lang="en">
      <body>{children}</body>
    </html>
  );
}
