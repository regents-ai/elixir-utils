defmodule RegentOAuth.Test.Return do
  @moduledoc """
  The address the page answering Allow or Cancel takes the browser to: its
  refresh and its Continue link name the same one.
  """
  import ExUnit.Assertions

  @entities %{"&amp;" => "&", "&lt;" => "<", "&gt;" => ">", "&quot;" => "\"", "&#39;" => "'"}

  def address(conn) do
    assert [_, refresh] =
             Regex.run(~r/<meta http-equiv="refresh" content="0;url=([^"]*)">/, conn.resp_body)

    assert [_, continue] = Regex.run(~r/<a href="([^"]*)">Continue<\/a>/, conn.resp_body)
    assert refresh == continue
    String.replace(refresh, Map.keys(@entities), &Map.fetch!(@entities, &1))
  end
end
