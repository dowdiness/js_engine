window.BENCHMARK_DATA = {
  "lastUpdate": 1780217384445,
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
          "id": "41d20d74392b55f65d9729ef75c5dc53402f90db",
          "message": "Show commit dates and compact benchmark dashboard (#175)\n\n* Show commit dates on benchmark charts\n\n* Compact benchmark dashboard mobile layout\n\n* Clarify benchmark dashboard copy\n\n* Minimize benchmark dashboard hero\n\n* Remove benchmark dashboard hero copy\n\n* Flatten benchmark dashboard header",
          "timestamp": "2026-05-31T05:56:59Z",
          "url": "https://github.com/dowdiness/js_engine/commit/41d20d74392b55f65d9729ef75c5dc53402f90db"
        },
        "date": 1780207294171,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "startup/startup/tiny_program",
            "value": 3.0808897079999995,
            "unit": "ms",
            "extra": "category=regression, cv=5.2%, noisy=false"
          },
          {
            "name": "frontend/lexer/small",
            "value": 0.028726946399998808,
            "unit": "ms",
            "extra": "category=regression, cv=23.2%, noisy=true"
          },
          {
            "name": "frontend/lexer/large",
            "value": 0.24884907919999968,
            "unit": "ms",
            "extra": "category=regression, cv=1.4%, noisy=false"
          },
          {
            "name": "execution/exec/fibonacci_30",
            "value": 20805.853481,
            "unit": "ms",
            "extra": "category=regression, cv=0.1%, noisy=false"
          },
          {
            "name": "execution/exec/property_chain",
            "value": 17.372196250002162,
            "unit": "ms",
            "extra": "category=regression, cv=10.1%, noisy=false"
          },
          {
            "name": "execution/exec/array_map_filter",
            "value": 26.654592800006505,
            "unit": "ms",
            "extra": "category=component, cv=11.5%, noisy=false"
          },
          {
            "name": "execution/exec/closure_factory",
            "value": 39.176559283333084,
            "unit": "ms",
            "extra": "category=component, cv=5.4%, noisy=false"
          },
          {
            "name": "execution/baseline/closure_conversion/closure_factory",
            "value": 39.12990701666713,
            "unit": "ms",
            "extra": "category=component, cv=8.2%, noisy=false"
          },
          {
            "name": "execution/baseline/bytecode/closure_factory",
            "value": 20.057311400000376,
            "unit": "ms",
            "extra": "category=component, cv=5.7%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/dispatch_stack",
            "value": 57.70871071111049,
            "unit": "ms",
            "extra": "category=component, cv=0.8%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/local_access",
            "value": 46.9615659999991,
            "unit": "ms",
            "extra": "category=component, cv=1.6%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/env_access",
            "value": 58.986666488889355,
            "unit": "ms",
            "extra": "category=component, cv=1.1%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/captured_access",
            "value": 55.874049022222685,
            "unit": "ms",
            "extra": "category=component, cv=1.0%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/call_frame",
            "value": 16.710230777775482,
            "unit": "ms",
            "extra": "category=component, cv=0.6%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/runtime_helpers",
            "value": 24.349033755555542,
            "unit": "ms",
            "extra": "category=component, cv=0.6%, noisy=false"
          },
          {
            "name": "execution/exec/arithmetic_loop",
            "value": 757.2784748749982,
            "unit": "ms",
            "extra": "category=component, cv=0.4%, noisy=false"
          },
          {
            "name": "execution/exec/object_construction",
            "value": 8.239586550000727,
            "unit": "ms",
            "extra": "category=component, cv=3.6%, noisy=false"
          },
          {
            "name": "execution/exec/string_ops",
            "value": 3.4203498100006255,
            "unit": "ms",
            "extra": "category=component, cv=7.1%, noisy=false"
          },
          {
            "name": "frontend/pipeline/exec/lex",
            "value": 0.02696343093333028,
            "unit": "ms",
            "extra": "category=workflow, cv=0.8%, noisy=false"
          },
          {
            "name": "frontend/pipeline/exec/parse",
            "value": 0.026729519212500236,
            "unit": "ms",
            "extra": "category=workflow, cv=2.9%, noisy=false"
          },
          {
            "name": "execution/pipeline/exec/evaluate",
            "value": 33.991401299997236,
            "unit": "ms",
            "extra": "category=workflow, cv=9.5%, noisy=false"
          },
          {
            "name": "execution/pipeline/closure_conversion/evaluate",
            "value": 34.02888345999963,
            "unit": "ms",
            "extra": "category=workflow, cv=4.8%, noisy=false"
          },
          {
            "name": "frontend/pipeline/bytecode/compile",
            "value": 0.021028417000023177,
            "unit": "ms",
            "extra": "category=workflow, cv=19.4%, noisy=true"
          },
          {
            "name": "execution/pipeline/bytecode/evaluate",
            "value": 14.237608469999978,
            "unit": "ms",
            "extra": "category=workflow, cv=5.8%, noisy=false"
          },
          {
            "name": "frontend/pipeline/parse_heavy",
            "value": 0.4710240193333593,
            "unit": "ms",
            "extra": "category=workflow, cv=5.3%, noisy=false"
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
          "id": "41d20d74392b55f65d9729ef75c5dc53402f90db",
          "message": "Show commit dates and compact benchmark dashboard (#175)\n\n* Show commit dates on benchmark charts\n\n* Compact benchmark dashboard mobile layout\n\n* Clarify benchmark dashboard copy\n\n* Minimize benchmark dashboard hero\n\n* Remove benchmark dashboard hero copy\n\n* Flatten benchmark dashboard header",
          "timestamp": "2026-05-31T05:56:59Z",
          "url": "https://github.com/dowdiness/js_engine/commit/41d20d74392b55f65d9729ef75c5dc53402f90db"
        },
        "date": 1780208828754,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "startup/startup/tiny_program",
            "value": 3.0041476555999997,
            "unit": "ms",
            "extra": "category=regression, cv=2.1%, noisy=false"
          },
          {
            "name": "frontend/lexer/small",
            "value": 0.03416348659999802,
            "unit": "ms",
            "extra": "category=regression, cv=28.6%, noisy=true"
          },
          {
            "name": "frontend/lexer/large",
            "value": 0.2801476339999951,
            "unit": "ms",
            "extra": "category=regression, cv=1.2%, noisy=false"
          },
          {
            "name": "execution/exec/fibonacci_30",
            "value": 21103.6872556,
            "unit": "ms",
            "extra": "category=regression, cv=0.4%, noisy=false"
          },
          {
            "name": "execution/exec/property_chain",
            "value": 20.408197125008883,
            "unit": "ms",
            "extra": "category=regression, cv=2.9%, noisy=false"
          },
          {
            "name": "execution/exec/array_map_filter",
            "value": 29.26384609999368,
            "unit": "ms",
            "extra": "category=component, cv=13.1%, noisy=false"
          },
          {
            "name": "execution/exec/closure_factory",
            "value": 41.24140648333268,
            "unit": "ms",
            "extra": "category=component, cv=5.6%, noisy=false"
          },
          {
            "name": "execution/baseline/closure_conversion/closure_factory",
            "value": 39.96862853333441,
            "unit": "ms",
            "extra": "category=component, cv=8.6%, noisy=false"
          },
          {
            "name": "execution/baseline/bytecode/closure_factory",
            "value": 22.080464533333725,
            "unit": "ms",
            "extra": "category=component, cv=5.4%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/dispatch_stack",
            "value": 50.80910162222248,
            "unit": "ms",
            "extra": "category=component, cv=0.7%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/local_access",
            "value": 44.97671351111171,
            "unit": "ms",
            "extra": "category=component, cv=1.3%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/env_access",
            "value": 62.19324248889008,
            "unit": "ms",
            "extra": "category=component, cv=0.6%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/captured_access",
            "value": 54.56687913333169,
            "unit": "ms",
            "extra": "category=component, cv=1.1%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/call_frame",
            "value": 18.124295111112428,
            "unit": "ms",
            "extra": "category=component, cv=3.7%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/runtime_helpers",
            "value": 24.744472133332682,
            "unit": "ms",
            "extra": "category=component, cv=0.5%, noisy=false"
          },
          {
            "name": "execution/exec/arithmetic_loop",
            "value": 968.0104426250036,
            "unit": "ms",
            "extra": "category=component, cv=0.8%, noisy=false"
          },
          {
            "name": "execution/exec/object_construction",
            "value": 10.251999883334793,
            "unit": "ms",
            "extra": "category=component, cv=2.9%, noisy=false"
          },
          {
            "name": "execution/exec/string_ops",
            "value": 3.889986580001132,
            "unit": "ms",
            "extra": "category=component, cv=7.5%, noisy=false"
          },
          {
            "name": "frontend/pipeline/exec/lex",
            "value": 0.02711953573333255,
            "unit": "ms",
            "extra": "category=workflow, cv=0.6%, noisy=false"
          },
          {
            "name": "frontend/pipeline/exec/parse",
            "value": 0.025386370125000023,
            "unit": "ms",
            "extra": "category=workflow, cv=3.4%, noisy=false"
          },
          {
            "name": "execution/pipeline/exec/evaluate",
            "value": 36.70052800000413,
            "unit": "ms",
            "extra": "category=workflow, cv=11.7%, noisy=false"
          },
          {
            "name": "execution/pipeline/closure_conversion/evaluate",
            "value": 35.02300048000063,
            "unit": "ms",
            "extra": "category=workflow, cv=4.7%, noisy=false"
          },
          {
            "name": "frontend/pipeline/bytecode/compile",
            "value": 0.02189006816666612,
            "unit": "ms",
            "extra": "category=workflow, cv=27.8%, noisy=true"
          },
          {
            "name": "execution/pipeline/bytecode/evaluate",
            "value": 15.610252220000257,
            "unit": "ms",
            "extra": "category=workflow, cv=6.2%, noisy=false"
          },
          {
            "name": "frontend/pipeline/parse_heavy",
            "value": 0.4739115953333675,
            "unit": "ms",
            "extra": "category=workflow, cv=6.4%, noisy=false"
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
          "id": "87d8abe7e0a14d3b7caed1beac842f9acc788573",
          "message": "Improve benchmark dashboard scanning (#176)",
          "timestamp": "2026-05-31T08:45:05Z",
          "url": "https://github.com/dowdiness/js_engine/commit/87d8abe7e0a14d3b7caed1beac842f9acc788573"
        },
        "date": 1780217383962,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "startup/startup/tiny_program",
            "value": 2.5261097843999987,
            "unit": "ms",
            "extra": "category=regression, cv=3.7%, noisy=false"
          },
          {
            "name": "frontend/lexer/small",
            "value": 0.03283220709999988,
            "unit": "ms",
            "extra": "category=regression, cv=31.3%, noisy=true"
          },
          {
            "name": "frontend/lexer/large",
            "value": 0.2843842588000007,
            "unit": "ms",
            "extra": "category=regression, cv=6.0%, noisy=false"
          },
          {
            "name": "execution/exec/fibonacci_30",
            "value": 18730.9052634,
            "unit": "ms",
            "extra": "category=regression, cv=0.4%, noisy=false"
          },
          {
            "name": "execution/exec/property_chain",
            "value": 16.172026000000187,
            "unit": "ms",
            "extra": "category=regression, cv=6.0%, noisy=false"
          },
          {
            "name": "execution/exec/array_map_filter",
            "value": 26.72022939999588,
            "unit": "ms",
            "extra": "category=component, cv=13.8%, noisy=false"
          },
          {
            "name": "execution/exec/closure_factory",
            "value": 41.3490552666665,
            "unit": "ms",
            "extra": "category=component, cv=4.8%, noisy=false"
          },
          {
            "name": "execution/baseline/closure_conversion/closure_factory",
            "value": 40.46587693333374,
            "unit": "ms",
            "extra": "category=component, cv=8.5%, noisy=false"
          },
          {
            "name": "execution/baseline/bytecode/closure_factory",
            "value": 21.84493461666619,
            "unit": "ms",
            "extra": "category=component, cv=5.9%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/dispatch_stack",
            "value": 59.523637533335325,
            "unit": "ms",
            "extra": "category=component, cv=0.5%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/local_access",
            "value": 48.898303066667474,
            "unit": "ms",
            "extra": "category=component, cv=1.2%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/env_access",
            "value": 63.92308135555552,
            "unit": "ms",
            "extra": "category=component, cv=0.7%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/captured_access",
            "value": 57.85351699999884,
            "unit": "ms",
            "extra": "category=component, cv=0.8%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/call_frame",
            "value": 18.259806599999617,
            "unit": "ms",
            "extra": "category=component, cv=2.1%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/runtime_helpers",
            "value": 22.933388155555196,
            "unit": "ms",
            "extra": "category=component, cv=1.8%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/property_get",
            "value": 63.25962722222126,
            "unit": "ms",
            "extra": "category=component, cv=0.8%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/property_set",
            "value": 52.739023999999816,
            "unit": "ms",
            "extra": "category=component, cv=1.7%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/method_call",
            "value": 19.46227964444358,
            "unit": "ms",
            "extra": "category=component, cv=1.0%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/object_literal",
            "value": 15.214947777777626,
            "unit": "ms",
            "extra": "category=component, cv=0.9%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/array_literal",
            "value": 15.578837777775737,
            "unit": "ms",
            "extra": "category=component, cv=1.0%, noisy=false"
          },
          {
            "name": "execution/exec/arithmetic_loop",
            "value": 907.6307461249999,
            "unit": "ms",
            "extra": "category=component, cv=0.6%, noisy=false"
          },
          {
            "name": "execution/exec/object_construction",
            "value": 8.959287816666379,
            "unit": "ms",
            "extra": "category=component, cv=4.0%, noisy=false"
          },
          {
            "name": "execution/exec/string_ops",
            "value": 3.4620466699995447,
            "unit": "ms",
            "extra": "category=component, cv=9.8%, noisy=false"
          },
          {
            "name": "frontend/pipeline/exec/lex",
            "value": 0.02756359386666832,
            "unit": "ms",
            "extra": "category=workflow, cv=0.9%, noisy=false"
          },
          {
            "name": "frontend/pipeline/exec/parse",
            "value": 0.02685565704999863,
            "unit": "ms",
            "extra": "category=workflow, cv=3.6%, noisy=false"
          },
          {
            "name": "execution/pipeline/exec/evaluate",
            "value": 36.75022620000236,
            "unit": "ms",
            "extra": "category=workflow, cv=10.9%, noisy=false"
          },
          {
            "name": "execution/pipeline/closure_conversion/evaluate",
            "value": 35.446575760000556,
            "unit": "ms",
            "extra": "category=workflow, cv=4.8%, noisy=false"
          },
          {
            "name": "frontend/pipeline/bytecode/compile",
            "value": 0.02258107533333047,
            "unit": "ms",
            "extra": "category=workflow, cv=27.8%, noisy=true"
          },
          {
            "name": "execution/pipeline/bytecode/evaluate",
            "value": 15.534427780000552,
            "unit": "ms",
            "extra": "category=workflow, cv=5.0%, noisy=false"
          },
          {
            "name": "frontend/pipeline/parse_heavy",
            "value": 0.4886705500000001,
            "unit": "ms",
            "extra": "category=workflow, cv=4.9%, noisy=false"
          }
        ]
      }
    ]
  }
}