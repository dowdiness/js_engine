window.BENCHMARK_DATA = {
  "lastUpdate": 1779806788449,
  "repoUrl": "https://github.com/dowdiness/js_engine",
  "entries": {
    "Benchmark": [
      {
        "commit": {
          "author": {
            "name": "Koji Ishimoto",
            "username": "dowdiness",
            "email": "koji.ishimoto@gmail.com"
          },
          "committer": {
            "name": "Koji Ishimoto",
            "username": "dowdiness",
            "email": "koji.ishimoto@gmail.com"
          },
          "id": "1e78b68688e97f252cd8db44dba3eb8dd4c898df",
          "message": "Add JS startup benchmark staging",
          "timestamp": "2026-05-26T09:01:43Z",
          "url": "https://github.com/dowdiness/js_engine/commit/1e78b68688e97f252cd8db44dba3eb8dd4c898df"
        },
        "date": 1779791089702,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "startup/startup/tiny_program",
            "value": 2.5521618532000003,
            "unit": "ms",
            "extra": "category=regression, cv=2.8%, noisy=false"
          },
          {
            "name": "frontend/lexer/small",
            "value": 0.0317288471000007,
            "unit": "ms",
            "extra": "category=regression, cv=22.9%, noisy=true"
          },
          {
            "name": "frontend/lexer/large",
            "value": 0.27155319040000103,
            "unit": "ms",
            "extra": "category=regression, cv=1.7%, noisy=false"
          },
          {
            "name": "execution/exec/fibonacci_30",
            "value": 18477.518264399994,
            "unit": "ms",
            "extra": "category=regression, cv=0.1%, noisy=false"
          },
          {
            "name": "execution/exec/property_chain",
            "value": 18.76678774999891,
            "unit": "ms",
            "extra": "category=regression, cv=7.3%, noisy=false"
          },
          {
            "name": "execution/exec/array_map_filter",
            "value": 24.913470600001165,
            "unit": "ms",
            "extra": "category=component, cv=13.0%, noisy=false"
          },
          {
            "name": "execution/exec/closure_factory",
            "value": 37.93905080000066,
            "unit": "ms",
            "extra": "category=component, cv=4.4%, noisy=false"
          },
          {
            "name": "execution/baseline/closure_conversion/closure_factory",
            "value": 18.148771483334226,
            "unit": "ms",
            "extra": "category=component, cv=7.9%, noisy=false"
          },
          {
            "name": "execution/exec/arithmetic_loop",
            "value": 851.31939912499,
            "unit": "ms",
            "extra": "category=component, cv=0.1%, noisy=false"
          },
          {
            "name": "execution/exec/object_construction",
            "value": 8.647614849999567,
            "unit": "ms",
            "extra": "category=component, cv=5.3%, noisy=false"
          },
          {
            "name": "execution/exec/string_ops",
            "value": 3.339499360000191,
            "unit": "ms",
            "extra": "category=component, cv=7.4%, noisy=false"
          },
          {
            "name": "frontend/pipeline/exec/lex",
            "value": 0.027028857133341563,
            "unit": "ms",
            "extra": "category=workflow, cv=0.4%, noisy=false"
          },
          {
            "name": "frontend/pipeline/exec/parse",
            "value": 0.02593137317499968,
            "unit": "ms",
            "extra": "category=workflow, cv=4.1%, noisy=false"
          },
          {
            "name": "execution/pipeline/exec/evaluate",
            "value": 33.73886359999888,
            "unit": "ms",
            "extra": "category=workflow, cv=10.4%, noisy=false"
          },
          {
            "name": "execution/pipeline/closure_conversion/evaluate",
            "value": 12.972452320000741,
            "unit": "ms",
            "extra": "category=workflow, cv=7.6%, noisy=false"
          },
          {
            "name": "frontend/pipeline/parse_heavy",
            "value": 0.47472249066670574,
            "unit": "ms",
            "extra": "category=workflow, cv=5.7%, noisy=false"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "name": "Ishimoto Koji",
            "username": "dowdiness",
            "email": "koji.ishimoto@gmail.com"
          },
          "committer": {
            "name": "GitHub",
            "username": "web-flow",
            "email": "noreply@github.com"
          },
          "id": "73a81758bc1bcf7497825c18ed0869b7b381faf3",
          "message": "Add JS startup benchmark staging (#154)",
          "timestamp": "2026-05-26T14:39:30Z",
          "url": "https://github.com/dowdiness/js_engine/commit/73a81758bc1bcf7497825c18ed0869b7b381faf3"
        },
        "date": 1779806787476,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "startup/startup/tiny_program",
            "value": 2.5199996844,
            "unit": "ms",
            "extra": "category=regression, cv=2.7%, noisy=false"
          },
          {
            "name": "frontend/lexer/small",
            "value": 0.03179153540000023,
            "unit": "ms",
            "extra": "category=regression, cv=19.5%, noisy=true"
          },
          {
            "name": "frontend/lexer/large",
            "value": 0.26887878920000224,
            "unit": "ms",
            "extra": "category=regression, cv=4.9%, noisy=false"
          },
          {
            "name": "execution/exec/fibonacci_30",
            "value": 18118.0018664,
            "unit": "ms",
            "extra": "category=regression, cv=0.4%, noisy=false"
          },
          {
            "name": "execution/exec/property_chain",
            "value": 19.18037424999784,
            "unit": "ms",
            "extra": "category=regression, cv=8.0%, noisy=false"
          },
          {
            "name": "execution/exec/array_map_filter",
            "value": 25.256127100004232,
            "unit": "ms",
            "extra": "category=component, cv=13.2%, noisy=false"
          },
          {
            "name": "execution/exec/closure_factory",
            "value": 40.05468106666716,
            "unit": "ms",
            "extra": "category=component, cv=5.1%, noisy=false"
          },
          {
            "name": "execution/baseline/closure_conversion/closure_factory",
            "value": 19.44868771666612,
            "unit": "ms",
            "extra": "category=component, cv=5.8%, noisy=false"
          },
          {
            "name": "execution/exec/arithmetic_loop",
            "value": 831.849402625001,
            "unit": "ms",
            "extra": "category=component, cv=1.0%, noisy=false"
          },
          {
            "name": "execution/exec/object_construction",
            "value": 8.974823649999841,
            "unit": "ms",
            "extra": "category=component, cv=4.1%, noisy=false"
          },
          {
            "name": "execution/exec/string_ops",
            "value": 3.469438250000239,
            "unit": "ms",
            "extra": "category=component, cv=7.5%, noisy=false"
          },
          {
            "name": "frontend/pipeline/exec/lex",
            "value": 0.027124610866672207,
            "unit": "ms",
            "extra": "category=workflow, cv=0.8%, noisy=false"
          },
          {
            "name": "frontend/pipeline/exec/parse",
            "value": 0.02548473109999904,
            "unit": "ms",
            "extra": "category=workflow, cv=3.5%, noisy=false"
          },
          {
            "name": "execution/pipeline/exec/evaluate",
            "value": 34.5021149999986,
            "unit": "ms",
            "extra": "category=workflow, cv=10.5%, noisy=false"
          },
          {
            "name": "execution/pipeline/closure_conversion/evaluate",
            "value": 13.868522800000212,
            "unit": "ms",
            "extra": "category=workflow, cv=7.1%, noisy=false"
          },
          {
            "name": "frontend/pipeline/parse_heavy",
            "value": 0.48684197799995316,
            "unit": "ms",
            "extra": "category=workflow, cv=8.1%, noisy=false"
          }
        ]
      }
    ]
  }
}