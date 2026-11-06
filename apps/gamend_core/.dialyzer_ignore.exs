[
  # Ecto.Multi.new/0 currently expands to a MapSet-backed struct Dialyzer reports
  # as incompatible with Ecto.Multi's own specs on OTP 29 / Elixir 1.20.
  {"lib/gamend/groups.ex", "Type mismatch in call without opaque term in insert."},
  {"lib/gamend/lobbies.ex", :call_without_opaque},
  {"lib/gamend/groups/join_requests.ex", :call_without_opaque},
  # `use Mix.Task` emits this false positive in the generated task module.
  {"lib/mix/tasks/gen.sdk.ex", "The pattern can never match the type true."},
  # :public_key's spec says pkix_path_validation/3 only ever errors with
  # {:bad_cert, _}. The catch-all clause stays so an undocumented error shape
  # is a clean {:error, _} rather than a CaseClauseError in the payment path.
  {"lib/gamend/payments/providers/apple.ex", :pattern_match_cov}
]
