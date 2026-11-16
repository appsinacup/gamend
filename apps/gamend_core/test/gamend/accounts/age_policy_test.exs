defmodule Gamend.Accounts.AgePolicyTest do
  @moduledoc """
  The age brackets and what they permit.

  This module encodes legal thresholds rather than product preferences, so the
  tests are written against the rules themselves — the same age landing in
  different brackets in different countries, the two published tables that are
  commonly wrong, and the direction an age is allowed to move.
  """
  use ExUnit.Case, async: true

  alias Gamend.Accounts.AgePolicy
  alias Gamend.Accounts.User

  defp user(attrs), do: struct(User, attrs)

  describe "digital consent ages" do
    test "an unlisted country gets the highest threshold, not the most convenient" do
      assert AgePolicy.digital_consent_age("ZZ") == 16
      assert AgePolicy.digital_consent_age(nil) == 16
      # Deliberately absent — the research could not verify them, and a guess
      # here would be worse than the conservative default.
      assert AgePolicy.digital_consent_age("NO") == 16
      assert AgePolicy.digital_consent_age("IS") == 16
    end

    test "the two thresholds published tables usually get wrong" do
      # ZVOP-2, in force 26 January 2023. Most tables still say 16.
      assert AgePolicy.digital_consent_age("SI") == 15
      # 14 today, but a draft Organic Law would raise it — re-check periodically.
      assert AgePolicy.digital_consent_age("ES") == 14
    end

    test "a representative spread" do
      assert AgePolicy.digital_consent_age("GB") == 13
      assert AgePolicy.digital_consent_age("US") == 13
      assert AgePolicy.digital_consent_age("IT") == 14
      assert AgePolicy.digital_consent_age("FR") == 15
      assert AgePolicy.digital_consent_age("RO") == 16
      assert AgePolicy.digital_consent_age("DE") == 16
    end

    test "the lookup is case-insensitive" do
      assert AgePolicy.digital_consent_age("ro") == AgePolicy.digital_consent_age("RO")
    end
  end

  describe "class_for_age/2" do
    test "the same age is a teen in one country and a child in another" do
      # The whole reason the country is stored. 14 clears the US threshold of
      # 13 and does not clear Romania's 16.
      assert AgePolicy.class_for_age(14, "US") == :teen
      assert AgePolicy.class_for_age(14, "RO") == :child
    end

    test "child is the higher of 13 and the country's age, never the lower" do
      # A country below 13 could not lower the COPPA floor even if one existed.
      assert AgePolicy.class_for_age(12, "GB") == :child
      assert AgePolicy.class_for_age(13, "GB") == :teen
    end

    test "18 is adult everywhere" do
      for country <- ["US", "GB", "RO", "DE", "ZZ"] do
        assert AgePolicy.class_for_age(18, country) == :adult
        assert AgePolicy.class_for_age(17, country) in [:teen, :child]
      end
    end
  end

  describe "age_in_years/3" do
    test "rolls on the first of the birth month, so it never reports an account younger" do
      # Born June 2010, asked in May 2026: not yet 16.
      assert AgePolicy.age_in_years(2010, 6, ~D[2026-05-31]) == 15
      # ...and on the 1st of June, 16. Conservative by up to 30 days: someone
      # born 30 June is treated as having had their birthday on the 1st, so the
      # age errs high, never low.
      assert AgePolicy.age_in_years(2010, 6, ~D[2026-06-01]) == 16
    end
  end

  describe "effective_class/2 and grandfathering" do
    test "a new account with no age is a child, not an adult" do
      assert AgePolicy.effective_class(user(%{})) == :child
    end

    test "an account predating the gate keeps adult capability until it answers" do
      legacy = user(%{grandfathered_at: DateTime.utc_now()})
      assert AgePolicy.classify(legacy) == :unknown
      assert AgePolicy.grandfathered?(legacy)
      assert AgePolicy.effective_class(legacy) == :adult
    end

    test "answering ends the grandfathering, and the answer governs" do
      answered =
        user(%{
          grandfathered_at: DateTime.utc_now(),
          birth_year: 2016,
          birth_month: 1,
          age_country: "RO"
        })

      refute AgePolicy.grandfathered?(answered)
      assert AgePolicy.effective_class(answered, ~D[2026-08-20]) == :child
    end
  end

  describe "policy_for/1" do
    test "the struct defaults are the child defaults" do
      # A field nobody remembered to set must be closed, not open.
      bare = %AgePolicy{}
      refute bare.discoverable?
      refute bare.public_groups?
      refute bare.purchases?
      refute bare.chat_default_on?
      assert bare.leaderboard_identity == :pseudonym
    end

    test "unknown is treated exactly as child" do
      assert %{AgePolicy.policy_for(:unknown) | class: :child} == AgePolicy.policy_for(:child)
    end

    test "children are undiscoverable, cannot reach public groups, and cannot spend" do
      p = AgePolicy.policy_for(:child)
      refute p.discoverable?
      refute p.public_groups?
      refute p.purchases?
      refute p.custom_display_name?
      refute p.third_party_egress?
      refute p.map_presence_published?
      assert p.leaderboard_identity == :pseudonym
    end

    test "teens are discoverable but chat is off by default" do
      p = AgePolicy.policy_for(:teen)
      assert p.discoverable?
      assert p.public_groups?
      assert p.purchases?
      # FTC v Epic: off by default for children *and teens*, charged as an FTC
      # Act unfairness violation independent of COPPA.
      refute p.chat_default_on?
    end

    test "adults get everything" do
      p = AgePolicy.policy_for(:adult)
      assert p.discoverable?
      assert p.chat_default_on?
      assert p.purchases?
      assert p.leaderboard_identity == :real_name
    end
  end

  describe "may_change_age?/4" do
    setup do
      %{
        teen:
          user(%{
            birth_year: 2012,
            birth_month: 1,
            age_country: "US",
            age_method: "self_declared"
          })
      }
    end

    test "a first answer is always allowed" do
      assert AgePolicy.may_change_age?(user(%{}), 1990, 5, "self_declared")
    end

    test "lowering your age is always allowed", %{teen: teen} do
      assert AgePolicy.may_change_age?(teen, 2020, 1, "self_declared")
    end

    test "raising it on the same kind of signal is refused", %{teen: teen} do
      # The rule that stops a user answering their way out of a restriction in
      # the session that created it.
      refute AgePolicy.may_change_age?(teen, 1990, 1, "self_declared")
    end

    test "raising it on a stronger signal is allowed", %{teen: teen} do
      assert AgePolicy.may_change_age?(teen, 1990, 1, "platform_signal")
      assert AgePolicy.may_change_age?(teen, 1990, 1, "verified")
    end

    test "a stronger signal cannot be undone by a weaker one" do
      verified =
        user(%{birth_year: 2012, birth_month: 1, age_country: "US", age_method: "verified"})

      refute AgePolicy.may_change_age?(verified, 1990, 1, "platform_signal")
      refute AgePolicy.may_change_age?(verified, 1990, 1, "self_declared")
    end
  end

  describe "signal strength" do
    test "is ordered weakest to strongest" do
      assert AgePolicy.methods() == [
               "self_declared",
               "platform_signal",
               "guardian_declared",
               "verified"
             ]
    end

    test "an unrecognised method is weaker than everything" do
      refute AgePolicy.stronger_signal?("made_up", "self_declared")
      assert AgePolicy.stronger_signal?("self_declared", "made_up")
    end
  end

  describe "known_countries/0" do
    test "lists only countries the table actually answers for" do
      countries = AgePolicy.known_countries()

      assert is_list(countries)
      assert countries != []

      # Every listed code must be a two-letter uppercase code the lookup knows,
      # otherwise an admin picker built from this list offers a country whose
      # threshold silently falls back to the default.
      for code <- countries do
        assert code =~ ~r/^[A-Z]{2}$/, "#{inspect(code)} is not an upcased ISO-3166 alpha-2 code"
        assert is_integer(AgePolicy.digital_consent_age(code))
      end
    end

    test "an unlisted country falls back to the strictest default" do
      refute "ZZ" in AgePolicy.known_countries()
      assert AgePolicy.digital_consent_age("ZZ") == 16
    end
  end
end
