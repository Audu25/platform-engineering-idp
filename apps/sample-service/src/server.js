import { createApp } from './app.js';

const port = Number(process.env.PORT ?? 8080);
if (!Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error('PORT must be an integer between 1 and 65535');
}
const { server, setReady } = createApp({ version: process.env.APP_VERSION ?? '0.1.0' });
server.listen(port, '0.0.0.0', () => {
  console.log(JSON.stringify({ level: 'info', event: 'listening', port }));
});
server.on('error', (error) => {
  console.error(JSON.stringify({ level: 'error', event: 'server_error', code: error.code }));
  process.exitCode = 1;
});

let stopping = false;
function shutdown(signal) {
  if (stopping) return;
  stopping = true;
  setReady(false);
  console.log(JSON.stringify({ level: 'info', event: 'shutdown', signal }));
  // Stop accepting connections and allow in-flight requests to finish.
  server.close(() => { process.exitCode = 0; });
  setTimeout(() => {
    server.closeAllConnections();
    process.exit(1);
  }, 10000).unref();
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
