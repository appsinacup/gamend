defmodule GamendWeb.Api.V1.ApiWrongTypesTest do
  @moduledoc """
  Every `/api` route, sent the wrong types, answers below 500
  (`GamendWeb.Testing.WrongTypes.api_tests/1`).
  """
  use GamendWeb.ConnCase, async: false
  require GamendWeb.Testing.WrongTypes, as: WrongTypes

  WrongTypes.api_tests()
end
