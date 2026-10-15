Follow ../AGENTS.md and the Regent workflow, Ash and Elixir skills. This package
adapts verified OAuth account connections to the shared hosted SIWA signer.
It never stores keys, accepts a caller-supplied identity, signs payments or
implements a second posting action. Run mix check. Never log bearer tokens,
pairing codes, signed envelopes, request bodies or internal signer responses.
