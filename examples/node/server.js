const http = require('node:http');
const pino = require('pino'); // proves node_modules from node-build works in node-runtime

// No shell/curl in distroless: the app checks itself for HEALTHCHECK.
if (process.argv[2] === 'healthcheck') {
  http.get('http://127.0.0.1:8080/healthz', { timeout: 2000 }, (r) => process.exit(r.statusCode === 200 ? 0 : 1))
    .on('error', () => process.exit(1));
} else {
  const log = pino();
  const server = http.createServer((req, res) => {
    res.end(req.url === '/healthz' ? 'ok\n' : `hello from node ${process.version}, uid=${process.getuid()}\n`);
  });
  server.listen(8080, () => log.info('listening on :8080'));
  // PID 1 gets no default signal handlers: shut down cleanly on SIGTERM.
  process.on('SIGTERM', () => server.close(() => process.exit(0)));
}
