export interface Env {
  ASSETS: Fetcher;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === '/app' || url.pathname === '/app/') {
      return env.ASSETS.fetch(new Request(new URL('/app.html', request.url), request));
    }
    if (url.pathname.startsWith('/app/')) {
      return env.ASSETS.fetch(new Request(new URL(url.pathname.slice(4) + url.search, request.url), request));
    }
    return new Response('Not found', { status: 404 });
  },
};
