defmodule CredoAsh.PolicyCoverageTest do
  use Credo.Test.Case

  alias CredoAsh.Check.Warning.AuthorizerWithoutPolicies
  alias CredoAsh.Check.Warning.PoliciesWithoutAuthorizer
  alias CredoAsh.Check.Warning.UnprotectedResource

  defp resource(use_opts, body \\ "") do
    """
    defmodule MyApp.Blog.Post do
      use Ash.Resource#{use_opts}

      attributes do
        uuid_primary_key :id
      end
    #{body}
    end
    """
    |> to_source_file()
  end

  @authorized ",\n    domain: MyApp.Blog,\n    data_layer: AshPostgres.DataLayer,\n    authorizers: [Ash.Policy.Authorizer]"
  @unauthorized ",\n    domain: MyApp.Blog,\n    data_layer: AshPostgres.DataLayer"
  @embedded ",\n    data_layer: :embedded"

  @policies """

    policies do
      policy action_type(:read) do
        authorize_if always()
      end
    end
  """

  describe "PoliciesWithoutAuthorizer" do
    test "accepts a resource that has both" do
      @policies
      |> then(&resource(@authorized, &1))
      |> run_check(PoliciesWithoutAuthorizer)
      |> refute_issues()
    end

    test "reports policies with no authorizer" do
      [issue] =
        @policies
        |> then(&resource(@unauthorized, &1))
        |> run_check(PoliciesWithoutAuthorizer)
        |> assert_issue()
        |> List.wrap()

      assert issue.message =~ "policies are ignored"
    end

    test "does not attribute a nested module's policies to its parent" do
      """
      defmodule MyApp.Blog.Post do
        use Ash.Resource, domain: MyApp.Blog, data_layer: AshPostgres.DataLayer

        defmodule Preparations.Recent do
          use Ash.Resource.Preparation

          def prepare(query, _, _), do: query
        end
      end
      """
      |> to_source_file()
      |> run_check(PoliciesWithoutAuthorizer)
      |> refute_issues()
    end
  end

  describe "AuthorizerWithoutPolicies" do
    test "accepts a resource that has both" do
      @policies
      |> then(&resource(@authorized, &1))
      |> run_check(AuthorizerWithoutPolicies)
      |> refute_issues()
    end

    test "reports an authorizer with no policies block" do
      @authorized
      |> resource()
      |> run_check(AuthorizerWithoutPolicies)
      |> assert_issue()
    end
  end

  describe "UnprotectedResource" do
    test "reports a persisted resource with neither" do
      @unauthorized
      |> resource()
      |> run_check(UnprotectedResource)
      |> assert_issue()
    end

    test "ignores embedded resources" do
      @embedded
      |> resource()
      |> run_check(UnprotectedResource)
      |> refute_issues()
    end

    test "ignores modules that only use Ash.Resource.Change" do
      """
      defmodule MyApp.Blog.Post.Changes.Slugify do
        use Ash.Resource.Change

        def change(changeset, _, _), do: changeset
      end
      """
      |> to_source_file()
      |> run_check(UnprotectedResource)
      |> refute_issues()
    end
  end
end
