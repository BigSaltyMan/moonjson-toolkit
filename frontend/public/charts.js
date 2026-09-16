// ECharts bindings for the MoonJSON statistics dashboard.
//
// The MoonBit side (main.mbt) fetches `stats.json`, renders the page, and then
// calls `window.moonjsonCharts.draw(text)` once the data is in the model. This
// file owns everything about ECharts: loading the library, waiting for the
// containers to exist, and keeping the charts in step with the window size.
(function () {
  "use strict";

  // `public/echarts.min.js` is vendored next to this file, so the dashboard
  // works offline. The CDN is only a fallback for a checkout that is missing
  // the vendored bundle.
  var ECHARTS_CDN =
    "https://cdn.jsdelivr.net/npm/echarts@5.6.0/dist/echarts.min.js";

  var CONTAINER_TIMEOUT_MS = 5000;

  var barChart = null;
  var pieChart = null;
  var echartsPromise = null;
  var resizeBound = false;

  function status(message) {
    var el = document.getElementById("chart-status");
    if (el) {
      el.textContent = message;
    }
  }

  function loadScript(src) {
    return new Promise(function (resolve, reject) {
      var el = document.createElement("script");
      el.src = src;
      el.onload = function () {
        resolve();
      };
      el.onerror = function () {
        reject(new Error("cannot load " + src));
      };
      document.head.appendChild(el);
    });
  }

  function ensureEcharts() {
    if (window.echarts) {
      return Promise.resolve(window.echarts);
    }
    if (!echartsPromise) {
      echartsPromise = loadScript(ECHARTS_CDN).then(function () {
        return window.echarts;
      });
    }
    return echartsPromise;
  }

  // Rabbita mounts the app asynchronously, so a container may not exist yet
  // when the data arrives. Poll until it shows up rather than assuming an
  // ordering we do not control.
  function waitFor(id, timeoutMs) {
    return new Promise(function (resolve) {
      var deadline = Date.now() + timeoutMs;
      function poll() {
        var el = document.getElementById(id);
        if (el) {
          resolve(el);
        } else if (Date.now() > deadline) {
          resolve(null);
        } else {
          window.requestAnimationFrame(poll);
        }
      }
      poll();
    });
  }

  function mount(existing, element, option) {
    var chart = existing && !existing.isDisposed() ? existing : null;
    if (!chart || chart.getDom() !== element) {
      if (chart) {
        chart.dispose();
      }
      chart = window.echarts.init(element);
    }
    // `notMerge` keeps a redraw from accumulating stale series.
    chart.setOption(option, true);
    return chart;
  }

  function depthAxisLabel(depth) {
    return "depth " + depth;
  }

  function barOption(stats) {
    // A field that holds no nested keys can only ever draw a zero-height bar,
    // so it is left out: the chart answers "which fields carry structure", and
    // a row of empty bars answers it worse than no bars at all.
    var keys = (stats.key_counts || []).filter(function (entry) {
      return entry.count > 0;
    });
    return {
      title: {
        text: "Key counts",
        subtext:
          keys.length === 0
            ? "no field holds nested keys"
            : "keys in each top-level field",
        left: "center",
      },
      tooltip: { trigger: "axis", axisPointer: { type: "shadow" } },
      grid: { left: 16, right: 24, bottom: 16, top: 72, containLabel: true },
      xAxis: {
        type: "category",
        data: keys.map(function (entry) {
          return entry.name;
        }),
        axisLabel: {
          interval: 0,
          rotate: keys.length > 6 ? 30 : 0,
        },
      },
      yAxis: { type: "value", minInterval: 1 },
      series: [
        {
          name: "keys",
          type: "bar",
          barMaxWidth: 56,
          itemStyle: { color: "#4f7cff", borderRadius: [4, 4, 0, 0] },
          data: keys.map(function (entry) {
            return entry.count;
          }),
        },
      ],
    };
  }

  function pieOption(stats) {
    var depths = stats.depth_counts || [];
    return {
      title: {
        text: "Nesting depth",
        subtext: "nodes at each level",
        left: "center",
      },
      tooltip: { trigger: "item", formatter: "{b}: {c} nodes ({d}%)" },
      legend: { bottom: 0, icon: "circle" },
      series: [
        {
          name: "nodes",
          type: "pie",
          radius: ["42%", "68%"],
          center: ["50%", "52%"],
          avoidLabelOverlap: true,
          itemStyle: { borderColor: "#ffffff", borderWidth: 2 },
          label: { formatter: "{b}\n{c} nodes" },
          data: depths.map(function (entry) {
            return { name: depthAxisLabel(entry.depth), value: entry.count };
          }),
        },
      ],
    };
  }

  function resizeAll() {
    [barChart, pieChart].forEach(function (chart) {
      if (chart && !chart.isDisposed()) {
        chart.resize();
      }
    });
  }

  function draw(text) {
    var stats;
    try {
      stats = JSON.parse(text);
    } catch (error) {
      status("stats.json could not be parsed: " + error.message);
      return;
    }
    ensureEcharts()
      .then(function (echarts) {
        if (!echarts) {
          throw new Error("ECharts is unavailable");
        }
        return Promise.all([
          waitFor("key-chart", CONTAINER_TIMEOUT_MS),
          waitFor("depth-chart", CONTAINER_TIMEOUT_MS),
        ]);
      })
      .then(function (elements) {
        var barElement = elements[0];
        var pieElement = elements[1];
        var missing = [];
        if (barElement) {
          barChart = mount(barChart, barElement, barOption(stats));
        } else {
          missing.push("#key-chart");
        }
        if (pieElement) {
          pieChart = mount(pieChart, pieElement, pieOption(stats));
        } else {
          missing.push("#depth-chart");
        }
        if (missing.length > 0) {
          status("cannot find " + missing.join(" and "));
          return;
        }
        if (!resizeBound) {
          window.addEventListener("resize", resizeAll);
          resizeBound = true;
        }
        status("");
      })
      .catch(function (error) {
        status("charts could not be drawn: " + error.message);
      });
  }

  function clear() {
    [barChart, pieChart].forEach(function (chart) {
      if (chart && !chart.isDisposed()) {
        chart.dispose();
      }
    });
    barChart = null;
    pieChart = null;
  }

  window.moonjsonCharts = { draw: draw, clear: clear };
})();
