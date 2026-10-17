defmodule Gamend.ReportsTest.WordKind do
  @moduledoc false
  @behaviour Gamend.Reports.Kind

  @impl true
  def key, do: "test_word"

  @impl true
  def topics, do: ~w(translation audio)

  @impl true
  def max_attachments, do: 0

  @impl true
  def cast(%{"subject" => %{"id" => id}, "data" => data}, _context) when is_binary(id) do
    {:ok,
     %{
       subject_ref: "w/" <> id,
       subject: %{"id" => id, "text" => "word #{id}"},
       data: Map.take(data, ["suggestion"])
     }}
  end

  def cast(_params, _context), do: {:error, :no_word}
end

defmodule Gamend.ReportsTest.Hooks do
  @moduledoc false
  def before_report_create(%{"description" => "spam"}), do: {:error, :spam}
  def before_report_create(attrs), do: {:ok, Map.put(attrs, "locale", attrs["locale"] || "xx")}

  def after_report_resolved(report) do
    send(:persistent_term.get({__MODULE__, :test_pid}), {:resolved, report.id, report.status})
    :ok
  end
end

defmodule Gamend.ReportsTest do
  use Gamend.DataCase, async: false

  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Notifications
  alias Gamend.Repo
  alias Gamend.Reports
  alias Gamend.Reports.Notices
  alias Gamend.Reports.Report
  alias Gamend.ReportsTest.Hooks
  alias Gamend.ReportsTest.WordKind
  alias Gamend.SettingsHelpers

  # A 1×1 PNG: the bytes are what is checked, so a real header matters.
  @png Base.decode64!(
         "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
       )

  setup do
    dir = Path.join(System.tmp_dir!(), "reports_test_#{System.unique_integer([:positive])}")
    old_storage = Application.get_env(:gamend_core, Gamend.Storage.Local)
    old_kinds = Application.get_env(:gamend_core, :report_kinds)
    old_hooks = Application.get_env(:gamend_core, :host_hook_modules)
    old_settings = Application.get_env(:gamend_core, Reports)

    Application.put_env(:gamend_core, Gamend.Storage.Local, dir: dir)
    Application.put_env(:gamend_core, :report_kinds, [WordKind])
    Application.put_env(:gamend_core, :host_hook_modules, [Hooks])
    :persistent_term.put({Hooks, :test_pid}, self())

    on_exit(fn ->
      File.rm_rf(dir)
      restore(Gamend.Storage.Local, old_storage)
      restore(:report_kinds, old_kinds)
      restore(:host_hook_modules, old_hooks)
      restore(Reports, old_settings)
      :persistent_term.erase({Hooks, :test_pid})
    end)

    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:gamend_core, key)
  defp restore(key, value), do: Application.put_env(:gamend_core, key, value)

  defp page(attrs \\ %{}) do
    Map.merge(
      %{"kind" => "page", "subject" => %{"path" => "/games"}, "description" => "It broke"},
      attrs
    )
  end

  defp word(id, attrs \\ %{}) do
    Map.merge(
      %{"kind" => "test_word", "topic" => "translation", "subject" => %{"id" => id}},
      attrs
    )
  end

  defp promote(user), do: user |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update!()

  describe "kinds" do
    test "core's page kind is always there, a configured kind beside it" do
      assert Enum.map(Reports.kinds(), & &1.key()) == ["test_word", "page"]
      assert Reports.kind("page") == Gamend.Reports.Kinds.Page
      assert Reports.kind("nope") == nil
    end

    test "a configured kind with the key page replaces core's" do
      defmodule MyPage do
        @behaviour Gamend.Reports.Kind
        def key, do: "page"
        def topics, do: []
        def max_attachments, do: 0
        def cast(_params, _context), do: {:ok, %{subject_ref: nil, subject: %{}, data: %{}}}
      end

      Application.put_env(:gamend_core, :report_kinds, [MyPage])
      assert Reports.kind("page") == MyPage
    end
  end

  describe "filing" do
    test "a visitor files a page report; it lands open, with no user" do
      assert {:ok, %Report{} = report} =
               Reports.create(page(), %{locale: "ro", client: %{"viewport" => "390×844"}})

      assert report.status == "open"
      assert report.kind == "page"
      assert report.user_id == nil
      assert report.subject == %{"path" => "/games"}
      assert report.subject_ref == "/games"
      assert report.client == %{"viewport" => "390×844"}
      assert report.source == "web"
    end

    test "a full URL is kept, query kept, fragment dropped, and keyed by its path" do
      {:ok, report} =
        Reports.create(page(%{"subject" => %{"path" => "http://localhost/tests/ro?x=1#top"}}))

      assert report.subject["path"] == "http://localhost/tests/ro?x=1"
      assert report.subject_ref == "/tests/ro"
    end

    test "a page report must say what happened" do
      assert {:error, :description_required} =
               Reports.create(page(%{"description" => "   "}))
    end

    test "an unknown kind and a topic the kind does not have are refused" do
      assert {:error, :unknown_kind} = Reports.create(%{"kind" => "nope"})
      assert {:error, :invalid_topic} = Reports.create(word("1", %{"topic" => "image"}))
      assert {:error, :invalid_topic} = Reports.create(word("1", %{"topic" => nil}))
      assert {:error, :invalid_topic} = Reports.create(page(%{"topic" => "x"}))
    end

    test "the kind checks the subject and keeps its own data" do
      assert {:error, :no_word} = Reports.create(word(nil, %{"subject" => %{}}))

      {:ok, report} =
        Reports.create(word("7", %{"data" => %{"suggestion" => "ardei gras", "junk" => "x"}}))

      assert report.subject_ref == "w/7"
      assert report.subject["text"] == "word 7"
      assert report.data == %{"suggestion" => "ardei gras"}
    end

    test "a bad email is refused, a blank one is dropped" do
      assert {:error, %Ecto.Changeset{}} = Reports.create(page(%{"email" => "not an email"}))
      assert {:ok, %Report{email: nil}} = Reports.create(page(%{"email" => " "}))
      assert {:ok, %Report{email: "a@b.co"}} = Reports.create(page(%{"email" => "a@b.co"}))
    end

    test "the before hook can refuse a report or change it" do
      assert {:error, :spam} = Reports.create(page(%{"description" => "spam"}))
      assert {:ok, %Report{locale: "xx"}} = Reports.create(page())
    end

    test "a signed-in reporter cannot file the same open report twice; a visitor can" do
      user = AccountsFixtures.user_fixture()

      assert {:ok, _} = Reports.create(word("3"), %{user_id: user.id})
      assert {:error, :already_reported} = Reports.create(word("3"), %{user_id: user.id})
      # Another topic on the same word is another report.
      assert {:ok, _} = Reports.create(word("3", %{"topic" => "audio"}), %{user_id: user.id})

      assert {:ok, _} = Reports.create(word("3"))
      assert {:ok, _} = Reports.create(word("3"))
    end

    test "the per-account and the global daily caps" do
      user = AccountsFixtures.user_fixture()
      SettingsHelpers.put(:gamend_core, Reports, :user_daily_limit, 1)

      assert {:ok, _} = Reports.create(page(), %{user_id: user.id})
      assert {:error, :user_daily_limit} = Reports.create(page(), %{user_id: user.id})

      SettingsHelpers.put(:gamend_core, Reports, :daily_limit, 2)
      assert {:ok, _} = Reports.create(page())
      assert {:error, :daily_limit} = Reports.create(page())
    end

    test "switched off, nothing is filed" do
      SettingsHelpers.put(:gamend_core, Reports, :enabled, false)
      assert {:error, :disabled} = Reports.create(page())
    end
  end

  describe "attachments" do
    test "an image is stored privately and read back by index" do
      {:ok, report} = Reports.create(page(), %{attachments: [@png]})

      assert [%{"key" => key, "type" => "image/png", "size" => size}] = Report.files(report)
      assert key == "reports/#{report.id}/1.png"
      assert size == byte_size(@png)
      refute Enum.any?(Gamend.Storage.public_prefixes(), &String.starts_with?(key, &1))

      assert {:ok, @png, "image/png"} = Reports.attachment(report, 1)
      assert {:error, :not_found} = Reports.attachment(report, 2)
    end

    test "not an image, too large, or too many are refused" do
      assert {:error, :attachment_type} = Reports.create(page(), %{attachments: ["<svg/>"]})

      SettingsHelpers.put(:gamend_core, Reports, :max_attachment_bytes, 10)
      assert {:error, :attachment_too_large} = Reports.create(page(), %{attachments: [@png]})

      SettingsHelpers.delete(:gamend_core, Reports, :max_attachment_bytes)

      assert {:error, :too_many_attachments} =
               Reports.create(page(), %{attachments: [@png, @png, @png, @png]})

      assert {:error, :too_many_attachments} =
               Reports.create(word("1"), %{attachments: [@png]})
    end
  end

  describe "the queue" do
    test "every admin hears that reports are waiting, as one standing alert" do
      admin = promote(AccountsFixtures.user_fixture())

      {:ok, _} = Reports.create(page())
      {:ok, _} = Reports.create(page())

      assert [alert] = Notifications.list_notifications_by_title(admin.id, Notices.admin_title())
      assert alert.content =~ "2 reports"
    end

    test "filters, text search and group counts" do
      {:ok, a} = Reports.create(word("1", %{"description" => "Wrong Sense"}))
      {:ok, _} = Reports.create(word("1"))
      {:ok, _} = Reports.create(word("2", %{"topic" => "audio"}))
      {:ok, _} = Reports.create(page())

      assert Reports.count(%{kind: "test_word"}) == 3
      assert Reports.count(%{"kind" => "test_word", "topic" => "audio"}) == 1
      assert [%Report{id: id}] = Reports.list(%{q: "wrong sense"})
      assert id == a.id

      groups = Reports.group_counts(Reports.list(%{kind: "test_word"}))
      assert groups[{"test_word", "translation", "w/1"}] == 2
      assert groups[{"test_word", "audio", "w/2"}] == 1
    end

    test "closing tells the reporter and the hook; reopening clears it" do
      user = AccountsFixtures.user_fixture()
      admin = promote(AccountsFixtures.user_fixture())
      {:ok, report} = Reports.create(word("5"), %{user_id: user.id})

      {:ok, closed} =
        Reports.resolve(report, "fixed", %{
          note: "fixed in the sheet",
          message: "Thanks, it is fixed.",
          resolved_by: admin.id
        })

      assert closed.status == "fixed"
      assert closed.resolved_by == admin.id
      assert closed.resolution_note == "fixed in the sheet"
      assert %DateTime{} = closed.resolved_at
      assert_receive {:resolved, id, "fixed"}, 1_000
      assert id == report.id

      assert [notice] =
               Notifications.list_notifications_by_title(user.id, Notices.reporter_title())

      assert notice.content == "Thanks, it is fixed."

      {:ok, reopened} = Reports.resolve(closed, "open")
      assert reopened.status == "open"
      assert reopened.resolved_at == nil
      refute_receive {:resolved, _, "open"}, 100
    end

    test "a blank message sends the reporter nothing" do
      user = AccountsFixtures.user_fixture()
      {:ok, report} = Reports.create(word("6"), %{user_id: user.id})
      {:ok, _} = Reports.resolve(report, "wontfix", %{message: " "})

      assert Notifications.list_notifications_by_title(user.id, Notices.reporter_title()) == []
    end

    test "deleting removes the images too" do
      {:ok, report} = Reports.create(page(), %{attachments: [@png]})
      {:ok, _} = Reports.delete(report)

      assert Reports.get(report.id) == nil
      assert {:error, _} = Gamend.Storage.get("reports/#{report.id}/1.png")
    end
  end

  describe "retention and erasure" do
    test "closed reports go after the window, open ones stay" do
      SettingsHelpers.put(:gamend_core, Reports, :retention_days, 30)
      {:ok, open} = Reports.create(page())
      {:ok, old} = Reports.create(page(), %{attachments: [@png]})
      {:ok, recent} = Reports.create(page())
      {:ok, old} = Reports.resolve(old, "fixed")
      {:ok, _} = Reports.resolve(recent, "fixed")

      long_ago = DateTime.add(DateTime.utc_now(:second), -31, :day)
      old |> Ecto.Changeset.change(resolved_at: long_ago) |> Repo.update!()

      assert Reports.prune() == 1
      assert Reports.get(old.id) == nil
      assert Reports.get(open.id)
      assert Reports.get(recent.id)
      assert {:error, _} = Gamend.Storage.get("reports/#{old.id}/1.png")
    end

    test "a deleted account takes its reports with it, a visitor's stay" do
      user = AccountsFixtures.user_fixture()
      {:ok, mine} = Reports.create(page(%{"email" => "me@x.co"}), %{user_id: user.id})
      {:ok, theirs} = Reports.create(page())

      {:ok, _} = Accounts.delete_user(user)

      assert Reports.get(mine.id) == nil
      assert Reports.get(theirs.id)
    end
  end
end
