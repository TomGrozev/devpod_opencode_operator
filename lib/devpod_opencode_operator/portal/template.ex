defmodule DevpodOpencodeOperator.Portal.Template do
  @moduledoc """
  Renders the portal HTML for a list of OpenCode Endpoints.

  Each endpoint is a map with `:url` (the user-facing URL),
  `:workspace_id` (the friendly display name), and optionally
  `:workspace_uid` (a subline showing the underlying devpod UID).
  The template is compiled once at compile time via
  `EEx.function_from_string/5`.

  Theme: Nord Polar Night base + Frost cyan accents, with a small
  "traffic light" decoration on each card (the signature element —
  a nod to the terminal/editor vocabulary of the audience).
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
        :root {
          --bg: #2e3440;
          --surface: #3b4252;
          --surface-hi: #434c5e;
          --border: #434c5e;
          --border-hi: #88c0d0;
          --fg: #eceff4;
          --fg-muted: #d8dee9;
          --fg-dim: #81a1c1;
          --aurora-red: #bf616a;
          --aurora-yellow: #ebcb8b;
          --aurora-green: #a3be8c;
        }
        * { box-sizing: border-box; }
        body {
          font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
          background: var(--bg);
          color: var(--fg);
          margin: 0;
          padding: 3rem 1.5rem;
          min-height: 100vh;
          line-height: 1.5;
          -webkit-font-smoothing: antialiased;
        }
        main { max-width: 64rem; margin: 0 auto; }
        header { margin-bottom: 2.5rem; }
        h1 {
          font-size: 1.75rem;
          font-weight: 600;
          letter-spacing: -0.01em;
          margin: 0 0 0.25rem;
          color: var(--fg);
        }
        .meta {
          font-size: 0.875rem;
          color: var(--fg-dim);
          margin: 0;
          font-variant-numeric: tabular-nums;
        }
        .grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(15rem, 1fr));
          gap: 1rem;
        }
        .card {
          display: block;
          position: relative;
          padding: 2.25rem 1.25rem 1.25rem;
          background: var(--surface);
          border: 1px solid var(--border);
          border-radius: 0.5rem;
          text-decoration: none;
          color: var(--fg);
          transition: border-color 120ms ease, transform 120ms ease, background 120ms ease;
        }
        .card:hover, .card:focus-visible {
          border-color: var(--border-hi);
          background: var(--surface-hi);
          transform: translateY(-1px);
          outline: none;
        }
        .lights {
          position: absolute;
          top: 0.85rem;
          left: 1rem;
          display: flex;
          gap: 0.4rem;
        }
        .lights span {
          width: 0.6rem;
          height: 0.6rem;
          border-radius: 50%;
          display: block;
        }
        .lights .r { background: var(--aurora-red); }
        .lights .y { background: var(--aurora-yellow); }
        .lights .g { background: var(--aurora-green); }
        .card .id {
          display: block;
          font-family: ui-monospace, SFMono-Regular, "JetBrains Mono", "Fira Code", Menlo, monospace;
          font-size: 0.95rem;
          color: var(--fg);
          word-break: break-all;
        }
        .card .uid {
          display: block;
          font-family: ui-monospace, SFMono-Regular, "JetBrains Mono", "Fira Code", Menlo, monospace;
          font-size: 0.75rem;
          color: var(--fg-dim);
          margin-top: 0.25rem;
          word-break: break-all;
          letter-spacing: 0.01em;
        }
        .empty {
          color: var(--fg-dim);
          font-style: italic;
          padding: 2rem 0;
          text-align: center;
          grid-column: 1 / -1;
        }
        @media (max-width: 30rem) {
          body { padding: 2rem 1rem; }
          h1 { font-size: 1.5rem; }
        }
        @media (prefers-reduced-motion: reduce) {
          .card { transition: none; }
          .card:hover, .card:focus-visible { transform: none; }
        }
      </style>
    </head>
    <body>
      <main>
        <header>
          <h1>OpenCode Endpoints</h1>
          <% count = length(endpoints) %>
          <% plural = if count == 1, do: "", else: "s" %>
          <p class="meta">
            <%= if count == 0 do %>
              No active sessions
            <% else %>
              <%= count %> active session<%= plural %>
            <% end %>
          </p>
        </header>
        <div class="grid">
        <%= for endpoint <- endpoints do %>
          <a class="card" href="<%= endpoint.url %>" aria-label="Open <%= endpoint.workspace_id %>">
            <span class="lights" aria-hidden="true">
              <span class="r"></span>
              <span class="y"></span>
              <span class="g"></span>
            </span>
            <span class="id"><%= endpoint.workspace_id %></span>
            <%= if workspace_uid = Map.get(endpoint, :workspace_uid) do %>
              <span class="uid"><%= workspace_uid %></span>
            <% end %>
          </a>
        <% end %>
        <%= if endpoints == [] do %>
          <p class="empty">No OpenCode Endpoints found.</p>
        <% end %>
        </div>
      </main>
    </body>
    </html>
    """,
    [:endpoints]
  )
end
