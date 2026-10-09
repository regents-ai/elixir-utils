// Transport only. SIWA's existing signer owns keys, receipts and signatures.
export type SignedOperation = {
  name: string
  route: string
  authentication: string
  availability: string
  operation_id_field?: string
  input_schema: {properties: Record<string, {type: string; maxLength?: number}>; required: string[]}
}
export type PreparedRequest = {
  operation: string
  audience: string
  origin: string
  method: string
  path: string
  body?: string
}
export type SignedInput = {input: Record<string, string>; request: PreparedRequest; proof: Record<string, string>}

export function signedTools(config: {
  origin: string
  trustedOrigins: readonly string[]
  audience: string
  operations: readonly SignedOperation[]
  proofHeaders: readonly string[]
}) {
  const origin = new URL(config.origin).origin
  if (origin !== config.origin || !config.trustedOrigins.includes(origin)) throw new Error("untrusted_origin")
  if (!/^https:\/\//.test(origin) && !/^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin)) {
    throw new Error("insecure_origin")
  }

  function prepare(name: string, input: Record<string, string>): PreparedRequest {
    const operation = config.operations.find(entry => entry.name === name)
    if (!operation || operation.authentication !== "siwa_per_request" || operation.availability !== "available") {
      throw new Error("operation_unavailable")
    }
    if (!input || Array.isArray(input) || typeof input !== "object") throw new Error("invalid_input")
    for (const key of operation.input_schema.required) {
      if (!Object.hasOwn(input, key)) throw new Error(`missing_field:${key}`)
    }
    for (const [key, value] of Object.entries(input)) {
      const field = operation.input_schema.properties[key]
      if (!field || field.type !== "string" || typeof value !== "string" || value.length > (field.maxLength ?? 10000)) {
        throw new Error(`invalid_field:${key}`)
      }
    }
    const [method, template, extra] = operation.route.split(" ")
    if (extra || !["GET", "POST", "PATCH", "DELETE"].includes(method)) throw new Error("invalid_operation")
    const body = {...input}
    const path = template.replace(/\{([a-z_]+)\}/g, (_match, field: string) => {
      const value = body[field]
      if (!value || value === "." || value === "..") throw new Error(`invalid_path_field:${field}`)
      delete body[field]
      return encodeURIComponent(value)
    })
    // No arbitrary destinations, redirects, fragments or unsigned queries.
    const target = new URL(path, origin)
    if (!path.startsWith("/") || path.startsWith("//") || target.origin !== origin ||
        target.pathname !== path || target.search || target.hash || /[{}\\]/.test(path)) throw new Error("invalid_path")
    if (method === "GET" && Object.keys(body).length) throw new Error("unexpected_read_body")
    const request: PreparedRequest = {operation: name, audience: config.audience, origin, method, path}
    if (method !== "GET") {
      if (operation.operation_id_field && !body[operation.operation_id_field]) throw new Error("operation_id_required")
      request.body = JSON.stringify(body)
    }
    return request
  }

  async function execute(name: string, signed: SignedInput, signal?: AbortSignal): Promise<Response> {
    if (!signed || typeof signed !== "object") throw new Error("signed_request_required")
    const expected = prepare(name, signed.input)
    if (!signed.request || Object.keys(signed.request).some(key => !Object.hasOwn(expected, key)) ||
        Object.entries(expected).some(([key, value]) => signed.request[key as keyof PreparedRequest] !== value)) {
      throw new Error("prepared_request_mismatch")
    }
    if (!signed.proof || typeof signed.proof !== "object" || Array.isArray(signed.proof)) throw new Error("proof_required")
    const allowed = new Set(config.proofHeaders)
    const headers: Record<string, string> = {accept: "application/json"}
    for (const [key, value] of Object.entries(signed.proof)) {
      const name = key.toLowerCase()
      if (!allowed.has(name)) continue
      if (Object.hasOwn(headers, name) || typeof value !== "string" || !value || /[\r\n]/.test(value)) throw new Error("invalid_proof")
      headers[name] = value
    }
    for (const name of allowed) {
      if (name !== "content-digest" && !headers[name]) throw new Error("incomplete_proof")
    }
    if (expected.body !== undefined) {
      if (!headers["content-digest"]) throw new Error("body_proof_required")
      headers["content-type"] = "application/json"
    } else if (headers["content-digest"]) throw new Error("unexpected_body_proof")
    // The product verifies once through SIWA. No retry, session fallback or reserialization.
    return fetch(origin + expected.path, {
      method: expected.method, body: expected.body, headers, credentials: "omit",
      cache: "no-store", redirect: "error", signal,
    })
  }
  return {prepare, execute}
}
