defmodule AbsintheTraceReporter.Signature do
  def build(operations) when is_list(operations),
    do: "# -\n{" <> (operations |> Enum.map_join("\n", &operation/1)) <> "}"

  def operation(%Absinthe.Blueprint.Document.Operation{selections: selections}),
    do: from_selections(selections)

  def from_selections([]), do: []

  def from_selections(selections) when is_list(selections),
    do: selections |> Enum.map(&from_selection/1) |> Enum.sort()

  def from_selection(%Absinthe.Blueprint.Document.Field{name: name, selections: []}), do: name

  def from_selection(%Absinthe.Blueprint.Document.Field{name: name, selections: selections}),
    do: "#{name}{" <> (selections |> from_selections() |> Enum.join(" ")) <> "}"

  def from_selection(%Absinthe.Blueprint.Document.Fragment.Spread{name: name}), do: name

  def from_selection(%Absinthe.Blueprint.Document.Fragment.Inline{selections: selections}),
    do: "inline{" <> (selections |> from_selections() |> Enum.join(" ")) <> "}"

  def from_selection(%Absinthe.Blueprint.Document.Fragment.Named{
        name: name,
        selections: selections
      }),
      do: "#{name}{" <> (selections |> from_selections() |> Enum.join(" ")) <> "}"
end
