defmodule AbsintheTraceReporter.TraceProvider.Engine do
  @behaviour AbsintheTraceReporter.TraceReportProvider

  def build_trace_report(tracing) when is_list(tracing) do
    %Mdg.Engine.Proto.FullTracesReport{
      header: %Mdg.Engine.Proto.ReportHeader{
        agent_version: "apollo-engine-reporting@0.0.2",
        hostname: "engine.local",
        runtime_version: runtime_version(),
        service: "",
        service_version: "",
        uname: "darwin, Darwin, 17.7.0, x64)"
      },
      traces_per_query: build_traces_per_query(tracing)
    }
    |> Mdg.Engine.Proto.FullTracesReport.encode()
  end

  defp build_traces_per_query(tracing) when is_list(tracing) do
    tracing
    |> Enum.map(fn trace ->
      {trace.signature,
       Mdg.Engine.Proto.Trace.new(
         root: from_trace(trace),
         origin_reported_start_time: build_timestamp(trace.start_time),
         start_time: build_timestamp(trace.start_time),
         end_time: build_timestamp(trace.end_time),
         origin_reported_end_time: build_timestamp(trace.end_time)
       )}
    end)
    |> Enum.group_by(fn {signature, _trace} -> signature end, fn {_signature, trace} -> trace end)
    |> Enum.map(fn {sig, traces} ->
      {sig, %Mdg.Engine.Proto.Traces{trace: traces}}
    end)
    |> Enum.into(%{})
  end

  defp build_timestamp(time) do
    {:ok, time, _offset} = DateTime.from_iso8601(time)
    ns = nanoseconds(time)

    Google.Protobuf.Timestamp.new(
      seconds: DateTime.to_unix(time),
      nanos: ns
    )
  end

  defp nanoseconds(datetime) do
    case datetime.microsecond do
      {_, 0} -> 0
      {end_time_ms, _} -> end_time_ms * 1000
    end
  end

  def runtime_version do
    "Elixir #{System.version()}"
  end

  def from_trace(trace) do
    trace.tracing
    |> from_blueprint_execution
    |> build_trace_tree()
  end

  defp root_node do
    Mdg.Engine.Proto.Trace.Node.new(%{
      duration: 0,
      fieldName: "RootQueryType",
      meta: nil,
      parentType: "",
      path: [],
      returnType: "",
      startOffset: 0,
      child: []
    })
  end

  defp from_blueprint_execution(%{execution: %{resolvers: resolvers}}) do
    resolvers
  end

  defp from_blueprint_execution(_) do
    []
  end

  def build_trace_tree(resolvers) when is_list(resolvers) do
    children =
      resolvers
      |> Enum.sort_by(& &1.path)
      |> Enum.reduce(%{}, fn
        %{path: []}, acc ->
          acc

        %{path: path} = node, acc ->
          # TODO: integer -> list indices
          access_path =
            path
            |> Enum.map(fn
              index when is_integer(index) ->
                Access.key(index, %{new_index_node(index) | child: %{}})

              part ->
                part
            end)
            |> Enum.intersperse(Access.key(:child))

          put_in(acc, access_path, %{new_node(node) | child: %{}})
      end)
      |> reduce_nodes()

    %{root_node() | child: children}
  end

  def build_trace_tree(_), do: []

  defp reduce_nodes(%{} = nodes), do: nodes |> Map.values() |> Enum.map(&reduce_node/1)
  defp reduce_node(%{child: children} = node), do: %{node | child: reduce_nodes(children)}

  defp new_index_node(index) do
    Mdg.Engine.Proto.Trace.Node.new(
      cache_policy: nil,
      child: %{},
      end_time: 0,
      error: [],
      id: {:index, index},
      parent_type: "",
      start_time: 0,
      type: ""
    )
  end

  defp new_node(node) do
    Mdg.Engine.Proto.Trace.Node.new(
      cache_policy: nil,
      child: %{},
      end_time: node.startOffset + node.duration,
      error: [],
      id: {:field_name, node.fieldName},
      parent_type: node.parentType,
      start_time: node.startOffset,
      type: node.returnType
    )
  end
end
