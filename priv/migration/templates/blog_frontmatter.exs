%{
  rename: %{
    "headline" => "title",
    "summary" => "description",
    "published_at" => "published_on"
  },
  coerce: %{
    "draft" => :boolean,
    "priority" => :integer
  },
  drop: ["legacy_id", "layout"],
  defaults: %{
    "status" => "draft",
    "category" => "general"
  }
}
