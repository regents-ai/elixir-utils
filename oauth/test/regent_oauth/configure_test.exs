defmodule RegentOAuth.ConfigureTest do
  # The provider's rows go through the site's repository, which must put the
  # site's schema on every query; without one they would land in `public` of
  # the shared database.
  use ExUnit.Case, async: true

  alias RegentOAuth.Test.Site

  defmodule SchemalessRepo do
    @moduledoc "A repository that puts no schema on its queries."
    def default_options(_operation), do: []
  end

  defmodule SchemalessSite do
    @moduledoc "The test site with that repository."
    @behaviour RegentOAuth

    @impl true
    defdelegate config, to: Site
    @impl true
    def repo, do: SchemalessRepo
    @impl true
    defdelegate current_subject(conn), to: Site
    @impl true
    defdelegate active_subject?(subject), to: Site
  end

  test "a site whose repository puts no schema on its queries is refused" do
    assert_raise ArgumentError, ~r/schema on every query/, fn ->
      RegentOAuth.configure(SchemalessSite)
    end

    assert Application.fetch_env!(:regent_oauth, :site) == Site
  end
end
