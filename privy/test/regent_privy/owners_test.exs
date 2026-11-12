defmodule RegentPrivy.OwnersTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Phoenix.LiveView.{Lifecycle, Socket}
  alias RegentPrivy.Owners

  @owner "did:privy:owner"
  @second_owner "did:privy:second-owner"

  # An app's sign-in: the session names the Privy id, and the sign-in still holds
  # while this test process says so.
  defmodule SignIn do
    @behaviour RegentPrivy.Owners

    @impl true
    def owners, do: ["did:privy:owner", "did:privy:second-owner"]

    @impl true
    def signed_in(%{"privy" => id}), do: {:ok, id, id}
    def signed_in(_session), do: :signed_out

    @impl true
    def still_signed_in(id), do: Process.get({:signed_in, id}, {:ok, id})
  end

  defp request(session) do
    Plug.Test.conn(:get, "/owner") |> Plug.Test.init_test_session(session)
  end

  defp call(session),
    do: Owners.call(request(session), Owners.init(sign_in: SignIn, router: Router))

  defp mount(session) do
    Owners.on_mount(SignIn, %{}, session, %Socket{
      router: Router,
      private: %{lifecycle: %Lifecycle{}}
    })
  end

  # A connected page: the session the socket's handshake carried, beside the one
  # the page was first rendered with. A handshake whose forms token did not match
  # carries no session at all.
  defp connect(handshake, rendered) do
    Owners.on_mount(SignIn, %{}, rendered, %Socket{
      router: Router,
      transport_pid: self(),
      private: %{lifecycle: %Lifecycle{}, connect_info: %{session: handshake}}
    })
  end

  defp press(socket) do
    [%{function: hook}] = socket.private.lifecycle.handle_event
    hook.("press", %{}, socket)
  end

  defp receive_message(socket) do
    [%{function: hook}] = socket.private.lifecycle.handle_info
    hook.(:refresh, socket)
  end

  defp navigate(socket) do
    [%{function: hook}] = socket.private.lifecycle.handle_params
    hook.(%{}, "/owner", socket)
  end

  defp finish_background_work(socket) do
    [%{function: hook}] = socket.private.lifecycle.handle_async
    hook.(:load, {:ok, :loaded}, socket)
  end

  defp acts(socket) do
    [press(socket), navigate(socket), receive_message(socket), finish_background_work(socket)]
  end

  defp sent_home?({:halt, %Socket{redirected: {:redirect, %{to: "/"}}}}), do: true
  defp sent_home?(_result), do: false

  describe "as a plug" do
    test "an owner's request goes on, carrying the owner's Privy id" do
      conn = call(%{"privy" => @owner})

      refute conn.halted
      assert conn.assigns.owner_privy_user_id == @owner
    end

    test "anyone else gets the app's not-found page" do
      assert_raise Phoenix.Router.NoRouteError, fn -> call(%{}) end

      capture_log(fn ->
        assert_raise Phoenix.Router.NoRouteError, fn -> call(%{"privy" => "did:privy:other"}) end
      end)
    end

    test "a signed-in account that is not an owner is logged by its Privy id, once" do
      log =
        capture_log(fn ->
          assert_raise Phoenix.Router.NoRouteError, fn ->
            call(%{"privy" => "did:privy:other"})
          end
        end)

      assert length(String.split(log, "did:privy:other")) == 2
    end
  end

  describe "as an on_mount hook" do
    test "an owner's page mounts with the owner's Privy id, and keeps working while the sign-in holds" do
      assert {:cont, socket} = mount(%{"privy" => @owner})
      assert socket.assigns.owner_privy_user_id == @owner

      for result <- acts(socket), do: assert({:cont, ^socket} = result)
    end

    test "anyone else is sent home before the page mounts" do
      assert sent_home?(mount(%{}))
      assert sent_home?(mount(%{"privy" => "did:privy:other"}))
    end

    test "a connected page goes by the session its socket carried" do
      assert {:cont, socket} = connect(%{"privy" => @second_owner}, %{"privy" => @owner})
      assert socket.assigns.owner_privy_user_id == @second_owner

      assert sent_home?(connect(%{}, %{"privy" => @owner}))
      assert sent_home?(connect(nil, %{"privy" => @owner}))
    end

    test "a sign-in that ends stops the next navigation, press, message and background result" do
      {:cont, socket} = mount(%{"privy" => @owner})
      Process.put({:signed_in, @owner}, :signed_out)

      assert Enum.all?(acts(socket), &sent_home?/1)
    end

    test "a sign-in that now names another account, even another owner, stops the page" do
      {:cont, socket} = mount(%{"privy" => @owner})

      Process.put({:signed_in, @owner}, {:ok, "did:privy:other"})
      assert Enum.all?(acts(socket), &sent_home?/1)

      Process.put({:signed_in, @owner}, {:ok, @second_owner})
      assert Enum.all?(acts(socket), &sent_home?/1)
    end
  end
end
