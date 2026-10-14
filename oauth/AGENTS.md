# Regent OAuth

Follow ../AGENTS.md and the workspace regent-workflow, ash-stack and elixir-stack.
This package adapts Boruta's OAuth protocol; it must not implement its own grants,
PKCE, token rotation or job queues. Sites own Privy login, account authorization,
consent pages, their database schema and supervision. Run mix check here.
Never log tokens, codes, client secrets, request bodies or query strings.
