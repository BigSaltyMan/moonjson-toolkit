///|
using @html {
  button,
  code,
  div,
  footer,
  fragment,
  h1,
  h2,
  header,
  p,
  section,
  span,
  table,
  tbody,
  td,
  text,
  th,
  thead,
  tr,
}

///|
using @rabbita {type Html, type Val}

///|
/// The statistics file, served next to the page. Produce it with
/// `moonjson-toolkit --json-out frontend/public/stats.json < your.json`.
let stats_url : String = "./stats.json"

///|
/// Hand the report to the ECharts bindings in `public/charts.js`.
extern "js" fn draw_charts(report_json : String) -> Unit =
  #| (report_json) => { window.moonjsonCharts.draw(report_json); }

///|
/// Drop the charts when there is nothing to show.
extern "js" fn clear_charts() -> Unit =
  #| () => { window.moonjsonCharts.clear(); }

///|
/// One row of the per-type node distribution.
struct KindCount {
  kind : String
  count : Int
} derive(FromJson, ToJson, Eq)

///|
/// One row of the top-level key counts.
struct NameCount {
  name : String
  count : Int
} derive(FromJson, ToJson, Eq)

///|
/// One row of the nesting-depth distribution.
struct DepthCount {
  depth : Int
  count : Int
} derive(FromJson, ToJson, Eq)

///|
/// The report `moonjson-toolkit --json-out` writes, mirrored field for field.
struct StatsReport {
  total_keys : Int
  total_nodes : Int
  max_depth : Int
  type_counts : Array[KindCount]
  key_counts : Array[NameCount]
  depth_counts : Array[DepthCount]
} derive(FromJson, ToJson, Eq)

///|
/// What the page knows about the statistics file.
enum Load {
  Loading
  Ready(StatsReport)
  Failed(String)
} derive(Eq)

///|
/// Everything the page can react to.
enum Msg {
  Loaded(Result[StatsReport, Error])
  Retry
}

///|
/// Ask the dev server for the statistics file.
fn fetch_stats(emit : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @http.get(stats_url).expect_json(emit.map(fn(result) { Loaded(result) }))
}

///|
/// Start by loading, and fetch immediately.
fn load_stats(emit : @cmd.Emit[Msg]) -> (Load, @cmd.Cmd) {
  (Loading, fetch_stats(emit))
}

///|
fn update(_model : Load, msg : Msg, emit : @cmd.Emit[Msg]) -> (Load, @cmd.Cmd) {
  match msg {
    Loaded(Ok(report)) =>
      (
        Ready(report),
        // The charts live outside the virtual DOM, so they are drawn once the
        // data is known rather than during rendering.
        @cmd.effect(fn() noraise {
          draw_charts(@json.to_json(report).stringify())
        }),
      )
    Loaded(Err(error)) =>
      (
        Failed(@debug.to_string(error)),
        @cmd.effect(fn() noraise { clear_charts() }),
      )
    Retry => (Loading, fetch_stats(emit))
  }
}

///|
/// One headline number.
fn stat_card(label : String, value : Int) -> Html {
  div(class="card") <| [
    span(class="card-value", value.to_string()),
    span(class="card-label", label),
  ]
}

///|
/// The per-type node distribution, straight from the report.
fn type_table(counts : Array[KindCount]) -> Html {
  table(class="type-table") <| [
    thead(tr([th("Type"), th(class="numeric", "Nodes")])),
    tbody(
      counts.map(fn(entry) {
        tr <| [
          td(code(entry.kind)),
          td(class="numeric", entry.count.to_string()),
        ]
      }),
    ),
  ]
}

///|
/// The dashboard itself, once the report has arrived.
fn report_view(report : StatsReport) -> Html {
  fragment([
    section(class="cards") <| [
      stat_card("Total keys", report.total_keys),
      stat_card("Total nodes", report.total_nodes),
      stat_card("Max depth", report.max_depth),
    ],
    section(class="charts") <| [
      div(id="key-chart", class="chart", ""),
      div(id="depth-chart", class="chart", ""),
    ],
    section(class="panel") <| [
      h2(class="panel-title", "Type distribution"),
      type_table(report.type_counts),
    ],
    // `charts.js` writes into this line when a chart cannot be drawn.
    p(id="chart-status", class="status", ""),
  ])
}

///|
/// What to show before, instead of, or after the report.
fn body(model : Load, emit : @cmd.Emit[Msg]) -> Html {
  match model {
    Loading => p(class="status", "Loading stats.json ...")
    Failed(message) =>
      div(class="panel panel-error") <| [
        h2(class="panel-title", "Cannot load stats.json"),
        p(class="error-detail", message),
        p(class="error-hint") <| [
          text("Write the file first with "),
          code(
            "moonjson-toolkit --json-out frontend/public/stats.json your.json",
          ),
          text("."),
        ],
        button(class="retry", on_click=emit(Retry), "Try again"),
      ]
    Ready(report) => report_view(report)
  }
}

///|
fn page(model : Load, emit : @cmd.Emit[Msg]) -> Html {
  div(class="page") <| [
    header(class="masthead") <| [
      h1(class="masthead-title", "MoonJSON Toolkit"),
      p(class="masthead-lead") <| [
        text("Key counts and nesting depth, read from the file that "),
        code("--json-out"),
        text(" wrote."),
      ],
    ],
    body(model, emit),
    footer(class="footer") <| [
      text("Charts drawn with Apache ECharts from "),
      code("stats.json"),
      text("."),
    ],
  ]
}

///|
fn app() -> Val[Html] {
  let (model, emit) = @rabbita.create_state_with_init(init=load_stats, update~)
  model.view(fn(load) { page(load, emit) })
}

///|
fn main {
  @rabbita.new(app).mount("app")
}
