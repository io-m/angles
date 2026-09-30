export const SITE_URL = 'https://useangles.app';
export const SITE_TITLE = 'Angles — Four short takes on a stuck thought';
export const SITE_DESCRIPTION =
  'Angles is an iPhone app for the moment a negative thought gets stuck. Write it down and get four short takes: Stoic, Optimistic, Humorous, and Tough love. Keep it private, or share it.';

export const softwareApplicationJsonLd = {
  '@context': 'https://schema.org',
  '@type': 'SoftwareApplication',
  name: 'Angles',
  operatingSystem: 'iOS',
  applicationCategory: 'LifestyleApplication',
  url: SITE_URL,
  description: SITE_DESCRIPTION,
  isAccessibleForFree: false,
  publisher: {
    '@type': 'Organization',
    name: 'Bithavn',
    url: 'https://bithavn.app',
  },
};
