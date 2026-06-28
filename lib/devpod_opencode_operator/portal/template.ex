defmodule DevpodOpencodeOperator.Portal.Template do
  @moduledoc """
  Renders the portal HTML for a list of OpenCode Endpoints.

  Each endpoint is a map with `:url` (the user-facing URL) and
  `:workspace_id` (the display text). The template is compiled once
  at compile time via `EEx.function_from_string/5`.
  """

  require EEx

  EEx.function_from_string(
    :def,
    :render,
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>OpenCode Endpoints</title>
      <style>
        body { font-family: system-ui, -apple-system, sans-serif; margin: 2rem; color: #222; }
        h1 { font-weight: 500; margin-bottom: 1.5rem; }
        .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 1rem; }
        .card { display: block; padding: 1.25rem 1rem; border: 1px solid #ddd; border-radius: 8px; text-decoration: none; color: #222; background: #fff; }
        .card:hover { border-color: #888; }
        .card .id { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; word-break: break-all; }
        .empty { color: #666; font-style: italic; }
      </style>
    </head>
    <body>
      <h1>OpenCode Endpoints</h1>
      <div class="grid">
      <%= for endpoint <- endpoints do %>
        <a class="card" href="<%= endpoint.url %>"><span class="id"><%= endpoint.workspace_id %></span></a>
      <% end %>
      <%= if endpoints == [] do %>
        <p class="empty">No OpenCode Endpoints found.</p>
      <% end %>
      </div>
    </body>
    </html>
    """,
    [:endpoints]
  )
end
