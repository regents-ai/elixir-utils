// Accepted invariant: preparation cannot read private data; execution cannot
// change signed bytes/destination or acquire authority from browser credentials.
import {test} from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import {signedTools, Refused} from './signed_tools.ts'
import type {SignedOperation, PreparedRequest, HostSigner} from './signed_tools.ts'

const protocol = JSON.parse(readFileSync(new URL('../../siwa/contract/contract.json', import.meta.url), 'utf8'))
const config: Parameters<typeof signedTools>[0] = {
  origin: 'https://example.test', trustedOrigins: ['https://example.test'], audience: 'fixture',
  proofHeaders: protocol.forwarded_headers as string[],
  requestHeaders: operation => ({'x-regent-client': `webmcp/${operation}`}),
  operations: [{name: 'create', route: 'POST /tools/notes', authentication: 'siwa_per_request',
    availability: 'available', operation_id_field: 'operation_id',
    input_schema: {properties: {title: {type: 'string'}, operation_id: {type: 'string'}}, required: ['title', 'operation_id']}},
    {name: 'read', route: 'GET /tools/notes/{id}', authentication: 'siwa_per_request', availability: 'available',
      input_schema: {properties: {id: {type: 'string'}}, required: ['id']}},
    {name: 'poll', route: 'POST /tools/fleets/{id}/polls', authentication: 'siwa_per_request', availability: 'available',
      input_schema: {properties: {id: {type: 'string'}, choices: {type: 'array', minItems: 2, maxItems: 10,
        items: {type: 'string', minLength: 1, maxLength: 100}}, minutes: {type: 'integer', minimum: 1, maximum: 60}},
        required: ['id', 'choices', 'minutes']}},
    {name: 'report', route: 'POST /tools/reports', authentication: 'siwa_per_request', availability: 'available',
      input_schema: {properties: {arguments: {type: 'object', additionalProperties: true, maxBytes: 8192},
        observation: {type: 'object', properties: {worked: {type: 'boolean'}, score: {type: 'number', minimum: 0, maximum: 1},
          detail: {type: 'null'}}, required: ['worked']}, verdict: {type: 'string', enum: ['worked', 'failed']}},
        required: ['arguments', 'observation', 'verdict']}},
    {name: 'raw', route: 'POST /tools/publications', authentication: 'siwa_per_request', availability: 'available',
      request_body: {encoding: 'raw_json', field: 'raw_body', maxBytes: 2097152},
      input_schema: {properties: {raw_body: {type: 'string'}}, required: ['raw_body']}}],
}
const input = {title: 'Exact café bytes', operation_id: 'a logical operation'}
const proof = Object.fromEntries(config.proofHeaders.map(header => [header, 'fixture-not-a-signature']))
const poll = {id: 'a fleet', choices: ['Yes', 'No'], minutes: 30}
const report = {arguments: {filters: ['open', 2, true, null, {label: 'café'}]},
  observation: {worked: true, score: 0.5, detail: null}, verdict: 'worked'}
const rawBody = ' \n{ "text": "café\\n", "tags": [true, null, 3.25] } \t'
const atLimit = '{"text":"' + 'é'.repeat(1_048_570) + 'a' + '"}'

type Sent = {url: string; options: RequestInit}
const host = globalThis as {regentsSign?: HostSigner}

// A host signer that records what it was asked to sign and answers `answer`.
async function withHost(answer: (prepared: PreparedRequest) => unknown,
  run: (signed: PreparedRequest[], sent: Sent[]) => Promise<void>) {
  const previous = globalThis.fetch
  const signed: PreparedRequest[] = []
  const sent: Sent[] = []
  globalThis.fetch = async (url, options) => {sent.push({url: String(url), options: options!}); return new Response('{}')}
  host.regentsSign = async prepared => {signed.push(prepared); return answer(prepared) as never}
  try { await run(signed, sent) } finally { globalThis.fetch = previous; delete host.regentsSign }
}

