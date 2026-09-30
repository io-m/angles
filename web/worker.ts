interface Env {
  ASSETS: {
    fetch(request: Request): Promise<Response>;
  };
}

const CANONICAL_HOST = 'useangles.app';
const LEGACY_HOSTS = new Set(['www.useangles.app']);

function visitorUsedHttp(request: Request, url: URL): boolean {
  if (url.protocol === 'http:') {
    return true;
  }
  const forwarded = request.headers.get('x-forwarded-proto');
  if (forwarded === 'http') {
    return true;
  }
  const visitor = request.headers.get('cf-visitor');
  return visitor?.includes('"scheme":"http"') === true;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const host = url.hostname.toLowerCase();
    const needsHttps = visitorUsedHttp(request, url);
    const needsCanonicalHost = LEGACY_HOSTS.has(host);

    if (needsHttps || needsCanonicalHost) {
      url.protocol = 'https:';
      url.hostname = CANONICAL_HOST;
      url.port = '';
      return Response.redirect(url.toString(), 301);
    }

    return env.ASSETS.fetch(request);
  },
};
