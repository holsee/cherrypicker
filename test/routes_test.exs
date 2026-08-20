defmodule Cherrypicker.RoutesTest do
  use ExUnit.Case, async: true

  alias Cherrypicker.Routes

  setup do
    start_supervised!(Routes)
    :ok
  end

  test "put, fetch, list, delete round-trip" do
    assert :ok = Routes.put("myapp", 4000)
    assert :ok = Routes.put("api.myapp", 4001)

    assert {:ok, 4000} = Routes.fetch("myapp")

    assert Routes.list() == [
             %{name: "api.myapp", port: 4001},
             %{name: "myapp", port: 4000}
           ]

    assert :ok = Routes.delete("myapp")
    assert :error = Routes.fetch("myapp")
  end

  test "re-registering a name replaces its port" do
    assert :ok = Routes.put("myapp", 4000)
    assert :ok = Routes.put("myapp", 5000)
    assert {:ok, 5000} = Routes.fetch("myapp")
  end

  test "the control host name is reserved" do
    assert {:error, message} = Routes.put("cherrypicker", 4000)
    assert message =~ "reserved"
  end

  test "names are DNS labels, not free text" do
    for bad <- ["My App", "UPPER", "-lead", "trail-", "dot..dot", "sp ace", ""] do
      assert {:error, message} = Routes.put(bad, 4000), "expected #{inspect(bad)} to be refused"
      assert message =~ "invalid name"
    end

    for good <- ["a", "my-app", "api.my-app", "a1.b2.c3"] do
      assert :ok = Routes.put(good, 4000)
    end
  end

  test "ports are validated" do
    assert {:error, message} = Routes.put("myapp", 0)
    assert message =~ "invalid port"
    assert {:error, _message} = Routes.put("myapp", 70_000)
  end
end