test('the host signs the exact request once and those bytes are sent without cookies', async () => {
  await withHost(() => ({headers: {...proof, cookie: 'ignored', authorization: 'ignored', 'x-trace': 'harmless'}}), async (signed, sent) => {
    const tools = signedTools(config)
    await tools.execute('create', input)
    assert.equal(signed.length, 1)
    assert.equal(Object.isFrozen(signed[0]), true)
    assert.deepEqual({...signed[0]}, {operation: 'create', audience: 'fixture', origin: 'https://example.test',
      method: 'POST', path: '/tools/notes', body: JSON.stringify(input)})
    assert.equal(sent.length, 1)
    assert.equal(sent[0].url, 'https://example.test/tools/notes')
    assert.equal(sent[0].options.body, signed[0].body)
    assert.equal(sent[0].options.credentials, 'omit')
    assert.equal(sent[0].options.redirect, 'error')
    const headers = sent[0].options.headers as Record<string, string>
    assert.equal(headers.authorization, undefined)
    assert.equal(headers.cookie, undefined)
    assert.equal(headers['x-trace'], undefined)
    assert.equal(headers['x-regent-client'], 'webmcp/create')
    for (const header of config.proofHeaders) assert.equal(headers[header], 'fixture-not-a-signature')
    for (const [name, values] of [['poll', poll], ['report', report]] as const) {
      await tools.execute(name, values)
      assert.equal(sent.at(-1)!.options.body, signed.at(-1)!.body)
      const {id: _id, ...expectedBody} = values as Record<string, unknown>
      assert.deepEqual(JSON.parse(signed.at(-1)!.body!), expectedBody)
    }
    assert.equal(sent[1].url, 'https://example.test/tools/fleets/a%20fleet/polls')
    assert.equal(new TextEncoder().encode(atLimit).length, 2097152)
    const manyFiles = JSON.stringify({files: Array.from({length: 101}, (_, id) => ({id})),
      metadata: Object.fromEntries(Array.from({length: 101}, (_, id) => [String(id), true]))})
    for (const raw_body of [rawBody, atLimit, manyFiles]) {
      await tools.execute('raw', {raw_body})
      assert.equal(signed.at(-1)!.body, raw_body)
      assert.equal(sent.at(-1)!.options.body, raw_body)
    }
    const read = {...proof}
    delete read['content-digest']
    host.regentsSign = async prepared => {signed.push(prepared); return {headers: read}}
    await tools.execute('read', {id: 'a/b'})
    assert.equal(signed.at(-1)!.body, undefined)
    assert.equal(sent.at(-1)!.url, 'https://example.test/tools/notes/a%2Fb')
    assert.equal(sent.at(-1)!.options.method, 'GET')
    assert.equal(sent.length, 7)
  })
})

test('with no host signer nothing is sent and the agent is told how to sign', async () => {
  const previous = globalThis.fetch
  globalThis.fetch = async () => {throw new Error('must not send')}
  try {
    delete host.regentsSign
    const refused = await signedTools(config).execute('create', input).catch(error => error)
    assert.ok(refused instanceof Refused)
    assert.equal(refused.refusal.code, 'agent_auth_required')
    assert.match(refused.refusal.hint!, /regents browser --site fixture/)
  } finally { globalThis.fetch = previous }
})

test('a refusal or an incomplete proof from the host signer sends nothing', async () => {
  const refusal = {code: 'invocation_not_found', message: 'No call is waiting for this request.', hint: 'Call the tool again.'}
  await withHost(() => ({error: refusal}), async (signed, sent) => {
    const refused = await signedTools(config).execute('create', input).catch(error => error)
    assert.ok(refused instanceof Refused)
    assert.deepEqual(refused.refusal, refusal)
    assert.equal(signed.length, 1)
    assert.equal(sent.length, 0)
  })
  for (const [answer, reason] of [
    [{headers: {...proof, 'X-SIWA-SIGNATURE': 'duplicate'}}, /invalid_proof/],
    [{headers: {}}, /incomplete_proof/],
    [{headers: 'x'}, /proof_required/],
    [{}, /proof_required/],
    ['headers', /invalid_signer_answer/],
    [{error: {code: 7}}, /invalid_signer_answer/],
  ] as const) {
    await withHost(() => answer, async (_signed, sent) => {
      await assert.rejects(signedTools(config).execute('create', input), reason)
      assert.equal(sent.length, 0)
    })
  }
  const withoutDigest = {...proof}
  delete withoutDigest['content-digest']
  await withHost(() => ({headers: withoutDigest}), async (_signed, sent) => {
    await assert.rejects(signedTools(config).execute('create', input), /body_proof_required/)
    assert.equal(sent.length, 0)
    await signedTools(config).execute('read', {id: 'x'})
    assert.equal(sent.length, 1)
  })
  await withHost(() => ({headers: proof}), async (_signed, sent) => {
    await assert.rejects(signedTools(config).execute('read', {id: 'x'}), /unexpected_body_proof/)
    for (const labels of [{accept: 'text/html'}, {cookie: 'a'}, {'X-Upper': 'a'}, {'x-line': 'a\nb'},
      {[config.proofHeaders[0]]: 'a'}] as Record<string, string>[]) {
      const labelled = signedTools({...config, requestHeaders: () => labels})
      await assert.rejects(labelled.execute('create', input), /invalid_request_header/)
    }
    assert.equal(sent.length, 0)
  })
})

