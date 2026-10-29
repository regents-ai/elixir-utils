defmodule RegentPrivy.OwnersTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Phoenix.LiveView.{Lifecycle, Socket}
  alias RegentPrivy.Owners

  @owner "did:privy:owner"

  # An app's sign-in: the session names the Privy id, and the sign-in still holds
  # while this test process says so.
  defmodule SignIn do
    @behaviour RegentPrivy.Owners

    @impl true
    def owners, do: ["did:privy:owner"]

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
  # the page was first rendered with.
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

  describe "as a plug" do
    test "an owner's request goes on" do
      conn = call(%{"privy" => @owner})
      refute conn.halted
    end

    test "anyone else gets the app's not-found page" do
      assert_raise Phoenix.Router.NoRouteError, fn -> call(%{}) end

      log =
        capture_log(fn ->
          assert_raise Phoenix.Router.NoRouteError, fn ->
            call(%{"privy" => "did:privy:other"})
          end
        end)

      assert log =~ "Privy account did:privy:other is not an owner"
    end
  end

  describe "as an on_mount hook" do
    test "an owner's page mounts, and keeps working while the sign-in holds" do
      assert {:cont, socket} = mount(%{"privy" => @owner})
      assert {:cont, ^socket} = press(socket)
      assert {:cont, ^socket} = navigate(socket)
      assert {:cont, ^socket} = receive_message(socket)
    end

    test "anyone else is sent home before the page mounts" do
      assert {:halt, %Socket{redirected: {:redirect, %{to: "/"}}}} = mount(%{})

      assert {:halt, %Socket{redirected: {:redirect, %{to: "/"}}}} =
               mount(%{"privy" => "did:privy:other"})
    end

    test "a connected page goes by the session its socket carried" do
      assert {:cont, _socket} = connect(%{"privy" => @owner}, %{})

      assert {:halt, %Socket{redirected: {:redirect, %{to: "/"}}}} =
               connect(%{}, %{"privy" => @owner})
    end

    test "a sign-in that ends stops the next press, navigation and message" do
      {:cont, socket} = mount(%{"privy" => @owner})
      Process.put({:signed_in, @owner}, :signed_out)

      assert {:halt, %Socket{redirected: {:redirect, %{to: "/"}}}} = press(socket)
      assert {:halt, %Socket{redirected: {:redirect, %{to: "/"}}}} = navigate(socket)
      assert {:halt, %Socket{redirected: {:redirect, %{to: "/"}}}} = receive_message(socket)
    end

    test "a sign-in that now names another account stops the page" do
      {:cont, socket} = mount(%{"privy" => @owner})
      Process.put({:signed_in, @owner}, {:ok, "did:privy:other"})

      assert {:halt, _socket} = press(socket)
    end
  end
end
