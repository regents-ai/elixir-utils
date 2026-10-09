// Accepted invariant: preparation cannot read private data; execution cannot
// change signed bytes/destination or acquire authority from browser credentials.
import {test} from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
import {signedTools} from './signed_tools.ts'

const protocol = JSON.parse(readFileSync(new URL('../../siwa/contract/contract.json', import.meta.url), 'utf8'))
const config = {
  origin: 'https://example.test', trustedOrigins: ['https://example.test'], audience: 'fixture',
  proofHeaders: protocol.forwarded_headers as string[],
  operations: [{name: 'create', route: 'POST /tools/notes', authentication: 'siwa_per_request',
    availability: 'available', operation_id_field: 'operation_id',
    input_schema: {properties: {title: {type: 'string'}, operation_id: {type: 'string'}}, required: ['title', 'operation_id']}},
    {name: 'read', route: 'GET /tools/notes/{id}', authentication: 'siwa_per_request', availability: 'available',
      input_schema: {properties: {id: {type: 'string'}}, required: ['id']}}],
}
const input = {title: 'Exact café bytes', operation_id: 'a logical operation'}
const proof = Object.fromEntries(config.proofHeaders.map(header => [header, 'fixture-not-a-signature']))

test('exact prepared bytes are forwarded once without cookies or unrelated authority headers', async () => {
  const previous = globalThis.fetch
  const sent: {url: string; options: RequestInit}[] = []
  globalThis.fetch = async (url, options) => {sent.push({url: String(url), options: options!}); return new Response('{}')}
  try {
    const tools = signedTools(config)
    const request = tools.prepare('create', input)
    assert.equal(sent.length, 0)
    await tools.execute('create', {input, request, proof: {...proof, cookie: 'ignored', authorization: 'ignored', 'x-trace': 'harmless'}})
    assert.equal(sent.length, 1)
    assert.equal(sent[0].url, 'https://example.test/tools/notes')
    assert.equal(sent[0].options.body, request.body)
    assert.equal(sent[0].options.credentials, 'omit')
    assert.equal(sent[0].options.redirect, 'error')
    assert.equal((sent[0].options.headers as Record<string, string>).authorization, undefined)
    assert.equal((sent[0].options.headers as Record<string, string>).cookie, undefined)
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
  } finally { globalThis.fetch = previous }
})
