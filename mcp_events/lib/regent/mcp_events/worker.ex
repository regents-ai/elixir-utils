defmodule Regent.MCPEvents.Worker do
  @moduledoc """
  Supervised delivery of a product's durable outbox through `Regent.MCPEvents.Adapter`.

  Add `{Regent.MCPEvents.Worker, adapter: MyApp.MCPEvents.Adapter}` to the product
  supervisor after its database. Alternatively call `run_once/2` from a durable
  product job. Run one mechanism; the adapter still fences claims across nodes.
  """
  use GenServer

  @default_max_attempts 8

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  @impl true
  def init(opts) do
    Keyword.fetch!(opts, :adapter)

    case validate_options(opts) do
      :ok ->
        send(self(), :deliver)
        {:ok, opts}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_info(:deliver, opts) do
    result = run_once(Keyword.fetch!(opts, :adapter), opts)

    interval =
      if match?({:ok, _}, result), do: 0, else: Keyword.get(opts, :poll_interval_ms, 1000)

    Process.send_after(self(), :deliver, interval)
    {:noreply, opts}
  end

  @doc "Claims and processes at most one occurrence. Storage failures are categorized without their contents."
  def run_once(adapter, opts \\ []) do
    with :ok <- validate_options(opts), do: claim_and_deliver(adapter, opts)
  end

  defp claim_and_deliver(adapter, opts) do
    now = DateTime.utc_now()
    lease_ms = Keyword.get(opts, :lease_ms, 60_000)

    case adapter.claim_next(now, lease_ms) do
      :empty ->
        :empty

      {:error, _} ->
        {:error, :storage_error}

      {:ok, delivery} ->
        outcome = process_delivery(adapter, delivery, opts)

        case adapter.finish(delivery, outcome, DateTime.utc_now()) do
          :ok -> {:ok, outcome}
          {:error, _} -> {:error, :storage_error}
        end
    end
  end

  defp validate_options(opts) do
    max_attempts = Keyword.get(opts, :max_attempts, @default_max_attempts)
    lease_ms = Keyword.get(opts, :lease_ms, 60_000)
    poll_ms = Keyword.get(opts, :poll_interval_ms, 1000)
    deliver = Keyword.get(opts, :deliver, &Regent.MCPEvents.deliver/2)

    if is_integer(max_attempts) and max_attempts in 1..32 and
         is_integer(lease_ms) and lease_ms in 30_000..3_600_000 and
         is_integer(poll_ms) and poll_ms in 1..60_000 and is_function(deliver, 2),
       do: :ok,
       else: {:error, :invalid_worker_options}
  end

  defp process_delivery(adapter, delivery, opts) do
    max_attempts = Keyword.get(opts, :max_attempts, @default_max_attempts)
    now = DateTime.utc_now()

    if delivery.attempt > max_attempts do
      {:stop, :attempts_exhausted}
    else
      case adapter.authorize_delivery(delivery, now) do
        {:ok, subscription} ->
          with :ok <- active(subscription, DateTime.utc_now()),
               true <- same_subscription?(delivery.subscription, subscription) do
            deliver = Keyword.get(opts, :deliver, &Regent.MCPEvents.deliver/2)
            result = deliver.(subscription, delivery.event)
            outcome(result, delivery, max_attempts)
          else
            false -> {:stop, :subscription_changed}
            {:error, reason} -> {:stop, reason}
          end

        {:stop, reason} ->
          {:stop, reason}

        {:error, _} ->
          outcome({:retry, :authorization_unavailable}, delivery, max_attempts)
      end
    end
  end

  defp active(%{active: true, expires_at: nil}, _now), do: :ok

  defp active(%{active: true, expires_at: %DateTime{} = expires}, now) do
    if DateTime.compare(expires, now) == :gt, do: :ok, else: {:error, :expired}
  end

  defp active(_, _), do: {:error, :inactive}

  defp same_subscription?(claimed, current) do
    Enum.all?([:id, :owner_id, :name, :arguments, :url], fn key ->
      Map.has_key?(claimed, key) and Map.has_key?(current, key) and
        Map.get(claimed, key) == Map.get(current, key)
    end)
  end

  defp outcome(:ok, delivery, _max), do: {:delivered, delivery.event["cursor"]}
  defp outcome({:stop, reason}, _delivery, _max), do: {:stop, reason}

  defp outcome({:retry, _reason}, %{attempt: attempt}, max) when attempt >= max,
    do: {:stop, :attempts_exhausted}

  defp outcome({:retry, reason}, delivery, _max) do
    delay_seconds = min(3600, Integer.pow(2, min(delivery.attempt - 1, 12)))
    {:retry, reason, DateTime.add(DateTime.utc_now(), delay_seconds, :second)}
  end
end
