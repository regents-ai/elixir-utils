defmodule CredoAsh.Check.Warning.ActorOnExecution do
  use Credo.Check,
    id: "CRA1005",
    base_priority: :normal,
    category: :warning,
    tags: [:credo_ash, :security],
    explanations: [
      check: """
      The actor belongs on the query or changeset while it is being prepared,
      not on the call that runs it. Changes, validations and preparations run
      during `for_read/3` and `for_action/4`; an actor supplied only at
      execution time is invisible to all of them.

          # bad — preparations ran without an actor
          Post
          |> Ash.Query.for_read(:feed, %{})
          |> Ash.read!(actor: actor)

          # good
          Post
          |> Ash.Query.for_read(:feed, %{}, actor: actor)
          |> Ash.read!()

      Only the two-argument form is reported, where the first argument is a
      query or changeset that was already built. When a resource module or a
      record is passed with params — `Ash.create!(Post, params, actor: actor)`,
      `Ash.update!(post, params, actor: actor)` — Ash builds the changeset from
      those same options, so the actor is present the whole time and there is
      nothing to fix.
      """
    ]

  @calls [
    :read,
    :read!,
    :read_one,
    :read_one!,
    :one,
    :one!,
    :get,
    :get!,
    :first,
    :first!,
    :create,
    :create!,
    :update,
    :update!,
    :destroy,
    :destroy!,
    :count,
    :count!,
    :exists?
  ]

  @builders [
    :for_read,
    :for_create,
    :for_update,
    :for_destroy,
    :for_action,
    :new
  ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  # In a pipe the subject is the left-hand side, not one of the call's arguments.
  defp traverse(
         {:|>, _, [subject, {{:., _, [{:__aliases__, _, [:Ash]}, fun]}, meta, args}]} = ast,
         issues,
         issue_meta
       )
       when fun in @calls do
    if late_actor?([subject | args]) do
      {ast, issues ++ [issue_for(issue_meta, meta[:line], fun)]}
    else
      {ast, issues}
    end
  end

  defp traverse({{:., _, [{:__aliases__, _, [:Ash]}, fun]}, meta, args} = ast, issues, issue_meta)
       when fun in @calls do
    if late_actor?(args) do
      {ast, issues ++ [issue_for(issue_meta, meta[:line], fun)]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  # Only `Ash.fun(query_or_changeset, opts)`. Anything with params in between
  # hands Ash the actor before it builds the changeset, and a bare resource
  # module does the same for a query.
  defp late_actor?([{:__aliases__, _, _}, _opts]), do: false

  defp late_actor?([subject, opts]) when is_list(opts) do
    Keyword.has_key?(opts, :actor) and not prepared_with_actor?(subject)
  end

  defp late_actor?(_), do: false

  # If anything upstream in the pipeline already handed the actor to a
  # `for_*` builder, preparations saw it and a second actor at execution is
  # redundant rather than wrong.
  defp prepared_with_actor?(subject) do
    {_ast, prepared?} =
      Macro.prewalk(subject, false, fn
        {{:., _, [_module, fun]}, _, args} = node, acc when fun in @builders ->
          {node, acc or Enum.any?(args, &(is_list(&1) and Keyword.has_key?(&1, :actor)))}

        node, acc ->
          {node, acc}
      end)

    prepared?
  end

  defp issue_for(issue_meta, line_no, fun) do
    format_issue(issue_meta,
      message:
        "`actor:` is passed to `Ash.#{fun}` at execution — move it to the " <>
          "`for_read/3` or `for_action/4` call so preparations and changes can see it.",
      trigger: "actor",
      line_no: line_no
    )
  end
end
