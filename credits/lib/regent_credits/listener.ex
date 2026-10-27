defmodule RegentCredits.Listener do
  @moduledoc """
  Hears Credits balance changes from every Regent site through the shared
  database and passes each one to this site's PubSub, as `:credits_changed`
  on `RegentCredits.topic/1`. It listens on the site's own
  `Postgrex.Notifications` connection, named in the `:notifications` setting,
  which the site opens on the database's direct address and shares with every
  listener. The site starts it after that connection and its PubSub, under a
  `:rest_for_one` supervisor, so a new connection brings a new listener.
  """

  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    notifications = Application.fetch_env!(:regent_credits, :notifications)

    # Listening starts now, or as soon as the connection is up.
    {_now_or_on_connect, _ref} =
      Postgrex.Notifications.listen(notifications, RegentCredits.channel())

    {:ok, Application.fetch_env!(:regent_credits, :pubsub)}
  end

  @impl true
  def handle_info({:notification, _notifications, _ref, _channel, privy_user_id}, pubsub) do
    Phoenix.PubSub.broadcast(pubsub, RegentCredits.topic(privy_user_id), :credits_changed)
    {:noreply, pubsub}
  end
end
