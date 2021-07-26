defmodule Media.FiltersPostgreSQL do
  @moduledoc false
  # alias Media.Helpers
  # alias Media.PostgreSQL
  @computed_filters ["number_of_contents"]
  # @computed_filters []
  import Ecto.Query

  # def add_offset(query, offset) do
  #   if offset != 0 do
  #     query
  #     |> offset(^offset)
  #   else
  #     query
  #   end
  # end

  def add_sort(query, nil), do: query
  def add_sort(query, sort) when sort == %{}, do: query

  def add_sort(query, sort) do
    [field | _tail] = sort |> Map.keys()
    direction = sort[field]

    field =
      cond do
        is_binary(field) -> String.to_atom(field)
        is_atom(field) -> field
        true -> raise "Sorted field can only be an atom or a string"
      end

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

  def init(query, filters, op \\ %{})

  def init(query, filters, _op) when filters == [],
    do: query

  def init(query, all_filters, ops) when is_list(all_filters) do
    ## remove the computed filter from here
    {computed_op, op} =
      Enum.reduce(ops, {%{}, []}, fn op, {computed_ops, normal_ops} ->
        {computed_op, op} = Map.split(op, @computed_filters)
        {computed_op |> Map.merge(computed_ops), normal_ops ++ [op]}
      end)

    {computed_filters, filters} =
      Enum.reduce(all_filters, {[], []}, fn filters, {comp_filters, normal_filters} ->
        {computed_filters, filters} =
          Enum.split_with(filters, fn filter ->
            (Map.keys(filter) |> Enum.at(0)) in @computed_filters
          end)

        {computed_filters ++ comp_filters, [filters] ++ normal_filters}
      end)

    # filters = [filters]

    conditions =
      Enum.reduce(filters, false, fn filter, condition ->
        dynamic(^build_where_and(filter, op) or ^condition)
      end)

    if computed_filters == [] do
      query
      |> where(^conditions)
    else
      computed_filters = computed_filters(query, computed_filters, computed_op)

      query
      |> having(^computed_filters)
      |> where(^conditions)
    end
  end

  def init(query, _filters, _op), do: query

  def computed_filters(_query, filters, _op) when filters == [] do
    dynamic([], ^true or ^false)
  end

  def computed_filters(query, filters, op) do
    ## I should accumulate into dynamic and not query
    Enum.reduce(filters, true, fn filter, dynamic ->
      dynamic((^add_computed_condition(query, filter, op) and ^dynamic) or false)
    end)
  end

  # =, <, >, <=, >=, <>
  def add_computed_condition(_query, %{"number_of_contents" => value}, op) do
    operation = op["number_of_contents"]["operation"]
    value = if is_binary(value), do: value |> String.to_integer(), else: value

    case operation do
      "=" ->
        dynamic([p, m, c, joint_table], fragment("COUNT(?) = ?", joint_table.content_id, ^value))

      "<" ->
        dynamic([p, m, c, joint_table], fragment("COUNT(?) < ?", joint_table.content_id, ^value))

      ">" ->
        dynamic([p, m, c, joint_table], fragment("COUNT(?) < ?", joint_table.content_id, ^value))

      "<=" ->
        dynamic([p, m, c, joint_table], fragment("COUNT(?) < ?", joint_table.content_id, ^value))

      ">=" ->
        dynamic([p, m, c, joint_table], fragment("COUNT(?) < ?", joint_table.content_id, ^value))

      "<>" ->
        dynamic_between(op)

      "between" ->
        dynamic_between(op)
    end
  end

  defp dynamic_between(op) do
    from = Map.get(op["number_of_contents"], "from", "0") |> Integer.parse() |> elem(0)
    to = Map.get(op["number_of_contents"], "to", "0") |> Integer.parse() |> elem(0)

    dynamic(
      [p, c, m, joint_table],
      fragment(
        "COUNT(?) > ? and COUNT(?) < ?",
        joint_table.content_id,
        ^from,
        joint_table.content_id,
        ^to
      )
    )
  end

  def build_where_and(filter, op) do
    Enum.reduce(filter, true, fn
      %{"title" => value}, dynamic ->
        dynamic([p], ^dynamic and p.title == ^value)

      %{"namespace" => value}, dynamic ->
        dynamic([p], ^dynamic and p.namespace == ^value)

      %{"author" => value}, dynamic ->
        dynamic([p], ^dynamic and p.author == ^value)

      %{"private_status" => value}, dynamic ->
        dynamic([p], ^dynamic and p.private_status == ^value)

      %{"locked_status" => value}, dynamic ->
        ## to do check if the dates need more processing
        dynamic([p], ^dynamic and p.locked_status == ^value)

      %{"number_of_medias" => value}, dynamic ->
        ## to do check if the dates need more processing
        number_of_medias_op(value, dynamic, op)

      in_table, dynamic ->
        in_table(in_table, dynamic, op)
    end)
  end

  defp number_of_medias_op(value, dynamic, op) do
    op =
      Enum.find(op, fn
        %{"number_of_medias" => _op} -> true
        _ -> false
      end)
      |> Map.get("number_of_medias")

    operation = op |> Map.get("operation", ">=")

    case operation do
      "=" ->
        dynamic(
          [p, s],
          ^dynamic and fragment("COALESCE(?, 0) = ?::bigint", s.number_of_medias, ^value)
        )

      ">" ->
        dynamic(
          [p, s],
          ^dynamic and fragment("COALESCE(?, 0) > ?::bigint", s.number_of_medias, ^value)
        )

      val ->
        number_of_medias_op_eq(value, dynamic, val)
    end
  end

  defp number_of_medias_op_eq(value, dynamic, operation) do
    case operation do
      ">=" ->
        dynamic(
          [p, s],
          ^dynamic and fragment("COALESCE(?, 0) >= ?::bigint", s.number_of_medias, ^value)
        )

      "<" ->
        dynamic(
          [p, s],
          ^dynamic and fragment("COALESCE(?, 0) < ?::bigint", s.number_of_medias, ^value)
        )

      "<=" ->
        dynamic(
          [p, s],
          ^dynamic and fragment("COALESCE(?, 0) <= ?::bigint", s.number_of_medias, ^value)
        )

      _val ->
        handle_rest_of_operations(value, dynamic, operation)
    end
  end

  def handle_rest_of_operations(_value, dynamic, op) when op in ["between", "<>"] do
    {from, _} = Map.get(op, "from") |> Float.parse()
    {to, _} = Map.get(op, "to") |> Float.parse()

    dynamic(
      [p, s],
      ^dynamic and fragment("COALESCE(?, 0) > ?::bigint", s.number_of_medias, ^from) and
        fragment("COALESCE(?, 0) < ?::bigint", s.number_of_medias, ^to)
    )
  end

  defp in_table(in_table, dynamic, _op) do
    key_string = in_table |> Map.keys() |> Enum.at(0)
    key_atom = key_string |> String.to_atom()
    value = in_table[key_string]

    case key_string do
      "title_alike" ->
        dynamic(
          [p],
          ^dynamic and
            fragment(
              "LOWER(?) ~ LOWER(?)",
              p.title,
              ^value
            )
        )

      _ ->
        dynamic([p], ^dynamic and field(p, ^key_atom) == ^value)
    end
  end

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
