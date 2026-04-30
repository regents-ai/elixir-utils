defmodule SiwaKeyring.Application do
  use Application

  @impl true
  def start(_type, _args) do
    config = runtime_config!()

    children =
      [{SiwaKeyring.ReplayStore, name: SiwaKeyring.ReplayStore}]
      |> maybe_add_server(config)

    Supervisor.start_link(children, strategy: :one_for_one, name: SiwaKeyring.Supervisor)
  end

  defp maybe_add_server(children, %{start_server: true} = config) do
    children ++
      [{Bandit, plug: SiwaKeyring.Router, scheme: :http, port: config.port, ip: config.host}]
  end

  defp maybe_add_server(children, %{start_server: false}), do: children

  def runtime_config! do
    %{
      secret: fetch_non_empty_binary!(:secret),
      password: fetch_non_empty_binary!(:password),
      path: fetch_non_empty_binary!(:path),
      port: fetch_port!(),
      start_server: fetch_boolean!(:start_server),
      host: fetch_host!()
    }
  end

  defp fetch_non_empty_binary!(key) do
    case Application.fetch_env!(:siwa_keyring, key) do
      value when is_binary(value) and value != "" ->
        value

      _value ->
        raise ArgumentError, "siwa_keyring #{inspect(key)} must be a non-empty string"
    end
  end

  defp fetch_port! do
    case Application.fetch_env!(:siwa_keyring, :port) do
      port when is_integer(port) and port in 1..65_535 ->
        port

      _value ->
        raise ArgumentError, "siwa_keyring :port must be an integer from 1 to 65535"
    end
  end

  defp fetch_boolean!(key) do
    case Application.fetch_env!(:siwa_keyring, key) do
      value when is_boolean(value) ->
        value

      _value ->
        raise ArgumentError, "siwa_keyring #{inspect(key)} must be true or false"
    end
  end

  defp fetch_host! do
    host = fetch_non_empty_binary!(:host)

    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, address} ->
        address

      {:error, _reason} ->
        raise ArgumentError, "siwa_keyring :host must be a valid IP address"
    end
  end
end
