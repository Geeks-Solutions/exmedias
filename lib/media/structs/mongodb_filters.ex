defmodule Media.FiltersMongoDB do
  @moduledoc false
  # alias Media.Helpers
  # alias Media.PostgreSQL
  @computed_filters ["number_of_contents"]
  @ops %{
    "=" => "$eq",
    "<" => "$lt",
    ">" => "$gt",
    "<=" => "$lte",
    ">=" => "$gte"
  }
  import Ecto.Query

  # def add_offset(query, offset) do
  #   if offset != 0 do
  #     query
  #     |> offset(^offset)
  #   else
  #     query
  #   end
  # end
  def build_sort(%{"id" => value}) do
    [%{"$sort" => %{"_id" => convert_sort(value)}}]
  end

  def build_sort(sort) when is_map(sort) do
    sorted_values =
      sort
      |> Enum.reduce(%{}, fn {key, value}, acc ->
        acc |> Map.merge(Map.put(%{}, "#{key}", convert_sort(value)))
      end)

    [%{"$sort" => sorted_values}]
  end

  def build_sort(nil), do: []

  def convert_sort(value) when is_binary(value) do
    case String.downcase(value) do
      "desc" -> -1
      "asc" -> 1
    end
  end

  def add_sort(query, nil), do: query
  def add_sort(query, sort) when sort == %{}, do: query

  def add_sort(query, sort) do
    [field | _tail] = sort |> Map.keys()
    direction = sort[field]
    field = field |> String.to_atom()

    with false <- is_nil(direction),
         direction <- direction |> String.downcase() |> String.to_atom(),
         true <- direction in [:desc, :asc] do
      query
      |> order_by([p], [{^direction, field(p, ^field)}])
    else
      _ -> query
    end
  end

  def add_limit(query, limit) do
    if limit != 0 do
      query
      |> limit(^limit)
    else
      query
    end
  end

  def init(filters, op \\ %{})

  def init(filters, _op) when filters == [],
    do: []

  def init(nil, _op),
    do: []

  ## filters arrive in the format of [[filters]]
  ## this is how it was done no zencca but I was not sure of the purpose
  def init(filters, op) when is_list(filters) do
    ## remove the computed filter from here
    {computed_op, op} = Map.split(op |> Enum.at(0), @computed_filters)

    {computed_filters, filters} =
      Enum.split_with(filters |> Enum.at(0), fn filter ->
        (Map.keys(filter) |> Enum.at(0)) in @computed_filters
      end)

    # conditions =
    normal_filters =
      Enum.reduce(filters, [], fn filter, condition ->
        condition ++
          build_condition(
            filter,
            op
          )
      end)

    {initial_computations, computed_filters} =
      Enum.reduce(computed_filters, {[], []}, fn filter,
                                                 {initial_computations_acc, computed_filters_acc} ->
        ## For later maybe the build computed condition
        ## will need further initial computation like computing the array size of ``contents_used``
        ## in this case let the function return a tuple {initial_computation, computed filters}
        {initial_compuation, computed_filters} = build_computed_condition(filter, computed_op)
        {initial_computations_acc ++ initial_compuation, computed_filters ++ computed_filters_acc}
      end)

    {initial_computations, computed_filters, normal_filters}
  end

  # calculates the number of contents using this media
  defp build_computed_condition(%{"number_of_contents" => _value} = filter, operations) do
    ## The initial computation here is needed for all the queries thus we return an empty array here
    {[], build_condition(filter, operations)}
  end

  # calculates the number of media using this platform
  defp build_computed_condition(%{"number_of_medias" => _value} = filter, operations) do
    ## The initial computation here is needed for all the queries thus we return an empty array here
    {[], build_condition(filter, operations)}
  end

  defp build_computed_condition(_, _operations), do: []

  # defp build_condition(filter, nil, _condition) do
  #   [filter]
  # end

  defp build_condition(filter, operations) do
    key = filter |> Map.keys() |> List.first()

    operations
    |> Map.get(key)
    |> Map.get("operation")
    |> case do
      nil ->
        ## if there is no operation for this filter then we return the filter as is.
        [filter]

      "between" ->
        handle_between(operations, key)

      "<>" ->
        handle_between(operations, key)

      operation ->
        handle_operation(operation, filter, key)
    end
  end

  def handle_operation(operation, filter, field_name) do
    op =
      @ops
      |> Map.get(operation)

    value = filter |> Map.get(field_name)
    [%{} |> Map.put(field_name, Map.put(%{}, op, value))]
  end

  def handle_between(operation, field_name) do
    operation = operation |> Map.get(field_name)
    from = operation |> Map.get("from")
    to = operation |> Map.get("to")

    [
      %{}
      |> Map.put(field_name, %{"$gte" => from}),
      %{}
      |> Map.put(field_name, %{"$lte" => to})
    ]
  end

  def init(query, _filters, _op), do: query

  # =, <, >, <=, >=, <>

  # defp convert_to_string(duration) do
  #   cond do
  #     is_binary(duration) ->
  #       {int, _} = Integer.parse(duration)
  #       Integer.to_string(int)

  #     is_integer(duration) ->
  #       Integer.to_string(duration)

  #     is_float(duration) ->
  #       duration |> Float.to_string()
  #   end
  # end
end
