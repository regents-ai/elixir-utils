import {test} from "node:test";
import assert from "node:assert/strict";
import {createProfileClient} from "../../assets/profile_client.mjs";

test("profile operations send the site's session, and a change its forms token", async () => {
  const calls = [];
  const payload = {profile: {profile_id: "canonical-id", x: null, wallet: {address: null, verified: false}}};
  let token = "first-token";
  const client = createProfileClient({csrfToken: () => token, fetch: async (url, options) => {
    calls.push({url, ...options});
    return {ok: true, status: 200, json: async () => payload};
  }});
  assert.deepEqual(await client("get"), {ok: true, status: 200, body: payload});
  token = "renewed-token";
  assert.deepEqual(await client("update", {display_name: "Alice"}, {expectedProfileId: "canonical-id"}),
    {ok: true, status: 200, body: payload});
  assert.deepEqual(calls.map(call => [call.method, call.url]), [["GET", "/api/v1/profile"], ["PATCH", "/api/v1/profile"]]);
  for (const call of calls) {
    assert.equal(call.redirect, "error");
    assert.equal(call.credentials, "same-origin");
  }
  assert.equal(calls[0].headers["x-csrf-token"], undefined);
  assert.equal(calls[1].headers["x-csrf-token"], "renewed-token");
  assert.equal(calls[1].headers["x-regent-profile-id"], "canonical-id");
  assert.equal(calls[1].body, JSON.stringify({display_name: "Alice"}));
});

test("a change whose answer never arrives may have been made", async () => {
  const client = createProfileClient({csrfToken: () => "token", fetch: async () => { throw new TypeError("network"); }});
  assert.deepEqual(await client("update", {display_name: "Alice"}),
    {ok: false, status: null, error: {code: "profile_unavailable", outcome_unknown: true}});
  assert.deepEqual(await client("get"),
    {ok: false, status: null, error: {code: "profile_unavailable", outcome_unknown: false}});
});

test("cancelled or unknown operations send nothing", async () => {
  const abort = new AbortController(); abort.abort();
  const client = createProfileClient({csrfToken: () => assert.fail("must not read"), fetch: () => assert.fail("must not send")});
  assert.equal((await client("get", {}, {signal: abort.signal})).error.code, "cancelled");
  for (const operation of ["delete", "constructor"]) {
    assert.equal((await client(operation)).error.code, "invalid_profile_operation");
  }
  assert.equal((await client("update", {privy_user_id: "other"})).error.code, "invalid_profile_operation");
});
