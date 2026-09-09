import { createServer } from 'node:http';

export function createApp({ logger = console.log, version = '0.1.0' } = {}) {
  let ready = true;
  const server = createServer((request, response) => {
    const started = performance.now();
    // Do not log query strings, bodies or headers: they can contain credentials.
    const path = request.url.split('?')[0];
    let status = 200;
    let body;

    if (request.method !== 'GET' && request.method !== 'HEAD') {
      status = 405;
      response.setHeader('Allow', 'GET, HEAD');
      body = { error: 'Method not allowed' };
    } else if (path === '/') {
      body = { service: 'sample-service', version, message: 'Hello from the IDP' };
    } else if (path === '/healthz') {
      body = { status: 'ok' };
    } else if (path === '/readyz') {
      status = ready ? 200 : 503;
      body = { status: ready ? 'ready' : 'draining' };
    } else {
      status = 404;
      body = { error: 'Not found' };
    }

    response.writeHead(status, {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
    });
    response.end(request.method === 'HEAD' ? undefined : JSON.stringify(body));
    logger(JSON.stringify({
      level: 'info', event: 'request', method: request.method, path,
      status, durationMs: Math.round((performance.now() - started) * 100) / 100,
    }));
  });
  server.requestTimeout = 15000;
  server.headersTimeout = 10000;
  server.timeout = 15000;
  server.keepAliveTimeout = 5000;
  return { server, setReady: (value) => { ready = value; } };
}
