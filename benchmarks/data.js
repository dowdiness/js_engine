window.BENCHMARK_DATA = {
  "lastUpdate": 1780197363889,
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
          "id": "88bf3b801cb2572b59bc881102a7eb7e3d18bb2a",
          "message": "Skip unneeded bytecode arguments object setup (#172)",
          "timestamp": "2026-05-30T14:54:39Z",
          "url": "https://github.com/dowdiness/js_engine/commit/88bf3b801cb2572b59bc881102a7eb7e3d18bb2a"
        },
        "date": 1780188638923,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "startup/startup/tiny_program",
            "value": 2.9327739408000006,
            "unit": "ms",
            "extra": "category=regression, cv=3.1%, noisy=false"
          },
          {
            "name": "frontend/lexer/small",
            "value": 0.032071612900002024,
            "unit": "ms",
            "extra": "category=regression, cv=22.4%, noisy=true"
          },
          {
            "name": "frontend/lexer/large",
            "value": 0.2726860147999999,
            "unit": "ms",
            "extra": "category=regression, cv=7.9%, noisy=false"
          },
          {
            "name": "execution/exec/fibonacci_30",
            "value": 20698.8133462,
            "unit": "ms",
            "extra": "category=regression, cv=0.9%, noisy=false"
          },
          {
            "name": "execution/exec/property_chain",
            "value": 19.03794887500044,
            "unit": "ms",
            "extra": "category=regression, cv=5.4%, noisy=false"
          },
          {
            "name": "execution/exec/array_map_filter",
            "value": 28.000065299996642,
            "unit": "ms",
            "extra": "category=component, cv=15.2%, noisy=true"
          },
          {
            "name": "execution/exec/closure_factory",
            "value": 40.80674443333312,
            "unit": "ms",
            "extra": "category=component, cv=4.7%, noisy=false"
          },
          {
            "name": "execution/baseline/closure_conversion/closure_factory",
            "value": 39.691017483333425,
            "unit": "ms",
            "extra": "category=component, cv=7.5%, noisy=false"
          },
          {
            "name": "execution/baseline/bytecode/closure_factory",
            "value": 20.89668468333257,
            "unit": "ms",
            "extra": "category=component, cv=4.9%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/dispatch_stack",
            "value": 60.05496815555573,
            "unit": "ms",
            "extra": "category=component, cv=0.9%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/local_access",
            "value": 49.6488829777796,
            "unit": "ms",
            "extra": "category=component, cv=1.3%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/env_access",
            "value": 67.3337282666652,
            "unit": "ms",
            "extra": "category=component, cv=1.2%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/captured_access",
            "value": 57.31357606666472,
            "unit": "ms",
            "extra": "category=component, cv=0.8%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/call_frame",
            "value": 17.620243999998397,
            "unit": "ms",
            "extra": "category=component, cv=2.5%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/runtime_helpers",
            "value": 26.833941266667615,
            "unit": "ms",
            "extra": "category=component, cv=0.9%, noisy=false"
          },
          {
            "name": "execution/exec/arithmetic_loop",
            "value": 757.7080942499961,
            "unit": "ms",
            "extra": "category=component, cv=0.8%, noisy=false"
          },
          {
            "name": "execution/exec/object_construction",
            "value": 9.19145073333299,
            "unit": "ms",
            "extra": "category=component, cv=16.3%, noisy=true"
          },
          {
            "name": "execution/exec/string_ops",
            "value": 3.6558807199998404,
            "unit": "ms",
            "extra": "category=component, cv=9.7%, noisy=false"
          },
          {
            "name": "frontend/pipeline/exec/lex",
            "value": 0.027159118533336246,
            "unit": "ms",
            "extra": "category=workflow, cv=1.0%, noisy=false"
          },
          {
            "name": "frontend/pipeline/exec/parse",
            "value": 0.02608834146249901,
            "unit": "ms",
            "extra": "category=workflow, cv=5.6%, noisy=false"
          },
          {
            "name": "execution/pipeline/exec/evaluate",
            "value": 37.77844580000092,
            "unit": "ms",
            "extra": "category=workflow, cv=6.7%, noisy=false"
          },
          {
            "name": "execution/pipeline/closure_conversion/evaluate",
            "value": 35.958987379999016,
            "unit": "ms",
            "extra": "category=workflow, cv=4.1%, noisy=false"
          },
          {
            "name": "frontend/pipeline/bytecode/compile",
            "value": 0.021020910500005516,
            "unit": "ms",
            "extra": "category=workflow, cv=18.5%, noisy=true"
          },
          {
            "name": "execution/pipeline/bytecode/evaluate",
            "value": 16.297108880000017,
            "unit": "ms",
            "extra": "category=workflow, cv=7.0%, noisy=false"
          },
          {
            "name": "frontend/pipeline/parse_heavy",
            "value": 0.4915735113333211,
            "unit": "ms",
            "extra": "category=workflow, cv=6.9%, noisy=false"
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
          "id": "cc8acaf7530f35f13900a69bea5e082788567a9d",
          "message": "Redesign benchmark dashboard (#174)",
          "timestamp": "2026-05-31T02:59:44Z",
          "url": "https://github.com/dowdiness/js_engine/commit/cc8acaf7530f35f13900a69bea5e082788567a9d"
        },
        "date": 1780197363485,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "startup/startup/tiny_program",
            "value": 2.5504692884000004,
            "unit": "ms",
            "extra": "category=regression, cv=2.3%, noisy=false"
          },
          {
            "name": "frontend/lexer/small",
            "value": 0.03216671170000116,
            "unit": "ms",
            "extra": "category=regression, cv=34.9%, noisy=true"
          },
          {
            "name": "frontend/lexer/large",
            "value": 0.27066605640000124,
            "unit": "ms",
            "extra": "category=regression, cv=2.3%, noisy=false"
          },
          {
            "name": "execution/exec/fibonacci_30",
            "value": 18123.1649094,
            "unit": "ms",
            "extra": "category=regression, cv=0.4%, noisy=false"
          },
          {
            "name": "execution/exec/property_chain",
            "value": 18.352014125004644,
            "unit": "ms",
            "extra": "category=regression, cv=9.5%, noisy=false"
          },
          {
            "name": "execution/exec/array_map_filter",
            "value": 25.63160489999573,
            "unit": "ms",
            "extra": "category=component, cv=14.3%, noisy=false"
          },
          {
            "name": "execution/exec/closure_factory",
            "value": 37.5296159000005,
            "unit": "ms",
            "extra": "category=component, cv=5.8%, noisy=false"
          },
          {
            "name": "execution/baseline/closure_conversion/closure_factory",
            "value": 35.76563096666747,
            "unit": "ms",
            "extra": "category=component, cv=8.7%, noisy=false"
          },
          {
            "name": "execution/baseline/bytecode/closure_factory",
            "value": 19.236351450000555,
            "unit": "ms",
            "extra": "category=component, cv=5.0%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/dispatch_stack",
            "value": 56.64853657777808,
            "unit": "ms",
            "extra": "category=component, cv=1.0%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/local_access",
            "value": 46.048699177776385,
            "unit": "ms",
            "extra": "category=component, cv=1.0%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/env_access",
            "value": 66.23589766666733,
            "unit": "ms",
            "extra": "category=component, cv=0.5%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/captured_access",
            "value": 56.63469599999953,
            "unit": "ms",
            "extra": "category=component, cv=0.8%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/call_frame",
            "value": 17.214545466666138,
            "unit": "ms",
            "extra": "category=component, cv=1.6%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/runtime_helpers",
            "value": 24.59704775555486,
            "unit": "ms",
            "extra": "category=component, cv=0.6%, noisy=false"
          },
          {
            "name": "execution/exec/arithmetic_loop",
            "value": 813.4831226249953,
            "unit": "ms",
            "extra": "category=component, cv=0.3%, noisy=false"
          },
          {
            "name": "execution/exec/object_construction",
            "value": 8.461984600000628,
            "unit": "ms",
            "extra": "category=component, cv=6.4%, noisy=false"
          },
          {
            "name": "execution/exec/string_ops",
            "value": 3.365604470001126,
            "unit": "ms",
            "extra": "category=component, cv=8.0%, noisy=false"
          },
          {
            "name": "frontend/pipeline/exec/lex",
            "value": 0.02691120453332745,
            "unit": "ms",
            "extra": "category=workflow, cv=0.7%, noisy=false"
          },
          {
            "name": "frontend/pipeline/exec/parse",
            "value": 0.025642681887499564,
            "unit": "ms",
            "extra": "category=workflow, cv=3.2%, noisy=false"
          },
          {
            "name": "execution/pipeline/exec/evaluate",
            "value": 31.992158199998084,
            "unit": "ms",
            "extra": "category=workflow, cv=1.9%, noisy=false"
          },
          {
            "name": "execution/pipeline/closure_conversion/evaluate",
            "value": 31.686002199999347,
            "unit": "ms",
            "extra": "category=workflow, cv=4.6%, noisy=false"
          },
          {
            "name": "frontend/pipeline/bytecode/compile",
            "value": 0.02214187249999183,
            "unit": "ms",
            "extra": "category=workflow, cv=25.7%, noisy=true"
          },
          {
            "name": "execution/pipeline/bytecode/evaluate",
            "value": 13.681126840000797,
            "unit": "ms",
            "extra": "category=workflow, cv=6.4%, noisy=false"
          },
          {
            "name": "frontend/pipeline/parse_heavy",
            "value": 0.4723195573332875,
            "unit": "ms",
            "extra": "category=workflow, cv=7.6%, noisy=false"
          }
        ]
      }
    ]
  }
}