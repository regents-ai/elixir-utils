defmodule RegentBlogTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  test "a post keeps its Markdown body beside the HTML", %{tmp_dir: dir} do
    path = Path.join(dir, "first-post.md")

    File.write!(path, """
    ---
    title: First post
    date: 2026-09-28
    author: Regent
    author_x: https://x.com/regent
    image: /images/blog/first.png
    image_alt: A first picture
    ---

    ## Hello

    Some *words*.
    """)

    post = RegentBlog.read!(path)

    assert post.markdown == "## Hello\n\nSome *words*."
    assert post.html =~ "<em>words</em>"
  end
end