test('inputs outside the manifest are refused before the host signer is asked', async () => {
  await withHost(() => ({headers: proof}), async (signed, sent) => {
    const tools = signedTools(config)
    const refuses = (name: string, values: unknown, reason: RegExp) =>
      assert.rejects(tools.execute(name, values as Record<string, unknown>), reason)
    await refuses('arbitrary', {}, /operation_unavailable/)
    await refuses('read', {id: '..'}, /invalid_path_field/)
    assert.throws(() => signedTools({...config, origin: 'https://evil.test'}), /untrusted_origin/)
    for (const invalid of [ {...poll, extra: 'authority'}, {...poll, minutes: '30'}, {...poll, minutes: 1.5},
      {...poll, minutes: 0}, {...poll, minutes: NaN}, {...poll, minutes: Number.MAX_SAFE_INTEGER + 1},
      {...poll, choices: ['Yes', 2]}, {...poll, choices: ['Yes']}, {...poll, choices: Array(11).fill('Yes')},
      {...poll, choices: ['Yes', 'x'.repeat(101)]} ]) {
      await refuses('poll', invalid, /invalid_field/)
    }
    for (const invalid of [ {...report, observation: {worked: true, cookie: 'authority'}},
      {...report, observation: {worked: 'true'}}, {...report, verdict: 'invented'},
      {...report, arguments: {text: 'é'.repeat(4096)}}, {...report, arguments: {value: undefined}},
      {...report, arguments: {value: Infinity}}, {...report, arguments: {value: new Date()}},
      {...report, arguments: JSON.parse('{"__proto__":{"cookie":"authority"}}'), observation: {}} ]) {
      await refuses('report', invalid, /invalid_field|missing_field|unsupported_field_type/)
    }
    await refuses('create', JSON.parse('{"title":"ok","operation_id":"id","__proto__":{}}'), /invalid_field/)
    await refuses('create', {title: 'no operation id', operation_id: ''}, /operation_id_required/)
    let deep: unknown = null
    for (let level = 0; level < 17; level++) deep = {value: deep}
    await refuses('report', {...report, arguments: {deep}}, /input_complexity_exceeded/)
    const wide = Array.from({length: 100}, () => Array(100).fill(null))
    await refuses('report', {...report, arguments: {wide}}, /input_complexity_exceeded/)
    const manyBytes = Array.from({length: 100}, () => Array(3).fill('x'.repeat(10_000)))
    await refuses('report', {...report, arguments: {manyBytes}}, /body_too_large/)
    const unsupported = signedTools({...config, operations: [{...config.operations[0],
      input_schema: {properties: {title: {type: 'binary'}}, required: ['title']}}]})
    await assert.rejects(unsupported.execute('create', {title: 'bytes'}), /unsupported_field_type/)
    for (const raw_body of ['{bad}', '[1]', '{"text":"\ud800"}']) {
      await refuses('raw', {raw_body}, /invalid_raw_body|invalid_field/)
    }
    await refuses('raw', {raw_body: atLimit + ' '}, /body_too_large/)
    await refuses('raw', {raw_body: rawBody, authorization: 'authority'}, /invalid_field/)
    for (const change of [{encoding: 'text'}, {maxBytes: 2097153}, {field: 'missing'}]) {
      const raw = config.operations.find(operation => operation.name === 'raw')!
      const badManifest = signedTools({...config, operations: [{...raw, request_body: {...raw.request_body!, ...change}} as SignedOperation]})
      await assert.rejects(badManifest.execute('raw', {raw_body: rawBody}), /invalid_operation/)
    }
    assert.equal(signed.length, 0)
    assert.equal(sent.length, 0)
  })
})
