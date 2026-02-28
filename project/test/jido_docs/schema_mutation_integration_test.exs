defmodule JidoDocs.SchemaMutationIntegrationTest do
  use ExUnit.Case, async: true

  alias JidoDocs.{Document, Field, Schema}

  defmodule BlogSchema do
    @behaviour Schema

    @impl true
    def fields do
      [
        %Field{name: :title, type: :string, required: true},
        %Field{name: :published, type: :boolean, default: false},
        %Field{name: :views, type: :integer, default: 0},
        %Field{name: :tags, type: {:array, :string}},
        %Field{name: :status, type: {:enum, ["draft", "published"]}, default: "draft"},
        %Field{
          name: :slug,
          type: :string,
          validator: fn value ->
            if String.contains?(value, " "), do: {:error, "must not contain spaces"}, else: :ok
          end
        }
      ]
    end
  end

  test "validates and coerces frontmatter values" do
    frontmatter = %{
      "title" => "Hello",
      "published" => "true",
      "views" => "42",
      "tags" => "elixir, docs",
      "slug" => "hello-world"
    }

    assert {:ok, normalized, warnings} = Schema.validate_frontmatter(frontmatter, BlogSchema)

    assert normalized == %{
             title: "Hello",
             published: true,
             views: 42,
             tags: ["elixir", "docs"],
             status: "draft",
             slug: "hello-world"
           }

    assert warnings == []
  end

  test "returns field-path errors for invalid schema values" do
    frontmatter = %{
      "title" => "Hello",
      "published" => "maybe",
      "status" => "unknown",
      "slug" => "bad slug"
    }

    assert {:error, errors} = Schema.validate_frontmatter(frontmatter, BlogSchema)

    paths = Enum.map(errors, & &1.path)

    assert [:frontmatter, :published] in paths
    assert [:frontmatter, :status] in paths
    assert [:frontmatter, :slug] in paths
  end

  test "supports unknown key policies" do
    frontmatter = %{"title" => "Hello", "slug" => "hello", "extra" => "value"}

    assert {:ok, _normalized, warnings} =
             Schema.validate_frontmatter(frontmatter, BlogSchema, unknown_keys: :warn)

    assert Enum.any?(warnings, fn warning -> warning.message =~ "unknown key" end)

    assert {:ok, _normalized, []} =
             Schema.validate_frontmatter(frontmatter, BlogSchema, unknown_keys: :ignore)

    assert {:error, reject_errors} =
             Schema.validate_frontmatter(frontmatter, BlogSchema, unknown_keys: :reject)

    assert Enum.any?(reject_errors, fn error -> error.message =~ "unknown key" end)
  end

  test "mutation helpers update dirty/revision state" do
    assert {:ok, doc} =
             Document.new(
               schema: BlogSchema,
               frontmatter: %{title: "Initial", slug: "initial"},
               body: "first\n"
             )

    assert doc.dirty == false
    assert doc.revision == 0

    assert {:ok, doc1} = Document.update_frontmatter(doc, %{published: true}, mode: :merge)
    assert doc1.dirty == true
    assert doc1.revision == 1
    assert doc1.frontmatter[:published] == true

    assert {:ok, doc2} = Document.update_body(doc1, "second\r\nline\r\n", line_endings: :lf)
    assert doc2.revision == 2
    assert doc2.body == "second\nline\n"

    assert {:ok, doc3} =
             Document.apply_body_patch(doc2, %{search: "line", replace: "entry", global: false})

    assert doc3.revision == 3
    assert doc3.body == "second\nentry\n"

    doc4 = Document.mark_clean(doc3)
    assert doc4.dirty == false
    assert doc4.revision == 3

    assert {:ok, doc5} = Document.update_body(doc4, doc4.body)
    assert doc5.revision == 3
  end
end
