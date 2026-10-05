interface Env {
  ASSETS: {
    fetch(request: Request): Promise<Response>;
  };
  ANGLES_API_BASE_URL?: string;
  /** Wrangler secret. Same value as Railway ADMIN_PROXY_SECRET. Never sent to the browser. */
  ADMIN_PROXY_SECRET?: string;
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

    if (isAdminApi(url.pathname)) {
      return proxyAdmin(request, env, url);
    }

    return env.ASSETS.fetch(request);
  },
};

function operatorCookie(header: string | null): string | null {
  if (!header) {
    return null;
  }
  for (const part of header.split(';')) {
    const trimmed = part.trim();
    if (trimmed.startsWith('angles_admin=')) {
      return trimmed;
    }
  }
  return null;
}

function isAdminApi(pathname: string): boolean {
  return pathname === '/api/admin' || pathname.startsWith('/api/admin/');
}

async function proxyAdmin(request: Request, env: Env, url: URL): Promise<Response> {
  const base = env.ANGLES_API_BASE_URL?.trim();
  if (!base) {
    return Response.json({ error: 'Admin is not configured', code: 'ADMIN_DISABLED' }, { status: 503 });
  }

  let target: URL;
  try {
    target = new URL(`${url.pathname.slice('/api'.length)}${url.search}`, base);
  } catch {
    return Response.json({ error: 'Admin is not configured', code: 'ADMIN_DISABLED' }, { status: 503 });
  }

  const headers = new Headers();
  const adminCookie = operatorCookie(request.headers.get('cookie'));
  if (adminCookie) {
    headers.set('cookie', adminCookie);
  }
  const contentType = request.headers.get('content-type');
  if (contentType) {
    headers.set('content-type', contentType);
  }
  const clientIp = request.headers.get('cf-connecting-ip');
  if (clientIp) {
    headers.set('x-angles-client-ip', clientIp);
  }
  const proxySecret = env.ADMIN_PROXY_SECRET?.trim();
  if (proxySecret) {
    headers.set('x-angles-admin-proxy', proxySecret);
  }

  const hasBody = request.method !== 'GET' && request.method !== 'HEAD';
  let upstream: Response;
  try {
    upstream = await fetch(target, {
      method: request.method,
      headers,
      body: hasBody ? await request.arrayBuffer() : undefined,
      redirect: 'manual',
    });
  } catch {
    return Response.json({ error: 'Admin API unreachable', code: 'ADMIN_UNAVAILABLE' }, { status: 502 });
  }

  const outgoing = new Headers();
  outgoing.set('cache-control', 'no-store');
  const responseType = upstream.headers.get('content-type');
  if (responseType) {
    outgoing.set('content-type', responseType);
  }
  const cookies =
    typeof upstream.headers.getSetCookie === 'function' ? upstream.headers.getSetCookie() : [];
  if (cookies.length > 0) {
    for (const cookieHeader of cookies) {
      outgoing.append('set-cookie', cookieHeader);
    }
  } else {
    const single = upstream.headers.get('set-cookie');
    if (single) {
      outgoing.set('set-cookie', single);
    }
  }

  return new Response(upstream.body, { status: upstream.status, headers: outgoing });
}
