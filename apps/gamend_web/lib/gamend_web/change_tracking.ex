defmodule GamendWeb.ChangeTracking do
  @moduledoc """
  Keeping a LiveView's updates to what changed, for a value worked out while
  rendering.

  LiveView sends an expression again when an assign it reads is *marked*
  changed. It never compares what the expression gives: the same class, the
  same list, the same number go out again, the browser patches them over
  what it has, and nothing on the screen says so. `assign/3` in a function
  component, or in a LiveView's `render/1`, marks its key on every render
  (the key is new to that render's assigns each time), so everything drawn
  from it is sent with every update of the page: a navbar with each coin
  spent, a keyboard with each key pressed.

  Three tools:

    * `derive/4` (and `derive_all/3`), in a **function component**: the value
      is marked changed only when the attrs it is worked out from are. It
      keeps nothing: it reads the component's own `__changed__`.
    * `derive_in_render/4`, where there are no such attrs to go by: a
      LiveView's `render/1`, or a component drawn once a page that reads
      something outside its attrs (a count in the database). The value is
      compared with the one the last render had.
    * `changed?/2`: whether any of the inputs changed, to skip work whose
      answer would not be drawn.

  And one rule they do not cover, because LiveView already does: **a list's
  entry holds all it is drawn from.** A comprehension's entries are compared
  one by one and an equal entry is skipped, but only where its body reads
  nothing but the entry. So a list is assigned plainly, each entry carrying
  its own state (a link whether it is the page's, a key its mark), never a
  body that reads `@current`, `@marks` or `@best_href`. A loop has one
  generator, and its body no `<% x = … %>`.

  Two things turn tracking off for a whole component, whatever its assigns:
  calling it with `{@rest}` or `{assigns}`, and `dynamic_tag`, which sends
  its tag and attributes every time.

  A reconnect, a second tab and a first render need nothing of this: with
  no change tracking (`__changed__` nil) every value is marked, and a new
  process has no last render to compare with.
  """

  @typedoc """
  What a derived value is worked out from: an attr (`:lang`), the fields of
  a map attr it reads (`state: [:grid]`), or what a function reads from a
  map attr (`state: &picked_word/1`).
  """
  @type input :: atom() | {atom(), [term()]} | {atom(), (map() -> term())}

  @doc """
  Whether any of `inputs` changed since the last render: true with no change
  tracking (a first render, a dead render).

  A map attr's fields and what a function reads from it are compared with
  the attr's value at the last render, which LiveView keeps in `__changed__`
  for an assign that was a map and hands on to a component given it straight
  through (`state={@board}`). The function is called with any map the attr
  ever held, so it answers for every shape of it.
  """
  @spec changed?(map(), [input()]) :: boolean()
  def changed?(%{__changed__: changed} = assigns, inputs) when is_map(changed),
    do: Enum.any?(inputs, &input_changed?(&1, assigns, changed))

  def changed?(_assigns, _inputs), do: true

  @doc """
  Puts `value` under `key`, marked changed only when one of `inputs` is
  (`changed?/2`). For a function component's own derived values:

      def keyboard(assigns) do
        assigns
        |> ChangeTracking.derive(:rows, [:lang, :layout], rows(assigns.lang, assigns.layout))
        ...

  The value must depend on nothing but the inputs: what else it reads would
  change it without marking it.
  """
  @spec derive(map(), atom(), [input()], term()) :: map()
  def derive(assigns, key, inputs, value) do
    if changed?(assigns, inputs),
      do: put_marked(assigns, key, value, true),
      else: Map.put(assigns, key, value)
  end

  @doc "`derive/4` for several values worked out from the same `inputs`."
  @spec derive_all(map(), [input()], Enumerable.t({atom(), term()})) :: map()
  def derive_all(assigns, inputs, values) do
    if changed?(assigns, inputs),
      do: Enum.reduce(values, assigns, fn {key, value}, acc -> put_marked(acc, key, value, true) end),
      else: Enum.reduce(values, assigns, fn {key, value}, acc -> Map.put(acc, key, value) end)
  end

  @doc """
  Puts `value` under `key`, marked changed only when it differs from the
  value the last render put there. For a LiveView's `render/1`, and for a
  component that is drawn once a page:

      def render(assigns) do
        assigns = ChangeTracking.derive_in_render(assigns, :score, score(assigns.round))

  The last value is the process's (a LiveView is one process for the life of
  its page; a reconnect is a new one), kept under `scope` and `key`: two
  renders in one process that use the same key (a LiveComponent and its
  LiveView, two components) each pass their own `scope`, their module.
  Never for a component drawn more than once a render: the second would be
  compared with the first.

  A value that was a map is marked as an assign is, with the map it was, so
  `@key.field` and a component handed `key={@key}` are tracked field by
  field (`changed?/2`).
  """
  @spec derive_in_render(map(), atom(), term(), term()) :: map()
  def derive_in_render(assigns, key, value, scope \\ nil)

  def derive_in_render(assigns, key, value, scope) do
    case Process.put({__MODULE__, scope, key}, {:rendered, value}) do
      {:rendered, was} when was === value -> Map.put(assigns, key, value)
      {:rendered, %{} = was} -> put_marked(assigns, key, value, was)
      _first_or_not_a_map -> put_marked(assigns, key, value, true)
    end
  end

  @doc """
  The value the last render put under `key` (`derive_in_render/4`), nil
  before the first: for work to skip while nothing it reads has changed.
  """
  @spec last_rendered(atom(), term()) :: term()
  def last_rendered(key, scope \\ nil) do
    case Process.get({__MODULE__, scope, key}) do
      {:rendered, value} -> value
      nil -> nil
    end
  end

  # Marked whatever the assigns hold under `key` now: `assign/3` leaves a
  # key unmarked when it already has the value, and a derived value may
  # take the name of an attr that holds it. With no change tracking there
  # is nothing to mark: everything is drawn.
  defp put_marked(%{__changed__: changed} = assigns, key, value, mark) when is_map(changed),
    do: %{assigns | __changed__: Map.put_new(changed, key, mark)} |> Map.put(key, value)

  defp put_marked(assigns, key, value, _mark), do: Map.put(assigns, key, value)

  defp input_changed?({attr, read}, assigns, changed) when is_function(read, 1) do
    case changed do
      %{^attr => %{} = was} ->
        now = Map.get(assigns, attr)
        not is_map(now) or read.(was) !== read.(now)

      %{^attr => _marked} ->
        true

      %{} ->
        false
    end
  end

  defp input_changed?({attr, fields}, assigns, changed) when is_list(fields) do
    case changed do
      %{^attr => %{} = was} ->
        now = Map.get(assigns, attr)
        not is_map(now) or Enum.any?(fields, &(Map.get(was, &1) !== Map.get(now, &1)))

      %{^attr => _marked} ->
        true

      %{} ->
        false
    end
  end

  defp input_changed?(attr, _assigns, changed) when is_atom(attr), do: is_map_key(changed, attr)
end
