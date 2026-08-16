export interface Env {
  ASSETS: Fetcher;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === '/' || url.pathname === '/landing' || url.pathname === '/landing/') {
      return env.ASSETS.fetch(new Request(new URL('/landing.html', request.url), request));
    }
    return env.ASSETS.fetch(request);
  },
};
