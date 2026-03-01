defmodule Jido.Document.PropertyDocumentRoundtripTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Jido.Document.Document

  property "parse/serialize roundtrip keeps frontmatter keys and body content" do
    check all(
            title <- StreamData.string(:alphanumeric, min_length: 1, max_length: 32),
            lines <-
              StreamData.list_of(StreamData.string(:alphanumeric, max_length: 24), max_length: 8)
          ) do
      body = Enum.join(lines, "\n")

      raw = """
      ---
      title: "#{title}"
      ---
      #{body}
      """

      assert {:ok, doc} = Document.parse(raw)
      assert {:ok, serialized} = Document.serialize(doc)
      assert {:ok, reparsed} = Document.parse(serialized)

      assert reparsed.frontmatter["title"] == title
      assert reparsed.body == doc.body
    end
  end
end
