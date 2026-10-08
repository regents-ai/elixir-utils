# Changelog

## Unreleased

- New `RegentChain.Transaction`: `sign/2` signs an EIP-1559 (type 2) transaction
  with a key the app holds and returns the raw bytes and their hash, which the app
  keeps before it broadcasts; `address/1` is the key's account. Pure: the app reads
  the nonce and fees and broadcasts. Adds the `ex_rlp` dependency.

## 0.3.0 (2026-09-28)

- New `RegentChain.Abi`: contract return data and event data, `bytes`, `string`
  and arrays included, read only in their one canonical encoding, plus JSON-RPC
  data, quantities and hashes. Taken from Keyfleet's `Keyfleet.Chain.Abi`.
- `RegentChain.Call` encodes the zero address as an argument, so a step can clear
  a delegate. New `Address.argument/1` reads it; a review's signer and a step's
  contract still refuse it.
- New `Outcome.sent/4`: whether the chain holds a step's transaction yet,
  without its receipt, so a report can be refused before anything is saved.
- New `RegentChain.Typed`: the EIP-712 digest of a signature step's typed data,
  the wallet that signed it (`v` as 0 or 1 read as 27 or 28), and the signature
  as contracts take it. Adds the `ex_secp256k1` dependency. From Patchbay's
  `WalletPayment.payment/3`.
- `Presses.failed/1` takes `sign_unconfirmed`: the wallet failed after a signature
  was asked for, so it may have signed.

## 0.2.0 (2026-09-27)

Breaking, adopt in one change:

- `Review.new/5` takes the on-screen `inputs` and gives each review an `id` derived
  from everything in it. The page reports presses by that id.
- Transaction steps carry `kind: "transaction"`; `Review.signature/2` adds EIP-712
  signature steps. `Review.find/2` names a step.
- `Outcome.of/4` takes the review and the step, reads the review's chain, and
  checks the transaction's chain id too. The client's `transaction/2` and
  `receipt/2` take the chain first.
- A review's `rpc_url` may be `http://127.0.0.1:` or `http://localhost:` for a lab
  chain.
- New `RegentChain.Presses`: the reviews a page pushed and each sent step, checked
  against the review it was sent from.

## 0.1.0

- Initial release: checked addresses, contract calldata, the review pushed to a
  wallet button, the check of a sent step, and single-event reads. Taken from
  Autolaunch's `Autolaunch.Chain` helpers, hashing with `ex_keccak`.
