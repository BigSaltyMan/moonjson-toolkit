# frontend

The statistics dashboard: a [Rabbita](https://github.com/moonbit-community/rabbita)
app that reads the file `moonjson-toolkit --json-out` writes and draws it with
Apache ECharts.

`main/main.mbt` holds the whole app — the model, the update function and the
view. It fetches `./stats.json`, renders the headline numbers and the type
table, and then calls into `public/charts.js` to draw the two charts outside the
virtual DOM. `public/echarts.min.js` is vendored so the page works offline.

## Run in development

Write the data the page reads, then start the dev server with live reload:

```sh
moon run ../cmd/main -- -f ../test.json --json-out public/stats.json
warren dev --browser-entry main
```

Open the local URL warren prints.

## Build a release bundle

```sh
moon run ../cmd/main -- -f ../test.json --json-out public/stats.json
warren build --browser-entry main
python3 -m http.server 8000 --directory dist
```

The page is served from `dist/`, so it must be opened over HTTP rather than as
a `file://` path — the browser will not let it fetch `stats.json` otherwise.

## Tests

```sh
moon test --target js
```

The tests decode a sample of the CLI's output, so a rename of a field in
`stats.mbt` fails here rather than silently emptying the charts.
