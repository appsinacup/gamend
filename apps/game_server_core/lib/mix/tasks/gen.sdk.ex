defmodule Mix.Tasks.Gen.Sdk do
  @moduledoc """
  Generates SDK stub modules from the real GameServer modules.

  This task reads the real implementations and generates stub modules
  for the SDK package with matching type specs and documentation.

  ## Usage

      mix gen.sdk

  The generated files are placed in `sdk/lib/game_server/`.
  """
  use Mix.Task

  @shortdoc "Generate SDK stubs from real GameServer modules"

  @sdk_modules [
    {GameServer.Accounts, "accounts.ex"},
    {GameServer.Quests, "quests.ex"},
    {GameServer.Lobbies, "lobbies.ex"},
    {GameServer.Leaderboards, "leaderboards.ex"},
    {GameServer.Friends, "friends.ex"},
    {GameServer.Groups, "groups.ex"},
    {GameServer.Parties, "parties.ex"},
    {GameServer.Notifications, "notifications.ex"},
    {GameServer.Push, "push.ex"},
    {GameServer.Chat, "chat.ex"},
    {GameServer.Schedule, "schedule.ex"},
    {GameServer.Jobs, "jobs.ex"},
    {GameServer.Economy, "economy.ex"},
    {GameServer.Inventory, "inventory.ex"},
    {GameServer.KV, "kv.ex"},
    {GameServer.Lock, "lock.ex"},
    {GameServer.Tournaments, "tournaments.ex"},
    {GameServer.ReadyChecks, "ready_checks.ex"}
  ]

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("compile")

    sdk_dir = Path.join([output_root(), "sdk", "lib", "game_server"])
    File.mkdir_p!(sdk_dir)

    for {module, filename} <- @sdk_modules do
      generate_stub(module, filename, sdk_dir)
    end

    Mix.shell().info("SDK stubs generated in #{sdk_dir}")
  end

  defp generate_stub(module, filename, sdk_dir) do
    {:docs_v1, _, :elixir, _, module_doc, _, function_docs} = Code.fetch_docs(module)

    specs = get_specs(module)
    types = get_types(module)

    functions = list_public_functions(module)

    function_docs_by_name = build_function_docs_by_name(function_docs)

    arg_names_by_mfa = build_arg_names_by_mfa(module)

    module_doc_text =
      case module_doc do
        %{"en" => doc} -> doc
        _ -> ""
      end

    stub_content =
      generate_module_content(
        module,
        module_doc_text,
        types,
        functions,
        function_docs,
        function_docs_by_name,
        arg_names_by_mfa,
        specs
      )

    path = Path.join(sdk_dir, filename)
    File.write!(path, stub_content)
    Mix.shell().info("Generated #{path}")
  end

  defp output_root do
    cwd = Path.expand(File.cwd!())
    parent = Path.dirname(cwd)

    if Path.basename(parent) == "apps" do
      Path.dirname(parent)
    else
      cwd
    end
  end

  defp get_specs(module) do
    case Code.Typespec.fetch_specs(module) do
      {:ok, specs} -> specs
      :error -> []
    end
  end

  defp get_types(module) do
    case Code.Typespec.fetch_types(module) do
      {:ok, types} -> types
      :error -> []
    end
  end

  defp generate_module_content(
         module,
         module_doc,
         types,
         functions,
         function_docs,
         function_docs_by_name,
         arg_names_by_mfa,
         specs
       ) do
    module_name = inspect(module)

    type_stubs =
      types
      |> Enum.map(&type_entry_to_string/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")

    function_stubs =
      functions
      |> Enum.reject(&doc_false?(&1, function_docs))
      |> Enum.map(
        &generate_function_stub(
          &1,
          module_name,
          function_docs,
          function_docs_by_name,
          arg_names_by_mfa,
          specs
        )
      )
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n\n")

    """
    defmodule #{module_name} do
      @moduledoc ~S\"\"\"
    #{indent_doc(escape_doc(module_doc), 2)}

      **Note:** This is an SDK stub. Calling these functions will raise an error.
      The actual implementation runs on the GameServer.
      \"\"\"

    #{type_stubs}

    #{function_stubs}
    end
    """
  end

  defp type_entry_to_string({kind, type_form}) when kind in [:type, :opaque] do
    quoted = Code.Typespec.type_to_quoted(type_form)
    attr = if kind == :opaque, do: "@opaque", else: "@type"
    "  #{attr} #{Macro.to_string(quoted)}"
  end

  defp type_entry_to_string(_), do: ""

  defp generate_function_stub(
         {function_name, arity},
         module_name,
         function_docs,
         function_docs_by_name,
         arg_names_by_mfa,
         specs
       )
       when is_atom(function_name) and is_integer(arity) do
    matching_doc =
      Enum.find(function_docs, fn
        {{:function, name, a}, _line, _sig, _doc, _meta} -> name == function_name and a == arity
        _ -> false
      end)

    {doc_text, signatures} =
      case matching_doc do
        {{:function, ^function_name, ^arity}, _line, sigs, doc_content, _meta} ->
          doc_text =
            case doc_content do
              %{"en" => doc} -> doc
              _ -> ""
            end

          {doc_text, sigs}

        _ ->
          fallback = Map.get(function_docs_by_name, function_name, nil)

          case fallback do
            %{doc_text: fallback_doc_text, signatures: fallback_sigs} ->
              {fallback_doc_text, fallback_sigs}

            _ ->
              {"", []}
          end
      end

    spec_text_raw = find_spec_text(function_name, arity, specs)
    spec_text = ensure_spec_text(module_name, function_name, arity, spec_text_raw)
    return_expr = stub_return_expression(function_name, spec_text)

    arg_names =
      arg_names_from_signature(signatures, arity)
      |> maybe_fallback_arg_names(function_name, arity, arg_names_by_mfa)

    arg_names = ensure_unique_arg_names(arg_names)

    ignored_args = Enum.map_join(arg_names, ", ", &"_#{&1}")

    doc_block =
      if doc_text == "" do
        "  @doc false\n"
      else
        """
          @doc ~S\"\"\"
        #{indent_doc(escape_doc(doc_text), 4)}
          \"\"\"
        """
      end

    """
    #{doc_block}#{spec_text}  def #{function_name}(#{ignored_args}) do
        case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
          :placeholder ->
            #{return_expr}

          _ ->
            raise "#{module_name}.#{function_name}/#{arity} is a stub - only available at runtime on GameServer"
        end
      end
    """
  end

  defp ensure_spec_text(module_name, function_name, arity, spec_text)
       when is_binary(module_name) and is_atom(function_name) and is_integer(arity) do
    if is_binary(spec_text) and spec_text != "" do
      spec_text
    else
      raise "Missing @spec for #{module_name}.#{function_name}/#{arity}. Add a correct typespec in the server module before generating the SDK."
    end
  end

  defp stub_return_expression(function_name, spec_text)
       when is_atom(function_name) and is_binary(spec_text) do
    return_type = extract_spec_return_type(spec_text)
    placeholder_expr_for_return_type(return_type) || fallback_placeholder_by_name(function_name)
  end

  defp placeholder_expr_for_return_type(return_type) when is_binary(return_type) do
    placeholder_expr_for_named_types(return_type) ||
      placeholder_expr_for_generics(return_type) ||
      placeholder_expr_for_primitives(return_type)
  end

  defp placeholder_expr_for_return_type(_), do: nil

  defp placeholder_expr_for_named_types(return_type) when is_binary(return_type) do
    rules = [
      # GameServer.KV.get/* returns `{:ok, payload()} | :error` where payload is a map with
      # required `:value` and `:metadata` keys. Returning `{:ok, nil}` in the stub causes
      # downstream code that pattern-matches on the payload shape to trigger "clause will never match"
      # typing warnings. Generate a placeholder that exercises both branches.
      {fn rt -> String.contains?(rt, "{:ok, payload()}") and String.contains?(rt, ":error") end,
       "if :erlang.phash2(make_ref(), 2) == 0, do: :error, else: {:ok, %{value: %{}, metadata: %{}}}"},
      {fn rt -> String.contains?(rt, "{:ok, GameServer.Accounts.User.t()}") end,
       "{:ok, #{user_placeholder_expr()}}"},
      {fn rt -> String.contains?(rt, "{:ok, GameServer.Lobbies.Lobby.t()}") end,
       "{:ok, #{lobby_placeholder_expr()}}"},
      {fn rt -> String.contains?(rt, "{:ok, GameServer.Leaderboards.Leaderboard.t()}") end,
       "{:ok, #{leaderboard_placeholder_expr()}}"},
      {fn rt -> String.contains?(rt, "{:ok, GameServer.Leaderboards.Record.t()}") end,
       "{:ok, #{record_placeholder_expr()}}"},
      {fn rt -> String.contains?(rt, "{:ok, GameServer.Friends.Friendship.t()}") end,
       "{:ok, #{friendship_placeholder_expr()}}"},
      {fn rt -> String.contains?(rt, "{:ok, GameServer.Tournaments.Tournament.t()}") end,
       "{:ok, #{tournament_placeholder_expr()}}"},
      {fn rt -> String.contains?(rt, "{:ok, GameServer.Tournaments.Entry.t()}") end,
       "{:ok, #{tournament_entry_placeholder_expr()}}"},
      {fn rt -> String.contains?(rt, "{:ok, GameServer.Tournaments.Match.t()}") end,
       "{:ok, #{tournament_match_placeholder_expr()}}"},
      {fn rt -> String.contains?(rt, "{:ok, GameServer.Push.PushToken.t()}") end,
       "{:ok, #{push_token_placeholder_expr()}}"},
      {fn rt -> String.contains?(rt, "{:ok, GameServer.ReadyChecks.Check.t()}") end,
       "{:ok, #{ready_check_placeholder_expr()}}"},
      {fn rt -> String.contains?(rt, "{:ok, GameServer.Quests.Quest.t()}") end,
       "{:ok, #{quest_placeholder_expr()}}"},
      {fn rt -> String.contains?(rt, "{:ok, GameServer.Quests.QuestProgress.t()}") end,
       "{:ok, #{quest_progress_placeholder_expr()}}"},
      {fn rt -> String.contains?(rt, "{:ok, [GameServer.Quests.QuestProgress.t()]}") end,
       "{:ok, []}"},
      {fn rt -> String.contains?(rt, "%{progress: GameServer.Quests.QuestProgress.t()") end,
       "{:ok, %{progress: #{quest_progress_placeholder_expr()}, rewards: []}}"},

      # For unions like `T | nil`, prefer a non-nil placeholder when we recognize T.
      # This keeps stub bodies type-friendly for external type checkers that infer from code.
      {fn rt ->
         String.contains?(rt, "GameServer.Accounts.User.t()") and String.contains?(rt, "| nil")
       end, "if :erlang.phash2(make_ref(), 2) == 0, do: nil, else: #{user_placeholder_expr()}"},
      {fn rt ->
         String.contains?(rt, "GameServer.Lobbies.Lobby.t()") and String.contains?(rt, "| nil")
       end, "if :erlang.phash2(make_ref(), 2) == 0, do: nil, else: #{lobby_placeholder_expr()}"},
      {fn rt ->
         String.contains?(rt, "GameServer.Leaderboards.Leaderboard.t()") and
           String.contains?(rt, "| nil")
       end,
       "if :erlang.phash2(make_ref(), 2) == 0, do: nil, else: #{leaderboard_placeholder_expr()}"},
      {fn rt ->
         String.contains?(rt, "GameServer.Leaderboards.Record.t()") and
           String.contains?(rt, "| nil")
       end, "if :erlang.phash2(make_ref(), 2) == 0, do: nil, else: #{record_placeholder_expr()}"},
      {fn rt ->
         String.contains?(rt, "GameServer.Friends.Friendship.t()") and
           String.contains?(rt, "| nil")
       end,
       "if :erlang.phash2(make_ref(), 2) == 0, do: nil, else: #{friendship_placeholder_expr()}"},
      {fn rt ->
         String.contains?(rt, "GameServer.Tournaments.Tournament.t()") and
           String.contains?(rt, "| nil")
       end,
       "if :erlang.phash2(make_ref(), 2) == 0, do: nil, else: #{tournament_placeholder_expr()}"},
      {fn rt ->
         String.contains?(rt, "GameServer.Tournaments.Entry.t()") and
           String.contains?(rt, "| nil")
       end,
       "if :erlang.phash2(make_ref(), 2) == 0, do: nil, else: #{tournament_entry_placeholder_expr()}"},
      {fn rt ->
         String.contains?(rt, "GameServer.Tournaments.Match.t()") and
           String.contains?(rt, "| nil")
       end,
       "if :erlang.phash2(make_ref(), 2) == 0, do: nil, else: #{tournament_match_placeholder_expr()}"},
      {fn rt ->
         String.contains?(rt, "GameServer.Tournaments.Bracket.t()") and
           String.contains?(rt, "| nil")
       end,
       "if :erlang.phash2(make_ref(), 2) == 0, do: nil, else: #{tournament_bracket_placeholder_expr()}"},
      {fn rt ->
         String.contains?(rt, "GameServer.ReadyChecks.Check.t()") and
           String.contains?(rt, "| nil")
       end,
       "if :erlang.phash2(make_ref(), 2) == 0, do: nil, else: #{ready_check_placeholder_expr()}"},
      {fn rt ->
         String.contains?(rt, "GameServer.Groups.Group.t()") and String.contains?(rt, "| nil")
       end, "if :erlang.phash2(make_ref(), 2) == 0, do: nil, else: #{group_placeholder_expr()}"},
      {fn rt ->
         String.contains?(rt, "GameServer.Quests.Quest.t()") and String.contains?(rt, "| nil")
       end, "if :erlang.phash2(make_ref(), 2) == 0, do: nil, else: #{quest_placeholder_expr()}"},
      {fn rt ->
         String.contains?(rt, "GameServer.Quests.QuestProgress.t()") and
           String.contains?(rt, "| nil")
       end,
       "if :erlang.phash2(make_ref(), 2) == 0, do: nil, else: #{quest_progress_placeholder_expr()}"},
      {fn rt -> friendship_struct_return?(rt) end, friendship_placeholder_expr()},

      # Fallback: if the return type allows nil and we can't infer a better placeholder, use nil.
      {fn rt -> String.contains?(rt, "| nil") end, "nil"}
    ]

    Enum.find_value(rules, fn {pred, expr} -> if pred.(return_type), do: expr, else: nil end)
  end

  defp friendship_struct_return?(return_type) when is_binary(return_type) do
    String.contains?(return_type, "GameServer.Friends.Friendship.t()") and
      not String.contains?(return_type, "list(") and
      not String.contains?(return_type, "[")
  end

  defp placeholder_expr_for_generics(return_type) when is_binary(return_type) do
    cond do
      String.contains?(return_type, "hook_result(") ->
        "{:ok, nil}"

      String.contains?(return_type, "{:ok,") ->
        "{:ok, nil}"

      true ->
        nil
    end
  end

  defp placeholder_expr_for_primitives(return_type) when is_binary(return_type) do
    cond do
      String.contains?(return_type, "boolean()") ->
        "false"

      String.contains?(return_type, "integer()") ->
        "0"

      String.contains?(return_type, "String.t()") ->
        "\"\""

      String.contains?(return_type, ":ok") ->
        ":ok"

      String.contains?(return_type, "map()") or String.contains?(return_type, "%{") ->
        "%{}"

      String.contains?(return_type, "keyword()") or String.contains?(return_type, "Keyword.t()") ->
        "[]"

      String.contains?(return_type, "list(") or String.contains?(return_type, "[") or
          String.contains?(return_type, "List.t()") ->
        "[]"

      true ->
        nil
    end
  end

  defp extract_spec_return_type(spec_text) when is_binary(spec_text) do
    # spec_text is formatted like "  @spec foo(arg) :: return\n".
    # Extract the return portion after "::".
    case Regex.run(~r/::\s*(.+)\n\z/, spec_text) do
      [_, return_type] -> String.trim(return_type)
      _ -> nil
    end
  end

  defp fallback_placeholder_by_name(function_name) when is_atom(function_name) do
    name = Atom.to_string(function_name)

    cond do
      String.ends_with?(name, "?") ->
        "false"

      String.starts_with?(name, "list_") ->
        "[]"

      String.starts_with?(name, "count_") ->
        "0"

      String.starts_with?(name, "get_") or String.starts_with?(name, "find_") ->
        "nil"

      String.starts_with?(name, "update_") or String.starts_with?(name, "create_") or
        String.starts_with?(name, "delete_") or String.starts_with?(name, "upsert_") ->
        "{:ok, nil}"

      true ->
        "nil"
    end
  end

  defp dt_placeholder_expr, do: "~U[1970-01-01 00:00:00Z]"

  defp user_placeholder_expr do
    dt = dt_placeholder_expr()

    "%GameServer.Accounts.User{id: 0, email: \"\", display_name: nil, metadata: %{}, is_admin: false, inserted_at: #{dt}, updated_at: #{dt}}"
  end

  defp lobby_placeholder_expr do
    dt = dt_placeholder_expr()

    "%GameServer.Lobbies.Lobby{id: 0, title: \"\", host_id: nil, hostless: false, max_users: 0, is_hidden: false, is_locked: false, metadata: %{}, inserted_at: #{dt}, updated_at: #{dt}}"
  end

  defp group_placeholder_expr do
    dt = dt_placeholder_expr()

    "%GameServer.Groups.Group{id: \"\", title: \"\", description: \"\", icon_url: nil, type: \"public\", max_members: 100, metadata: %{}, slowdown: 0, creator_id: nil, inserted_at: #{dt}, updated_at: #{dt}}"
  end

  defp leaderboard_placeholder_expr do
    dt = dt_placeholder_expr()

    "%GameServer.Leaderboards.Leaderboard{id: 0, slug: \"\", title: \"\", description: nil, sort_order: :desc, operator: :set, starts_at: nil, ends_at: nil, metadata: %{}, inserted_at: #{dt}, updated_at: #{dt}}"
  end

  defp tournament_placeholder_expr do
    dt = dt_placeholder_expr()

    "%GameServer.Tournaments.Tournament{id: \"\", slug: \"\", title: \"\", description: \"\", state: \"scheduled\", registration_opens_at: nil, starts_at: nil, ends_at: nil, recur: nil, max_entries: nil, team_size: 1, bracket_size: 8, round_window_sec: 3600, deadline_policy: \"forfeit_both\", metadata: %{}, inserted_at: #{dt}, updated_at: #{dt}}"
  end

  defp tournament_entry_placeholder_expr do
    dt = dt_placeholder_expr()

    "%GameServer.Tournaments.Entry{id: \"\", tournament_id: \"\", leader_id: \"\", seed: nil, bracket_index: nil, wins: 0, state: \"registered\", metadata: %{}, inserted_at: #{dt}, updated_at: #{dt}}"
  end

  defp tournament_match_placeholder_expr do
    dt = dt_placeholder_expr()

    "%GameServer.Tournaments.Match{id: \"\", tournament_id: \"\", bracket_index: 0, round: 1, slot: 0, a_entry_id: nil, b_entry_id: nil, winner_entry_id: nil, ready_at: nil, expired_at: nil, resolved_at: nil, deadline_at: #{dt}, metadata: %{}, inserted_at: #{dt}, updated_at: #{dt}}"
  end

  defp ready_check_placeholder_expr do
    dt = dt_placeholder_expr()

    "%GameServer.ReadyChecks.Check{id: \"\", kind: \"ready\", status: \"pending\", lobby_id: nil, deadline_at: nil, opened_by: nil, reason: nil, resolved_at: nil, metadata: %{}, participants: [], inserted_at: #{dt}, updated_at: #{dt}}"
  end

  defp tournament_bracket_placeholder_expr do
    dt = dt_placeholder_expr()

    "%GameServer.Tournaments.Bracket{id: \"\", tournament_id: \"\", index: 0, size: 8, inserted_at: #{dt}}"
  end

  defp push_token_placeholder_expr do
    dt = dt_placeholder_expr()

    "%GameServer.Push.PushToken{id: \"\", user_id: \"\", token: \"\", platform: \"android\", provider: \"fcm\", device_id: nil, disabled_at: nil, last_used_at: nil, metadata: %{}, inserted_at: #{dt}, updated_at: #{dt}}"
  end

  defp quest_placeholder_expr do
    dt = dt_placeholder_expr()

    "%GameServer.Quests.Quest{id: \"\", key: \"\", title: \"\", description: \"\", icon_url: nil, sort_order: 0, hidden: false, kind: \"achievement\", objectives: [], rewards: [], auto_claim: false, prerequisite_quest_key: nil, starts_at: nil, ends_at: nil, active: true, metadata: %{}, inserted_at: #{dt}, updated_at: #{dt}}"
  end

  defp quest_progress_placeholder_expr do
    dt = dt_placeholder_expr()

    "%GameServer.Quests.QuestProgress{id: \"\", user_id: \"\", quest_key: \"\", period_key: \"static\", objective_progress: %{}, status: \"active\", completed_at: nil, claimed_at: nil, rewards_granted_at: nil, metadata: %{}, inserted_at: #{dt}, updated_at: #{dt}}"
  end

  defp record_placeholder_expr do
    dt = dt_placeholder_expr()

    "%GameServer.Leaderboards.Record{id: 0, leaderboard_id: 0, user_id: 0, label: nil, score: 0, rank: nil, metadata: %{}, inserted_at: #{dt}, updated_at: #{dt}}"
  end

  defp friendship_placeholder_expr do
    dt = dt_placeholder_expr()

    "%GameServer.Friends.Friendship{id: 0, requester_id: 0, target_id: 0, requester: nil, target: nil, status: \"pending\", inserted_at: #{dt}, updated_at: #{dt}}"
  end

  defp build_function_docs_by_name(function_docs) do
    function_docs
    |> Enum.reduce(%{}, fn
      {{:function, name, arity}, _line, sigs, doc_content, _meta}, acc ->
        doc_text =
          case doc_content do
            %{"en" => doc} -> doc
            _ -> ""
          end

        # Prefer an entry that actually has documentation.
        cond do
          doc_text == "" ->
            acc

          Map.has_key?(acc, name) ->
            existing = acc[name]

            if arity > existing.arity,
              do: Map.put(acc, name, %{arity: arity, doc_text: doc_text, signatures: sigs}),
              else: acc

          true ->
            Map.put(acc, name, %{arity: arity, doc_text: doc_text, signatures: sigs})
        end

      _, acc ->
        acc
    end)
  end

  defp list_public_functions(module) do
    all_funs =
      module.__info__(:functions)
      |> Enum.reject(fn {name, _arity} ->
        name in [:module_info, :behaviour_info] or
          String.starts_with?(Atom.to_string(name), "__")
      end)

    # Group by name to detect default-argument variants.
    # When a function has default args, Elixir generates multiple arities.
    # We only keep the highest arity (which has the @spec) and skip lower
    # arities that are just generated wrappers.
    specs =
      case Code.Typespec.fetch_specs(module) do
        {:ok, s} -> s
        :error -> []
      end

    spec_set = MapSet.new(specs, fn {{name, arity}, _} -> {name, arity} end)

    by_name = Enum.group_by(all_funs, fn {name, _} -> name end)

    all_funs
    |> Enum.reject(fn {name, arity} ->
      arities = Enum.map(by_name[name], fn {_, a} -> a end)
      max_arity = Enum.max(arities)

      # Skip lower-arity variants that lack their own @spec
      arity < max_arity and not MapSet.member?(spec_set, {name, arity})
    end)
    |> Enum.sort_by(fn {name, arity} -> {Atom.to_string(name), arity} end)
  end

  # Returns true when the function is marked @doc false (hidden) in the source.
  defp doc_false?({function_name, arity}, function_docs) do
    Enum.any?(function_docs, fn
      {{:function, ^function_name, ^arity}, _line, _sigs, :hidden, _meta} -> true
      _ -> false
    end)
  end

  defp arg_names_from_signature(signatures, arity) when is_list(signatures) do
    case signatures do
      [sig | _] when is_binary(sig) ->
        # Parse "func_name(arg1, arg2, opts \\ [])" to get arg names.
        # Note: function names can include ? and !
        case Regex.run(~r/[\w!?]+\(([^)]*)\)/, sig) do
          [_, args_str] ->
            args_str
            |> String.split(",")
            |> Enum.map(&extract_arg_name/1)
            |> Enum.take(arity)

          _ ->
            generate_arg_names(arity)
        end

      _ ->
        generate_arg_names(arity)
    end
  end

  defp arg_names_from_signature(_, arity), do: generate_arg_names(arity)

  defp maybe_fallback_arg_names(arg_names, function_name, arity, arg_names_by_mfa)
       when is_list(arg_names) do
    has_auto = Enum.any?(arg_names, &String.match?(&1, ~r/^arg\d+$/))

    cond do
      arg_names == [] ->
        Map.get(arg_names_by_mfa, {function_name, arity}, generate_arg_names(arity))

      has_auto ->
        Map.get(arg_names_by_mfa, {function_name, arity}, arg_names)

      true ->
        arg_names
    end
  end

  defp extract_arg_name(arg_str) do
    arg_str
    |> String.trim()
    # Remove default value (opts \\\\ [])
    |> String.replace(~r/\\\\.*$/, "")
    |> String.trim()
  end

  defp find_spec_text(function_name, arity, specs) do
    case Enum.find(specs, fn {{name, a}, _} -> name == function_name and a == arity end) do
      {{_, _}, [spec | _]} ->
        # spec is a single spec clause, wrap in list for spec_to_quoted
        try do
          spec_str = Macro.to_string(Code.Typespec.spec_to_quoted(function_name, spec))
          "  @spec #{spec_str}\n"
        rescue
          _ -> ""
        end

      _ ->
        ""
    end
  end

  defp generate_arg_names(0), do: []

  defp generate_arg_names(arity) do
    Enum.map(1..arity, &"arg#{&1}")
  end

  defp build_arg_names_by_mfa(module) do
    source = module.module_info(:compile)[:source]

    with true <- is_list(source),
         source_path <- List.to_string(source),
         {:ok, content} <- File.read(source_path),
         {:ok, ast} <- Code.string_to_quoted(content) do
      {_, acc} =
        Macro.prewalk(ast, %{}, fn
          {:def, _meta, [head, _body]} = node, acc ->
            {node, maybe_put_def_arg_names(head, acc)}

          {:defp, _meta, [head, _body]} = node, acc ->
            {node, maybe_put_def_arg_names(head, acc)}

          node, acc ->
            {node, acc}
        end)

      acc
    else
      _ ->
        %{}
    end
  end

  defp maybe_put_def_arg_names(head, acc) do
    {name, args_ast} =
      case head do
        {:when, _meta, [{fun_name, _meta2, args}, _guard]}
        when is_atom(fun_name) and is_list(args) ->
          {fun_name, args}

        {fun_name, _meta, args} when is_atom(fun_name) and is_list(args) ->
          {fun_name, args}

        _ ->
          {nil, nil}
      end

    if is_list(args_ast) do
      arity = length(args_ast)

      arg_names =
        args_ast
        |> Enum.with_index(1)
        |> Enum.map(fn {arg_ast, idx} ->
          arg_name_from_pattern(arg_ast, idx)
        end)

      # Populate entries for default-arg arities too (eg. def f(a, b \\ 1)
      # exports f/1 and f/2).
      Enum.reduce(0..arity, acc, fn a, acc ->
        Map.put_new(acc, {name, a}, Enum.take(arg_names, a))
      end)
    else
      acc
    end
  end

  defp arg_name_from_pattern({:=, _meta, [_left, {var, _m, _c}]}, _idx) when is_atom(var) do
    var
    |> Atom.to_string()
    |> String.trim_leading("_")
    |> blank_to("arg")
  end

  defp arg_name_from_pattern({:%, _meta, [alias_ast, map_ast]}, idx) do
    alias_last =
      case alias_ast do
        {:__aliases__, _m, parts} when is_list(parts) -> List.last(parts)
        atom when is_atom(atom) -> atom
        _ -> nil
      end

    base =
      if is_atom(alias_last) do
        Macro.underscore(Atom.to_string(alias_last))
      else
        "arg#{idx}"
      end

    hint = struct_var_hint(map_ast)

    if is_binary(hint) and hint != "" do
      hint
    else
      base
    end
  end

  defp arg_name_from_pattern({var, _m, _c}, idx) when is_atom(var) and var != :% do
    case Atom.to_string(var) do
      "_" -> "arg#{idx}"
      other -> other |> String.trim_leading("_") |> blank_to("arg#{idx}")
    end
  end

  defp arg_name_from_pattern(_other, idx), do: "arg#{idx}"

  defp struct_var_hint(map_ast) do
    # Try to infer a meaningful name from struct patterns like:
    #   %User{id: host_id} => "host"
    #   %User{id: target_id} => "target"
    case map_ast do
      {:%{}, _m, kvs} when is_list(kvs) ->
        kvs
        |> Enum.find_value(fn
          {:id, {var, _m2, _c2}} when is_atom(var) -> var
          _ -> nil
        end)
        |> case do
          nil ->
            nil

          var when is_atom(var) ->
            var
            |> Atom.to_string()
            |> String.trim_leading("_")
            |> String.trim_trailing("_id")
        end

      _ ->
        nil
    end
  end

  defp ensure_unique_arg_names(arg_names) when is_list(arg_names) do
    {uniq, _counts} =
      Enum.map_reduce(arg_names, %{}, fn name, counts ->
        name = if is_binary(name) and name != "", do: name, else: "arg"
        count = Map.get(counts, name, 0) + 1
        counts = Map.put(counts, name, count)
        uniq = if count == 1, do: name, else: "#{name}#{count}"
        {uniq, counts}
      end)

    uniq
  end

  defp blank_to("", fallback), do: fallback
  defp blank_to(val, _fallback), do: val

  defp indent_doc(doc, spaces) when is_binary(doc) do
    indent = String.duplicate(" ", spaces)

    doc
    |> String.split("\n")
    |> Enum.map_join("\n", &(indent <> &1))
  end

  defp escape_doc(doc) when is_binary(doc) do
    # Prevent docs that include "\"\"\"" from terminating the heredoc in generated files.
    String.replace(doc, "\"\"\"", "\\\"\\\"\\\"")
  end

  defp escape_doc(_), do: ""
end
