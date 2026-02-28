defmodule Jido.Document.DocumentParseSerializeIntegrationTest do
  use ExUnit.Case, async: true

  alias Jido.Document.Document

  test "parses YAML frontmatter and body" do
    raw = "---\ntitle: \"Hello\"\ncount: 3\n---\n# Body\n"

    assert {:ok, doc} = Document.parse(raw)
    assert doc.frontmatter == %{"count" => 3, "title" => "Hello"}
    assert doc.body == "# Body\n"
    assert doc.raw == raw
  end

  test "parses TOML frontmatter and body" do
    raw = "+++\ntitle = \"Hello\"\ncount = 3\n+++\n# Body\n"

    assert {:ok, doc} = Document.parse(raw)
    assert doc.frontmatter == %{"count" => 3, "title" => "Hello"}
    assert doc.body == "# Body\n"
  end

  test "parses document without frontmatter" do
    raw = "# Plain markdown\n\nNo metadata.\n"

    assert {:ok, doc} = Document.parse(raw)
    assert doc.frontmatter == %{}
    assert doc.body == raw
  end

  test "returns structured error for missing closing delimiter" do
    raw = "---\ntitle: test\n# body without closing delimiter\n"

    assert {:error, [error]} = Document.parse(raw)
    assert error.path == [:frontmatter]
    assert error.message =~ "missing closing"
    assert error.value[:line] == 1
  end

  test "roundtrips parse and serialize deterministically" do
    raw = "---\nzeta: 9\nalpha: \"first\"\n---\nLine 1\nLine 2\n"

    assert {:ok, doc} = Document.parse(raw)
    assert {:ok, serialized_once} = Document.serialize(doc, syntax: :yaml)
    assert {:ok, reparsed} = Document.parse(serialized_once)
    assert {:ok, serialized_twice} = Document.serialize(reparsed, syntax: :yaml)

    assert serialized_once == serialized_twice
    assert reparsed.frontmatter == doc.frontmatter
    assert reparsed.body == doc.body
  end
end
