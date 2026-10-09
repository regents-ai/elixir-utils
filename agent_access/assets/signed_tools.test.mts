// Accepted invariant: preparation cannot read private data; execution cannot
// change signed bytes/destination or acquire authority from browser credentials.
import {test} from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import {signedTools} from './signed_tools.ts'
import type {SignedOperation} from './signed_tools.ts'

const protocol = JSON.parse(readFileSync(new URL('../../siwa/contract/contract.json', import.meta.url), 'utf8'))
const config: Parameters<typeof signedTools>[0] = {
  origin: 'https://example.test', trustedOrigins: ['https://example.test'], audience: 'fixture',
  proofHeaders: protocol.forwarded_headers as string[],
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

test('exact prepared bytes are forwarded once without cookies or unrelated authority headers', async () => {
  const previous = globalThis.fetch
  const sent: {url: string; options: RequestInit}[] = []
  globalThis.fetch = async (url, options) => {sent.push({url: String(url), options: options!}); return new Response('{}')}
  try {
    const tools = signedTools(config)
    const request = tools.prepare('create', input)
    assert.equal(Object.isFrozen(request), true)
    assert.equal(sent.length, 0)
    await tools.execute('create', {input, request, proof: {...proof, cookie: 'ignored', authorization: 'ignored', 'x-trace': 'harmless'}})
    assert.equal(sent.length, 1)
    assert.equal(sent[0].url, 'https://example.test/tools/notes')
    assert.equal(sent[0].options.body, request.body)
    assert.equal(sent[0].options.credentials, 'omit')
    assert.equal(sent[0].options.redirect, 'error')
    assert.equal((sent[0].options.headers as Record<string, string>).authorization, undefined)
    assert.equal((sent[0].options.headers as Record<string, string>).cookie, undefined)
    for (const [name, values] of [['poll', poll], ['report', report]] as const) {
      const prepared = tools.prepare(name, values)
      await tools.execute(name, {input: values, request: prepared, proof})
      assert.equal(sent.at(-1)!.options.body, prepared.body)
      const {id: _id, ...expectedBody} = values as Record<string, unknown>
      assert.deepEqual(JSON.parse(prepared.body!), expectedBody)
    }
    assert.equal(sent[1].url, 'https://example.test/tools/fleets/a%20fleet/polls')
    assert.equal(new TextEncoder().encode(atLimit).length, 2097152)
    const manyFiles = JSON.stringify({files: Array.from({length: 101}, (_, id) => ({id})),
      metadata: Object.fromEntries(Array.from({length: 101}, (_, id) => [String(id), true]))})
    for (const raw_body of [rawBody, atLimit, manyFiles]) {
      const values = {raw_body}
      const prepared = tools.prepare('raw', values)
      assert.equal(prepared.body, raw_body)
      await tools.execute('raw', {input: values, request: prepared, proof: {...proof, 'x-publication-title': 'ignored'}})
      assert.equal(sent.at(-1)!.options.body, raw_body)
      assert.equal((sent.at(-1)!.options.headers as Record<string, string>)['x-publication-title'], undefined)
    }
    assert.equal(sent.length, 6)
  } finally { globalThis.fetch = previous }
})

test('changed bytes, operation, origin, path and ambiguous proofs fail before sending', async () => {
  const previous = globalThis.fetch
  globalThis.fetch = async () => {throw new Error('must not send')}
  try {
    const tools = signedTools(config)
    const request = tools.prepare('create', input)
    for (const alteration of [{body: '{}'}, {method: 'GET'}, {origin: 'https://evil.test'},
      {path: '/other'}, {operation: 'read'}, {extra: 'not allowed'}]) {
      await assert.rejects(tools.execute('create', {input, request: {...request, ...alteration}, proof}), /prepared_request_mismatch/)
    }
    await assert.rejects(tools.execute('create', {input, request, proof: {...proof, 'X-SIWA-SIGNATURE': 'duplicate'}}), /invalid_proof/)
    await assert.rejects(tools.execute('create', {input, request, proof: {}}), /incomplete_proof/)
    assert.throws(() => tools.prepare('arbitrary', {}), /operation_unavailable/)
    assert.throws(() => tools.prepare('read', {id: '..'}), /invalid_path_field/)
    assert.throws(() => signedTools({...config, origin: 'https://evil.test'}), /untrusted_origin/)
    for (const invalid of [ {...poll, extra: 'authority'}, {...poll, minutes: '30'}, {...poll, minutes: 1.5},
      {...poll, minutes: 0}, {...poll, minutes: NaN}, {...poll, minutes: Number.MAX_SAFE_INTEGER + 1},
      {...poll, choices: ['Yes', 2]}, {...poll, choices: ['Yes']}, {...poll, choices: Array(11).fill('Yes')},
      {...poll, choices: ['Yes', 'x'.repeat(101)]} ]) {
      assert.throws(() => tools.prepare('poll', invalid), /invalid_field/)
    }
    for (const invalid of [ {...report, observation: {worked: true, cookie: 'authority'}},
      {...report, observation: {worked: 'true'}}, {...report, verdict: 'invented'},
      {...report, arguments: {text: 'é'.repeat(4096)}}, {...report, arguments: {value: undefined}},
      {...report, arguments: {value: Infinity}}, {...report, arguments: {value: new Date()}},
      {...report, arguments: JSON.parse('{"__proto__":{"cookie":"authority"}}'), observation: {}} ]) {
      assert.throws(() => tools.prepare('report', invalid), /invalid_field|missing_field|unsupported_field_type/)
    }
    assert.throws(() => tools.prepare('create', JSON.parse('{"title":"ok","operation_id":"id","__proto__":{}}')), /invalid_field/)
    let deep: unknown = null
    for (let level = 0; level < 17; level++) deep = {value: deep}
    assert.throws(() => tools.prepare('report', {...report, arguments: {deep}}), /input_complexity_exceeded/)
    const wide = Array.from({length: 100}, () => Array(100).fill(null))
    assert.throws(() => tools.prepare('report', {...report, arguments: {wide}}), /input_complexity_exceeded/)
    const manyBytes = Array.from({length: 100}, () => Array(3).fill('x'.repeat(10_000)))
    assert.throws(() => tools.prepare('report', {...report, arguments: {manyBytes}}), /body_too_large/)
    const unsupported = signedTools({...config, operations: [{...config.operations[0],
      input_schema: {properties: {title: {type: 'binary'}}, required: ['title']}}]})
    assert.throws(() => unsupported.prepare('create', {title: 'bytes'}), /unsupported_field_type/)
    const preparedPoll = tools.prepare('poll', poll)
    await assert.rejects(tools.execute('poll', {input: {...poll, choices: ['No', 'Yes']}, request: preparedPoll, proof}), /prepared_request_mismatch/)
    const preparedRaw = tools.prepare('raw', {raw_body: rawBody})
    await assert.rejects(tools.execute('raw', {input: {raw_body: rawBody.trim()}, request: preparedRaw, proof}), /prepared_request_mismatch/)
    for (const raw_body of ['{bad}', '[1]', '{"text":"\ud800"}']) {
      assert.throws(() => tools.prepare('raw', {raw_body}), /invalid_raw_body|invalid_field/)
    }
    assert.throws(() => tools.prepare('raw', {raw_body: atLimit + ' '}), /body_too_large/)
    assert.throws(() => tools.prepare('raw', {raw_body: rawBody, authorization: 'authority'}), /invalid_field/)
    for (const change of [{encoding: 'text'}, {maxBytes: 2097153}, {field: 'missing'}]) {
      const raw = config.operations.find(operation => operation.name === 'raw')!
      const badManifest = signedTools({...config, operations: [{...raw, request_body: {...raw.request_body!, ...change}} as SignedOperation]})
      assert.throws(() => badManifest.prepare('raw', {raw_body: rawBody}), /invalid_operation/)
    }
  } finally { globalThis.fetch = previous }
})
