defmodule Regent.MCPEvents.Adapter do
  @moduledoc """
  Product storage and authorization boundary for the shared delivery worker.

  All state is durable in the product database. `claim_next/2` atomically claims
  the earliest outstanding event for one subscription, increments its persisted
  attempt, and grants a fenced lease. A pending retry or retained failed event
  blocks later events for that subscription. Expired leases may be reclaimed;
  the lease must exceed the transport deadline plus storage/authorization time.

  `authorize_delivery/2` reloads the current subscription and rechecks its owner's
  access and event filters. It must reject inactive, expired, revoked or changed
  subscriptions. Return the current signing secret and bounded rotation fields.

  `finish/3` updates only a still-owned lease, atomically. Only `:delivered`
  advances the acknowledged cursor; retry and stop retain the failed occurrence
  and never skip it. No subsequent occurrence may pass a retained failure.
  A stop due to access revocation, expiration, unsubscribe or HTTP 410 disables
  the subscription; other permanent event failures require explicit recovery.
  A crashed worker after HTTP acknowledgement can redeliver the same event ID.
  """

  @type delivery :: %{
          required(:token) => term(),
          required(:subscription) => map(),
          required(:event) => map(),
          required(:attempt) => pos_integer()
        }

  @type outcome ::
          {:delivered, String.t() | nil}
          | {:retry, term(), DateTime.t()}
          | {:stop, term()}

  @callback claim_next(DateTime.t(), pos_integer()) ::
              :empty | {:ok, delivery()} | {:error, term()}
  @callback authorize_delivery(delivery(), DateTime.t()) ::
              {:ok, map()} | {:stop, term()} | {:error, term()}
  @callback finish(delivery(), outcome(), DateTime.t()) :: :ok | {:error, term()}
end
