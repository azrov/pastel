// Tests for routes.ts: finding routes and jobs, and sending requests. Run: npm test
import * as assert from 'assert';
import * as http from 'http';
import { devSettings, fillPath, formatResult, parseJobs, parseRoutes, pathParams, sendHttp } from '../routes';

let passed = 0;
async function test(name: string, fn: () => void | Promise<void>): Promise<void> {
  try {
    await fn();
    passed++;
  } catch (e) {
    console.error('FAIL:', name);
    console.error(e);
    process.exitCode = 1;
  }
}

const source = [
  'procedure TTasksController.Routes(Web: TWebServer);',   // 0
  'begin',                                                 // 1
  "  Web.Get('/api/tasks', @ListTasks);",                  // 2
  "  Web.Post('/api/tasks', @CreateTask);  // new ones",   // 3
  "  // Web.Get('/old', @Old);",                           // 4
  "  { Web.Get('/older', @Older); }",                      // 5
  "  Web.Delete('/api/tasks/:id', @DeleteTask);",          // 6
  "  Web.Static('/', 'public');",                          // 7
  "  Web.Health('/health', AppVersion);",                  // 8
  "  Server.patch( '/x/:a/*' , Ctl.Change);",              // 9
  '  {',                                                   // 10
  "    Web.Get('/in-comment', @Hidden);",                  // 11
  '  }',                                                   // 12
  "  Every(30, @CheckDisk, 'disk');",                      // 13
  "  DailyAt('23:55', @Nightly);",                         // 14
  'end;',
].join('\n');

(async () => {
  await test('finds routes, not in comments', () => {
    assert.deepStrictEqual(parseRoutes(source).map(r => `${r.line} ${r.method} ${r.path} ${r.handler}`), [
      '2 GET /api/tasks ListTasks',
      '3 POST /api/tasks CreateTask',
      '6 DELETE /api/tasks/:id DeleteTask',
      '7 STATIC / public',
      '8 GET /health health check',
      '9 PATCH /x/:a/* Ctl.Change',
    ]);
  });
  await test('finds jobs', () => {
    assert.deepStrictEqual(parseJobs(source).map(j => `${j.line} ${j.schedule} ${j.handler}`),
      ['13 every 30 s CheckDisk', '14 daily 23:55 Nightly']);
  });
  await test('path parameters', () => {
    assert.deepStrictEqual(pathParams('/x/:a/b/:id/*'), ['a', 'id', '*']);
    assert.strictEqual(fillPath('/x/:a/b/:id/*', { a: 'ş y', id: '7', '*': 'f/g.txt' }), '/x/%C5%9F%20y/b/7/f/g.txt');
  });
  await test('development settings', () => {
    assert.deepStrictEqual(devSettings('[server]\nport = 9000 # dev\n[api]\nkeys = ["k-123", "k-2"]\n'),
      { port: 9000, apiKey: 'k-123' });
    assert.deepStrictEqual(devSettings('[api]\nkeys = ["CHANGE-ME-x"]\n[other]\nport = 1\n'), {});
  });
  await test('sends requests and reads answers', async () => {
    const server = http.createServer((req, res) => {
      let body = '';
      req.on('data', c => body += c);
      req.on('end', () => {
        res.writeHead(201, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ method: req.method, url: req.url, key: req.headers['x-api-key'], body }));
      });
    });
    await new Promise<void>(r => server.listen(0, '127.0.0.1', r));
    const port = (server.address() as { port: number }).port;
    try {
      const url = `http://127.0.0.1:${port}/api/tasks?x=1`;
      const r = await sendHttp('POST', url, { 'X-API-Key': 'k', 'Content-Type': 'application/json' }, '{"title":"Süt"}');
      assert.strictEqual(r.status, 201);
      assert.deepStrictEqual(JSON.parse(r.body), { method: 'POST', url: '/api/tasks?x=1', key: 'k', body: '{"title":"Süt"}' });
      const text = formatResult('POST', url, r);
      assert.ok(text.includes('HTTP 201 Created'), text);
      assert.ok(text.includes('  "method": "POST"'), 'pretty JSON');
    } finally {
      server.close();
    }
  });
  await test('explains a server that is not running', async () => {
    await assert.rejects(sendHttp('GET', 'http://127.0.0.1:1/', {}), /ECONNREFUSED/);
  });
  console.log(`routes: ${passed} passed`);
})();
