defmodule GamendWeb.ErrorJSONTest do
  use ExUnit.Case, async: true

  test "renders 404" do
    assert GamendWeb.ErrorJSON.render("404.json", %{}) == %{
             error: "not_found",
             message: "Not Found"
           }
  end

  test "renders 500" do
    assert GamendWeb.ErrorJSON.render("500.json", %{}) ==
             %{error: "internal_server_error", message: "Internal Server Error"}
  end
end
