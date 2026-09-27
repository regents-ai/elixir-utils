defmodule RegentERC8004.Components do
  @moduledoc """
  Stateless ERC-8004 evidence components. Import this module in an Ash/Phoenix UI.
  Load/project evidence in the owning action, never in render. Uses Regent.Structure
  panels and the host's shared tokens. No JavaScript, automatic reads or wallet actions.
  """
  use Phoenix.Component
  alias RegentERC8004.Ref

  attr(:snapshot, :map, required: true)
  attr(:rest, :global)
  slot(:feedback_more)
  slot(:validation_more)

  def profile(assigns) do
    ~H"""
    <div class="erc8004 erc8004-profile" {@rest}>
      <p class="erc8004-note">
        Indexed evidence, not independent verification. Registration metadata is agent-supplied.
      </p>
      <.agent_card agent={@snapshot.agent} />
      <.endpoints services={@snapshot.agent.services} />
      <.reputation summary={@snapshot.reputation} />
      <.feedback_list page={@snapshot.feedback}>
        <:more>{render_slot(@feedback_more)}</:more>
      </.feedback_list>
      <.validations summary={@snapshot.validation} page={@snapshot.validations}>
        <:more>{render_slot(@validation_more)}</:more>
      </.validations>
      <.activity events={@snapshot.activity} />
    </div>
    """
  end

  attr(:agent, :map, required: true)

  attr(:rest, :global)
  slot(:actions)

  def agent_card(assigns) do
    ~H"""
    <Regent.Structure.panel class="erc8004 erc8004-section" {@rest}>
      <header class="erc8004-identity">
        <.fingerprint ref={@agent.ref} />
        <div>
          <h2>{@agent.name || "Agent #{@agent.ref.agent_id}"}</h2>
          <p class="erc8004-note">ERC-8004 registration · chain {@agent.ref.chain_id}</p>
        </div>
      </header>
      <p :if={@agent.description} class="erc8004-prose">{@agent.description}</p>
      <details>
        <summary>Full identity and owner</summary>
        <dl class="erc8004-identifiers">
          <dt>Registry</dt><dd><code>{@agent.ref.registry}</code></dd>
          <dt>Agent ID</dt><dd><code>{@agent.ref.agent_id}</code></dd>
          <dt>Indexed owner</dt><dd><code>{@agent.owner}</code></dd>
        </dl>
      </details>
      <p :if={@agent.last_activity} class="erc8004-note">
        Last indexed activity: <.timestamp at={@agent.last_activity} />
      </p>
      <div :if={@actions != []} class="erc8004-actions">{render_slot(@actions)}</div>
    </Regent.Structure.panel>
    """
  end

  attr(:ref, Ref, required: true)

  def fingerprint(assigns) do
    digest =
      :crypto.hash(
        :sha256,
        assigns.ref.registry <> "/" <> Integer.to_string(assigns.ref.agent_id)
      )

    cells = for y <- 0..4, x <- 0..4, :binary.at(digest, y * 3 + min(x, 4 - x)) >= 128, do: {x, y}
    assigns = assign(assigns, :cells, cells)

    ~H"""
    <svg class="erc8004-fingerprint" viewBox="-1 -1 7 7" aria-hidden="true" focusable="false">
      <rect :for={{x, y} <- @cells} x={x} y={y} width="1" height="1" fill="currentColor" />
    </svg>
    """
  end

  attr(:services, :list, required: true)

  def endpoints(assigns) do
    ~H"""
    <Regent.Structure.panel class="erc8004 erc8004-section">
      <h3>Declared endpoints</h3>
      <p class="erc8004-note">Not health checked. Only HTTPS destinations are clickable.</p>
      <p :if={@services == []}>No endpoints declared.</p>
      <ul class="erc8004-list" role="list">
        <li :for={service <- @services}>
          <strong>{service.protocol}</strong>
          <a
            :if={safe_url(service.url)}
            class="erc8004-endpoint"
            href={safe_url(service.url)}
            rel="nofollow noreferrer noopener"
          >{service.url}</a>
          <span :if={!safe_url(service.url)} class="erc8004-endpoint">{service.url}</span>
        </li>
      </ul>
    </Regent.Structure.panel>
    """
  end

  attr(:summary, :map, required: true)

  def reputation(assigns) do
    ~H"""
    <Regent.Structure.panel class="erc8004 erc8004-section">
      <h3>Reputation</h3>
      <p :if={@summary.status == :unavailable}>Reputation aggregate unavailable.</p>
      <p :if={@summary.status == :empty}>No non-revoked feedback in this aggregate.</p>
      <p :if={@summary.status == :ready}>
        <strong class="erc8004-score">{number(@summary.average)}</strong>
        mean · {@summary.count} non-revoked reviews
      </p>
      <p class="erc8004-note">
        Feedback values have no universal scale. This is not a percentage or a trust rating.
      </p>
    </Regent.Structure.panel>
    """
  end

  attr(:page, :map, required: true)
  slot(:more)

  def feedback_list(assigns) do
    ~H"""
    <Regent.Structure.panel class="erc8004 erc8004-section">
      <h3>Feedback</h3>
      <p :if={@page.entries == []}>No feedback in this page.</p>
      <ol class="erc8004-list" role="list">
        <li :for={entry <- @page.entries}>
          <p><strong>{number(entry.value)}</strong> · <.timestamp at={entry.at} /></p>
          <p :if={entry.text} class="erc8004-prose">{entry.text}</p>
          <ul :if={entry.tags != []} class="erc8004-tags" role="list" aria-label="Feedback tags">
            <li :for={tag <- entry.tags}>{tag}</li>
          </ul>
          <details>
            <summary>Reviewer and feedback ID</summary><p><code>{entry.reviewer}</code></p><p>
              <code>{entry.id}</code>
            </p>
          </details>
        </li>
      </ol>
      <.continuation page={@page}>{render_slot(@more)}</.continuation>
    </Regent.Structure.panel>
    """
  end

  attr(:summary, :map, required: true)
  attr(:page, :map, required: true)
  slot(:more)

  def validations(assigns) do
    ~H"""
    <Regent.Structure.panel class="erc8004 erc8004-section">
      <h3>Validation evidence</h3>
      <p :if={@summary.status == :unavailable}>Validation aggregate unavailable.</p>
      <p :if={@summary.status == :empty}>No validation responses in this aggregate.</p>
      <p :if={@summary.status == :ready}>
        <strong>{number(@summary.average)} / 100</strong> mean · {@summary.count} indexed responses
      </p>
      <p class="erc8004-note">
        A validator's response is evidence, not a library-issued verification badge.
      </p>
      <p :if={@page.entries == []}>No validations in this page.</p>
      <ol class="erc8004-list" role="list">
        <li :for={entry <- @page.entries}>
          <p>
            <strong>{entry.status}</strong><span :if={!is_nil(entry.score)}> · {entry.score} / 100</span>
            · <.timestamp at={entry.at} />
          </p>
          <p :if={entry.tag}>{entry.tag}</p>
          <details>
            <summary>Validator and validation ID</summary><p><code>{entry.validator}</code></p><p>
              <code>{entry.id}</code>
            </p>
          </details>
        </li>
      </ol>
      <.continuation page={@page}>{render_slot(@more)}</.continuation>
    </Regent.Structure.panel>
    """
  end

  attr(:events, :list, required: true)

  def activity(assigns) do
    ~H"""
    <Regent.Structure.panel class="erc8004 erc8004-section">
      <h3>Activity in loaded pages</h3>
      <p class="erc8004-note">Feedback and validation only; not a complete on-chain event history.</p>
      <p :if={@events == []}>No activity in these pages.</p>
      <ol class="erc8004-list" role="list">
        <li :for={event <- @events}>
          <p>
            {event.kind}<span :if={!is_nil(event.value)}> · {number(event.value)}</span>
            · <.timestamp at={event.at} />
          </p>
          <details>
            <summary>Full actor address</summary><code>{event.actor}</code>
          </details>
        </li>
      </ol>
    </Regent.Structure.panel>
    """
  end

  attr(:status, :atom, required: true, values: [:loading, :error, :empty, :not_found])
  slot(:retry)

  def state(assigns) do
    ~H"""
    <Regent.Structure.panel class="erc8004 erc8004-section" aria-busy={@status == :loading}>
      <p role={if @status == :error, do: "alert", else: "status"}>{state_label(@status)}</p>
      <div :if={@status == :error && @retry != []} class="erc8004-actions">{render_slot(@retry)}</div>
    </Regent.Structure.panel>
    """
  end

  attr(:page, :map, required: true)
  slot(:inner_block)

  defp continuation(assigns) do
    ~H"""
    <footer :if={@page.has_more} class="erc8004-actions">
      <p :if={!@page.limit_reached}>More indexed entries are available.</p>
      <p :if={@page.limit_reached}>More entries exist beyond this reader's pagination limit.</p>
      {render_slot(@inner_block)}
    </footer>
    """
  end

  attr(:at, DateTime, required: true)

  defp timestamp(assigns) do
    ~H"""
    <time datetime={DateTime.to_iso8601(@at)}>{Calendar.strftime(@at, "%Y-%m-%d %H:%M UTC")}</time>
    """
  end

  defp number(nil), do: "—"
  defp number(%Decimal{} = value), do: Decimal.to_string(value, :normal)
  defp number(value) when is_integer(value), do: Integer.to_string(value)
  defp state_label(:loading), do: "Loading indexed agent evidence…"
  defp state_label(:error), do: "Agent evidence could not be loaded. Try again."
  defp state_label(:empty), do: "No agent evidence supplied."
  defp state_label(:not_found), do: "Agent not found in this indexer."

  defp safe_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host, userinfo: nil} when is_binary(host) and host != "" ->
        if not String.match?(url, ~r/[\s\x00-\x1f\x7f]/), do: url

      _ ->
        nil
    end
  end

  defp safe_url(_), do: nil
end
