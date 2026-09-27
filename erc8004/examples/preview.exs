# Run with: mix run --no-start examples/preview.exs
# Actual HEEx render, synthetic evidence, static navigation; no app/Repo/provider startup.
Code.require_file("data.exs", __DIR__)

defmodule RegentERC8004.Preview do
  use Phoenix.Component
  import RegentERC8004.Components

  def page(assigns) do
    assigns =
      assign(
        assigns,
        :palettes,
        for(
          brand <- ~w(platform techtree autolaunch patchbay),
          theme <- ~w(light dark),
          do: {brand, theme}
        )
      )

    ~H"""
    <main>
      <h1>ERC-8004 · Phoenix components</h1>
      <p>Synthetic examples. No wallet, API key, application database or browser JavaScript.</p>
      <nav aria-label="Palette examples">
        <a :for={{brand, theme} <- @palettes} href={"#{brand}-#{theme}-0.html"}>{brand} {theme}</a>
      </nav>
      <p><a href={"#{@brand}-#{@theme}-0.html"}>First example page</a></p>
      <.profile snapshot={@snapshot}>
        <:feedback_more>
          <a :if={@snapshot.feedback.next_offset} class="rg-button rg-button--secondary" href={@next}>Next example page</a>
        </:feedback_more>
        <:validation_more>
          <a
            :if={@snapshot.validations.next_offset}
            class="rg-button rg-button--secondary"
            href={@next}
          >Next example page</a>
        </:validation_more>
      </.profile>
      <h2>States</h2>
      <.state :for={status <- [:loading, :error, :empty, :not_found]} status={status} />
    </main>
    """
  end
end

out = Path.expand("preview")
File.mkdir_p!(out)
ui = Mix.Project.deps_paths()[:regent_ui]
File.cp!(Path.join(Path.dirname(ui), "design_system_tokens.css"), Path.join(out, "tokens.css"))

for name <- ~w(primitives structure ratio theme_toggle),
    do: File.cp!(Path.join(ui, "assets/css/#{name}.css"), Path.join(out, "#{name}.css"))

File.cp!("priv/static/erc8004.css", Path.join(out, "erc8004.css"))
File.mkdir_p!(Path.join(out, "fonts"))
File.cp_r!(Path.join(ui, "priv/static/fonts"), Path.join(out, "fonts/regent-ui"))
{:ok, ref} = RegentERC8004.Ref.new(RegentERC8004.ExampleData.registry(), "7")

files =
  for brand <- ~w(platform techtree autolaunch patchbay),
      theme <- ~w(light dark),
      offset <- [0, 2] do
    raw =
      RegentERC8004.ExampleData.data()
      |> Map.update!("feedbacks", &Enum.drop(&1, offset))
      |> Map.update!("validations", &Enum.drop(&1, offset))

    {:ok, snapshot} =
      RegentERC8004.Snapshot.from_graphql(ref, raw,
        limit: 2,
        feedback_offset: offset,
        validation_offset: offset
      )

    body =
      RegentERC8004.Preview.page(%{
        __changed__: nil,
        snapshot: snapshot,
        brand: brand,
        theme: theme,
        next: "#{brand}-#{theme}-2.html"
      })
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    html = """
    <!doctype html><html lang="en" data-brand="#{brand}" data-theme="#{theme}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>ERC-8004 synthetic component preview</title>
    <link rel="stylesheet" href="tokens.css"><link rel="stylesheet" href="primitives.css"><link rel="stylesheet" href="structure.css"><link rel="stylesheet" href="erc8004.css">
    <style>body{margin:0;padding:1rem;background:var(--color-bg);color:var(--color-fg);font-family:var(--font-family-ui)}main{max-width:52rem;margin-inline:auto}h1,h2{font-family:var(--font-family-title);font-weight:400}nav{display:flex;flex-wrap:wrap;gap:.5rem}nav a{display:block;min-height:44px;padding:.5rem;box-sizing:border-box;color:inherit}main>p>a{color:inherit}</style>
    </head><body>#{body}</body></html>
    """

    file = Path.join(out, "#{brand}-#{theme}-#{offset}.html")
    File.write!(file, html)
    file
  end

File.cp!(Path.join(out, "platform-dark-0.html"), Path.join(out, "index.html"))
IO.puts("Rendered #{length(files)} actual-component palette/page examples to #{out}")
