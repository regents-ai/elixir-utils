defmodule CredoAsh.QueryAndActorTest do
  use Credo.Test.Case

  alias CredoAsh.Check.Design.WildcardAccept
  alias CredoAsh.Check.Warning.ActorOnExecution
  alias CredoAsh.Check.Warning.AshCallInLoop
  alias CredoAsh.Check.Warning.DirectRepoCall
  alias CredoAsh.Check.Warning.UnjustifiedAuthorizeFalse

  defp module(body) do
    """
    defmodule MyApp.Blog do
    #{body}
    end
    """
    |> to_source_file()
  end

  describe "AshCallInLoop" do
    test "reports a load inside Enum.map" do
      """
        def feed(users) do
          Enum.map(users, &Ash.load!(&1, :posts))
        end
      """
      |> module()
      |> run_check(AshCallInLoop)
      |> assert_issue()
    end

    test "reports a write inside Enum.each with a multi-line body" do
      """
        def expire(rows) do
          Enum.each(rows, fn row ->
            Ash.update!(row, %{}, action: :mark_stale)
          end)
        end
      """
      |> module()
      |> run_check(AshCallInLoop)
      |> assert_issue()
    end

    test "reports a read inside a for comprehension" do
      """
        def counts(ids) do
          for id <- ids, do: Ash.get!(MyApp.Blog.Post, id)
        end
      """
      |> module()
      |> run_check(AshCallInLoop)
      |> assert_issue()
    end

    test "accepts a single call over the whole collection" do
      """
        def feed(users) do
          Ash.load!(users, :posts)
        end
      """
      |> module()
      |> run_check(AshCallInLoop)
      |> refute_issues()
    end

    test "accepts plain data mapping" do
      """
        def titles(posts) do
          Enum.map(posts, & &1.title)
        end
      """
      |> module()
      |> run_check(AshCallInLoop)
      |> refute_issues()
    end

    test "reports one issue per loop, not one per nested call" do
      """
        def sync(rows) do
          Enum.each(rows, fn row ->
            Ash.update!(row, %{}, action: :a)
            Ash.update!(row, %{}, action: :b)
          end)
        end
      """
      |> module()
      |> run_check(AshCallInLoop)
      |> assert_issue()
    end
  end

  describe "ActorOnExecution" do
    test "reports an actor passed at execution" do
      """
        def feed(actor) do
          MyApp.Blog.Post
          |> Ash.Query.for_read(:feed, %{})
          |> Ash.read!(actor: actor)
        end
      """
      |> module()
      |> run_check(ActorOnExecution)
      |> assert_issue()
    end

    test "accepts a resource module built with the actor in the same call" do
      """
        def create(actor, params) do
          Ash.create!(MyApp.Blog.Post, params, action: :publish, actor: actor)
        end
      """
      |> module()
      |> run_check(ActorOnExecution)
      |> refute_issues()
    end

    test "accepts a record updated with params and the actor in the same call" do
      """
        def retire(post, actor) do
          Ash.update!(post, %{}, action: :retire, actor: actor)
        end
      """
      |> module()
      |> run_check(ActorOnExecution)
      |> refute_issues()
    end

    test "accepts a bare resource read with the actor" do
      """
        def all(actor) do
          Ash.read!(MyApp.Blog.Post, actor: actor)
        end
      """
      |> module()
      |> run_check(ActorOnExecution)
      |> refute_issues()
    end

    test "reports a changeset created after for_create" do
      """
        def publish(params, actor) do
          MyApp.Blog.Post
          |> Ash.Changeset.for_create(:publish, params)
          |> Ash.create!(actor: actor)
        end
      """
      |> module()
      |> run_check(ActorOnExecution)
      |> assert_issue()
    end

    test "accepts a redundant actor when preparation already had one" do
      """
        def publish(params, actor) do
          MyApp.Blog.Post
          |> Ash.Changeset.for_create(:publish, params, actor: actor)
          |> Ash.create!(actor: actor)
        end
      """
      |> module()
      |> run_check(ActorOnExecution)
      |> refute_issues()
    end

    test "accepts an actor given to for_read earlier in the pipeline" do
      """
        def feed(actor) do
          MyApp.Blog.Post
          |> Ash.Query.for_read(:feed, %{}, actor: actor)
          |> Ash.Query.lock(:for_update)
          |> Ash.read_one!(actor: actor)
        end
      """
      |> module()
      |> run_check(ActorOnExecution)
      |> refute_issues()
    end

    test "reports a query built with no actor at all" do
      """
        def feed(actor) do
          MyApp.Blog.Post
          |> Ash.Query.for_read(:feed, %{}, domain: MyApp.Blog)
          |> Ash.read_one!(actor: actor)
        end
      """
      |> module()
      |> run_check(ActorOnExecution)
      |> assert_issue()
    end

    test "accepts an actor passed during preparation" do
      """
        def feed(actor) do
          MyApp.Blog.Post
          |> Ash.Query.for_read(:feed, %{}, actor: actor)
          |> Ash.read!()
        end
      """
      |> module()
      |> run_check(ActorOnExecution)
      |> refute_issues()
    end
  end

  describe "DirectRepoCall" do
    test "reports a bulk insert that skips Ash" do
      """
        def seed(rows) do
          MyApp.Repo.insert_all(MyApp.Blog.Post, rows)
        end
      """
      |> module()
      |> run_check(DirectRepoCall)
      |> assert_issue()
    end

    test "accepts raw SQL" do
      """
        def lock(id) do
          MyApp.Repo.query("SELECT pg_advisory_xact_lock($1)", [id])
        end
      """
      |> module()
      |> run_check(DirectRepoCall)
      |> refute_issues()
    end
  end

  describe "UnjustifiedAuthorizeFalse" do
    test "reports a bare escape hatch" do
      """
        def all do
          Ash.read!(MyApp.Blog.Post, authorize?: false)
        end
      """
      |> module()
      |> run_check(UnjustifiedAuthorizeFalse)
      |> assert_issue()
    end

    test "accepts one with a comment above it" do
      """
        def all do
          # Indexer job, no actor exists; rows are public chain data.
          Ash.read!(MyApp.Blog.Post, authorize?: false)
        end
      """
      |> module()
      |> run_check(UnjustifiedAuthorizeFalse)
      |> refute_issues()
    end

    test "accepts one with a trailing comment" do
      """
        def all do
          Ash.read!(MyApp.Blog.Post, authorize?: false) # seed script only
        end
      """
      |> module()
      |> run_check(UnjustifiedAuthorizeFalse)
      |> refute_issues()
    end
  end

  describe "WildcardAccept" do
    test "reports accept :*" do
      """
        def dummy, do: :ok

        create :sign_up do
          accept :*
        end
      """
      |> module()
      |> run_check(WildcardAccept)
      |> assert_issue()
    end

    test "accepts a named attribute list" do
      """
        create :sign_up do
          accept [:email, :display_name]
        end
      """
      |> module()
      |> run_check(WildcardAccept)
      |> refute_issues()
    end
  end
end
