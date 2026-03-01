%{
  rename: %{
    "kb_title" => "title",
    "owner_team" => "owner",
    "reviewed_on" => "last_reviewed_on"
  },
  coerce: %{
    "archived" => :boolean,
    "revision_count" => :integer
  },
  drop: ["legacy_slug"],
  defaults: %{
    "status" => "active",
    "visibility" => "internal"
  }
}
