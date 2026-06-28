defmodule DevpodOpencodeOperator.Portal.TemplateTest do
  use ExUnit.Case, async: true

  alias DevpodOpencodeOperator.Portal.Template

  describe "render/1 — empty state" do
    test "shows empty-state message when endpoints list is empty" do
      html = Template.render([])

      assert html =~ "No OpenCode Endpoints found."
    end

    test "returns a complete HTML document for empty state" do
      html = Template.render([])

      assert html =~ "<!DOCTYPE html>"
      assert html =~ "<html"
      assert html =~ "</html>"
    end
  end

  describe "render/1 — populated state" do
    test "renders one anchor card per endpoint with href and workspace id text" do
      html =
        Template.render([
          %{url: "https://abc123.example.com", workspace_id: "abc123"}
        ])

      assert html =~ ~s(href="https://abc123.example.com")
      assert html =~ "abc123"
    end

    test "renders multiple endpoints in the order given" do
      html =
        Template.render([
          %{url: "https://z.example.com", workspace_id: "z-id"},
          %{url: "https://a.example.com", workspace_id: "a-id"}
        ])

      z_pos = :binary.match(html, "z-id") |> elem(0)
      a_pos = :binary.match(html, "a-id") |> elem(0)

      assert z_pos < a_pos
    end

    test "does NOT show empty-state message when endpoints are present" do
      html =
        Template.render([
          %{url: "https://abc.example.com", workspace_id: "abc"}
        ])

      refute html =~ "No OpenCode Endpoints found."
    end
  end
end
