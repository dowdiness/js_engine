window.BENCHMARK_DATA = {
  "lastUpdate": 1782627940250,
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
          "id": "7c7f102f92d011bfb79f2162188b2e37752ffc42",
          "message": "Fix live Array iterator semantics (#274)\n\n* Fix live Array iterator semantics\n\n* Use enum source for Array iterator kind\n\n* Refactor Array iterator construction helpers",
          "timestamp": "2026-06-07T05:44:26Z",
          "url": "https://github.com/dowdiness/js_engine/commit/7c7f102f92d011bfb79f2162188b2e37752ffc42"
        },
        "date": 1780814130167,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "startup/startup/tiny_program",
            "value": 1.399875991600001,
            "unit": "ms",
            "extra": "category=regression, cv=7.8%, noisy=false"
          },
          {
            "name": "frontend/lexer/small",
            "value": 0.031935156000000006,
            "unit": "ms",
            "extra": "category=regression, cv=27.7%, noisy=true"
          },
          {
            "name": "frontend/lexer/large",
            "value": 0.2661626111999988,
            "unit": "ms",
            "extra": "category=regression, cv=2.8%, noisy=false"
          },
          {
            "name": "execution/exec/fibonacci_30",
            "value": 15568.206102600001,
            "unit": "ms",
            "extra": "category=regression, cv=1.0%, noisy=false"
          },
          {
            "name": "execution/exec/property_chain",
            "value": 14.33809837499939,
            "unit": "ms",
            "extra": "category=regression, cv=3.7%, noisy=false"
          },
          {
            "name": "frontend/startup/phase/parse_tiny",
            "value": 0.001868894221999945,
            "unit": "ms",
            "extra": "category=component, cv=5.0%, noisy=false"
          },
          {
            "name": "startup/startup/phase/new_interpreter",
            "value": 1.2537532979997632,
            "unit": "ms",
            "extra": "category=component, cv=10.9%, noisy=false"
          },
          {
            "name": "execution/startup/phase/execute_preparsed_tiny",
            "value": 0.0005300860179999142,
            "unit": "ms",
            "extra": "category=component, cv=1.1%, noisy=false"
          },
          {
            "name": "startup/startup/phase/event_loop_drain_empty",
            "value": 0.00017964420320002827,
            "unit": "ms",
            "extra": "category=component, cv=0.7%, noisy=false"
          },
          {
            "name": "execution/startup/phase/result_stringify_output",
            "value": 0.00002784744724000106,
            "unit": "ms",
            "extra": "category=component, cv=0.3%, noisy=false"
          },
          {
            "name": "execution/exec/array_map_filter",
            "value": 23.592482399998698,
            "unit": "ms",
            "extra": "category=component, cv=22.1%, noisy=true"
          },
          {
            "name": "execution/exec/closure_factory",
            "value": 32.698906633333536,
            "unit": "ms",
            "extra": "category=component, cv=7.2%, noisy=false"
          },
          {
            "name": "execution/baseline/closure_conversion/closure_factory",
            "value": 30.547068416668726,
            "unit": "ms",
            "extra": "category=component, cv=7.8%, noisy=false"
          },
          {
            "name": "execution/baseline/bytecode/closure_factory",
            "value": 18.97846178333275,
            "unit": "ms",
            "extra": "category=component, cv=6.6%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/dispatch_stack",
            "value": 24.417567688889626,
            "unit": "ms",
            "extra": "category=component, cv=2.6%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/local_access",
            "value": 36.0261694222223,
            "unit": "ms",
            "extra": "category=component, cv=0.7%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/env_access",
            "value": 35.66654666666679,
            "unit": "ms",
            "extra": "category=component, cv=0.7%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/captured_access",
            "value": 38.59783657777847,
            "unit": "ms",
            "extra": "category=component, cv=1.8%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/call_frame",
            "value": 16.632381933332525,
            "unit": "ms",
            "extra": "category=component, cv=1.6%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/runtime_helpers",
            "value": 21.92909437777643,
            "unit": "ms",
            "extra": "category=component, cv=1.0%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/property_get",
            "value": 45.12268584444407,
            "unit": "ms",
            "extra": "category=component, cv=1.4%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/property_set",
            "value": 42.215171244443624,
            "unit": "ms",
            "extra": "category=component, cv=1.7%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/method_call",
            "value": 18.702605622222315,
            "unit": "ms",
            "extra": "category=component, cv=1.4%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/object_literal",
            "value": 12.713855777777889,
            "unit": "ms",
            "extra": "category=component, cv=0.9%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/array_literal",
            "value": 13.692106977778412,
            "unit": "ms",
            "extra": "category=component, cv=3.0%, noisy=false"
          },
          {
            "name": "execution/exec/arithmetic_loop",
            "value": 1038.1454066250044,
            "unit": "ms",
            "extra": "category=component, cv=0.7%, noisy=false"
          },
          {
            "name": "execution/exec/object_construction",
            "value": 8.915286483333329,
            "unit": "ms",
            "extra": "category=component, cv=3.9%, noisy=false"
          },
          {
            "name": "execution/exec/string_ops",
            "value": 2.1799451600009343,
            "unit": "ms",
            "extra": "category=component, cv=13.8%, noisy=false"
          },
          {
            "name": "frontend/pipeline/exec/lex",
            "value": 0.028162477400000597,
            "unit": "ms",
            "extra": "category=workflow, cv=0.9%, noisy=false"
          },
          {
            "name": "frontend/pipeline/exec/parse",
            "value": 0.025919158449998935,
            "unit": "ms",
            "extra": "category=workflow, cv=4.5%, noisy=false"
          },
          {
            "name": "execution/pipeline/exec/evaluate",
            "value": 27.53303639999067,
            "unit": "ms",
            "extra": "category=workflow, cv=1.4%, noisy=false"
          },
          {
            "name": "execution/pipeline/closure_conversion/evaluate",
            "value": 26.980007710000212,
            "unit": "ms",
            "extra": "category=workflow, cv=4.5%, noisy=false"
          },
          {
            "name": "frontend/pipeline/bytecode/compile",
            "value": 0.020514073833323595,
            "unit": "ms",
            "extra": "category=workflow, cv=21.7%, noisy=true"
          },
          {
            "name": "execution/pipeline/bytecode/evaluate",
            "value": 13.915317069998997,
            "unit": "ms",
            "extra": "category=workflow, cv=5.5%, noisy=false"
          },
          {
            "name": "frontend/pipeline/parse_heavy",
            "value": 0.48346938133338696,
            "unit": "ms",
            "extra": "category=workflow, cv=7.1%, noisy=false"
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
          "id": "d5f5c0feec17f9ba18af6cbb291cd20bec6b684c",
          "message": "arch(stage7): route bytecode literal accumulator paths through runtime ops (#333)\n\nStage 7 of the architecture redesign (object/array creation operations).\nMove the bytecode VM's incremental literal-accumulator paths off direct\nrepresentation mutation and onto new @runtime operations.\n\n- Add 4 runtime ops in interpreter/runtime/eval_expr.mbt:\n  apply_object_literal_static_data_property, apply_array_literal_element,\n  apply_array_literal_spread, apply_array_literal_hole. They mirror the\n  existing apply_object_literal_* family.\n- Migrate ObjectSetStatic / ArrayPushValue / ArrayPushSpread / ArrayPushHole\n  in compiler/bytecode_vm.mbt onto those ops. ObjectSetStatic gets a\n  dedicated naming-free op (NOT apply_object_literal_data_property) because\n  SetFunctionName is a separate instruction; interp.spread_iterable stays in\n  the VM so interpreter semantics do not leak into the runtime ops.\n- Drop the 4 now-dead bytecode_vm.mbt entries from\n  scripts/architecture_representation_access.json\n  (representation-access audit: 1577 -> 1567 classified accesses; all direct\n  representation access removed from the compiler's literal paths).\n- Add 4 equivalence tests to compiler/bytecode_test.mbt per the issue #330\n  per-migration harness obligation (mixed value/hole/spread accumulator,\n  hole-falls-through-to-prototype, computed-key + static-data ordering,\n  method + static-data evaluation order).\n\nSurfaced two Stage-7 design decisions as issues #331 (SourceKind /\npreparation-input encoding) and #332 (static_semantics cohesion convention);\nneither is touched by this slice.\n\nCo-authored-by: Claude Opus 4.8 (1M context) <noreply@anthropic.com>",
          "timestamp": "2026-06-13T04:27:13Z",
          "url": "https://github.com/dowdiness/js_engine/commit/d5f5c0feec17f9ba18af6cbb291cd20bec6b684c"
        },
        "date": 1781326028057,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "startup/startup/tiny_program",
            "value": 1.3649511203999998,
            "unit": "ms",
            "extra": "category=regression, cv=3.7%, noisy=false"
          },
          {
            "name": "frontend/lexer/small",
            "value": 0.030495824299999814,
            "unit": "ms",
            "extra": "category=regression, cv=24.6%, noisy=true"
          },
          {
            "name": "frontend/lexer/large",
            "value": 0.26990338759999977,
            "unit": "ms",
            "extra": "category=regression, cv=0.9%, noisy=false"
          },
          {
            "name": "execution/exec/fibonacci_30",
            "value": 15117.808278200002,
            "unit": "ms",
            "extra": "category=regression, cv=0.6%, noisy=false"
          },
          {
            "name": "execution/exec/property_chain",
            "value": 14.939459875002285,
            "unit": "ms",
            "extra": "category=regression, cv=6.1%, noisy=false"
          },
          {
            "name": "frontend/startup/phase/parse_tiny",
            "value": 0.0019367590039999624,
            "unit": "ms",
            "extra": "category=component, cv=0.9%, noisy=false"
          },
          {
            "name": "startup/startup/phase/new_interpreter",
            "value": 1.3908523919999711,
            "unit": "ms",
            "extra": "category=component, cv=10.8%, noisy=false"
          },
          {
            "name": "execution/startup/phase/execute_preparsed_tiny",
            "value": 0.0005657891449999588,
            "unit": "ms",
            "extra": "category=component, cv=1.4%, noisy=false"
          },
          {
            "name": "startup/startup/phase/event_loop_drain_empty",
            "value": 0.00015834052200001895,
            "unit": "ms",
            "extra": "category=component, cv=0.7%, noisy=false"
          },
          {
            "name": "execution/startup/phase/result_stringify_output",
            "value": 0.000026171621299999818,
            "unit": "ms",
            "extra": "category=component, cv=1.0%, noisy=false"
          },
          {
            "name": "execution/exec/array_map_filter",
            "value": 21.55982039999799,
            "unit": "ms",
            "extra": "category=component, cv=21.4%, noisy=true"
          },
          {
            "name": "execution/exec/closure_factory",
            "value": 29.565127666666616,
            "unit": "ms",
            "extra": "category=component, cv=3.8%, noisy=false"
          },
          {
            "name": "execution/baseline/closure_legacy/closure_factory",
            "value": 28.889896383332957,
            "unit": "ms",
            "extra": "category=component, cv=10.2%, noisy=false"
          },
          {
            "name": "execution/baseline/bytecode/closure_factory",
            "value": 16.194340950001305,
            "unit": "ms",
            "extra": "category=component, cv=6.8%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/dispatch_stack",
            "value": 21.03674028888927,
            "unit": "ms",
            "extra": "category=component, cv=0.7%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/local_access",
            "value": 34.92867831110877,
            "unit": "ms",
            "extra": "category=component, cv=0.8%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/env_access",
            "value": 35.109183644445146,
            "unit": "ms",
            "extra": "category=component, cv=0.5%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/captured_access",
            "value": 34.36433531110977,
            "unit": "ms",
            "extra": "category=component, cv=2.3%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/call_frame",
            "value": 17.43236704444474,
            "unit": "ms",
            "extra": "category=component, cv=2.1%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/runtime_helpers",
            "value": 20.631105155554053,
            "unit": "ms",
            "extra": "category=component, cv=1.3%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/property_get",
            "value": 42.673346288888325,
            "unit": "ms",
            "extra": "category=component, cv=2.6%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/property_set",
            "value": 40.112620066667056,
            "unit": "ms",
            "extra": "category=component, cv=1.2%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/method_call",
            "value": 17.791108222222988,
            "unit": "ms",
            "extra": "category=component, cv=1.0%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/object_literal",
            "value": 14.267341933332178,
            "unit": "ms",
            "extra": "category=component, cv=0.9%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/array_literal",
            "value": 14.741132488890113,
            "unit": "ms",
            "extra": "category=component, cv=3.3%, noisy=false"
          },
          {
            "name": "execution/exec/arithmetic_loop",
            "value": 993.9437046249986,
            "unit": "ms",
            "extra": "category=component, cv=0.6%, noisy=false"
          },
          {
            "name": "execution/exec/object_construction",
            "value": 7.3596199666668936,
            "unit": "ms",
            "extra": "category=component, cv=3.1%, noisy=false"
          },
          {
            "name": "execution/exec/string_ops",
            "value": 2.21327764000016,
            "unit": "ms",
            "extra": "category=component, cv=16.5%, noisy=true"
          },
          {
            "name": "frontend/pipeline/exec/lex",
            "value": 0.028155363133328504,
            "unit": "ms",
            "extra": "category=workflow, cv=4.5%, noisy=false"
          },
          {
            "name": "frontend/pipeline/exec/parse",
            "value": 0.02589529731250077,
            "unit": "ms",
            "extra": "category=workflow, cv=3.2%, noisy=false"
          },
          {
            "name": "execution/pipeline/exec/evaluate",
            "value": 27.397469800000543,
            "unit": "ms",
            "extra": "category=workflow, cv=12.6%, noisy=false"
          },
          {
            "name": "execution/pipeline/closure_legacy/evaluate",
            "value": 25.22136464999931,
            "unit": "ms",
            "extra": "category=workflow, cv=4.8%, noisy=false"
          },
          {
            "name": "frontend/pipeline/bytecode/compile",
            "value": 0.02101370616666099,
            "unit": "ms",
            "extra": "category=workflow, cv=22.1%, noisy=true"
          },
          {
            "name": "execution/pipeline/bytecode/evaluate",
            "value": 10.670627799999203,
            "unit": "ms",
            "extra": "category=workflow, cv=1.0%, noisy=false"
          },
          {
            "name": "frontend/pipeline/parse_heavy",
            "value": 0.47170434266670297,
            "unit": "ms",
            "extra": "category=workflow, cv=5.4%, noisy=false"
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
          "id": "539fc411d42876c7abf562c0f7e7bceb688d1bda",
          "message": "arch(stage8): static-attach helpers and typed internal-slot accessors (#345)\n\n* Add runtime static attach helpers\n\nIntroduce builtin_install.mbt (install_builtin_method/accessor/non_writable/frozen_data\nand their symbol-keyed counterparts) and internal_slots.mbt (typed-read/write helpers for\ninternal slot properties stored in PropertyBag). These form the static-attach API surface\nthat downstream tasks will migrate stdlib callers onto.\n\nCo-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>\n\n* Remove stdlib builtin install helper\n\nDelete builtin_install_helpers.mbt and replace all builtin_method_desc()\ncalls across stdlib with inline PropDescriptor literals. Migrate the one\ninstall_builtin_method() call in builtins_string.mbt to @runtime.install_builtin_method.\n\nCo-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>\n\n* Migrate error constructor static attach\n\nReplace raw bag.properties/bag.descriptors double-writes for the\nErrorType.prototype.constructor back-link in register_error_ctor and\nregister_aggregate_error_ctor with @runtime.install_builtin_method.\n\nAlso sync architecture_representation_access.json: update stale\nfingerprints/counts from earlier branch tasks, remove deleted\nbuiltin_install_helpers.mbt entries, and add missing\nbuiltins_iterator.mbt:runtime-prop-descriptor-type entry.\n\nCo-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>\n\n* arch(stage8): migrate ArrayBuffer static-attach to runtime install helpers\n\nReplace raw bag.properties/bag.descriptors writes for:\n- ArrayBuffer.prototype.constructor link → install_builtin_method\n- ArrayBuffer[@@species] accessor → install_builtin_symbol_accessor\n\nReduces representation-bag-field allowlist count from 9 → 5 in\nscripts/architecture_representation_access.json.\n\nSymmetric-diff proof: ArrayBuffer test262 failing sets identical before/after\n(172/172 passed in both runs).\n\nCo-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>\n\n* Fix stale audit fingerprint for builtins_arraybuffer after constructor migration\n\n* arch(stage8): migrate Map and Set static-attach to runtime install helpers\n\nReplace direct .bag.symbol_properties/descriptors writes in map_iterator_next\nwith @runtime.get/set_map_iterator_* ops, and replace Map/Set prototype symbol\ninstalls (Symbol.iterator, Symbol.toStringTag), constructor.prototype links, and\nprototype.constructor back-links with @runtime.install_builtin_* helpers.\n\nAllowlist updated: representation-bag-field builtins_map_set.mbt 24 -> 3.\n\n* Fix stale audit fingerprint for builtins_map_set after iterator migration\n\n* arch(stage8): migrate core builtin static-attach to runtime install helpers\n\nReplace raw bag-field writes in builtins.mbt with @runtime helper calls:\n- Boolean.prototype.toString/.valueOf: bag.properties.get(\"[[BooleanData]]\")\n  → @runtime.get_boolean_data(data)\n- String.prototype.constructor / Boolean.prototype.constructor: raw\n  bag.properties + bag.descriptors writes → @runtime.install_builtin_method\n- Error.isError: extract func into named let, attach via install_builtin_method\n- RegExp.prototype on constructor: bag writes → install_builtin_frozen_data\n- Symbol.species on Array/RegExp/Map/Set: raw symbol_properties/descriptors\n  writes → install_builtin_symbol_accessor; drop now-unused species_desc variable\n\nNote: Function.prototype[Symbol.hasInstance] intentionally left as raw bag\nwrite — its descriptor is non-writable/non-configurable (frozen symbol data)\nand no install_builtin_symbol_frozen_data helper exists. No behavior change.\n\nRepresentation-bag-field count: 29 → 17 (-12 accesses)\nArchitecture audit: passes clean after fingerprint update.\nSymmetric-diff proof: Boolean/Function/RegExp/Error all identical.\n\nCo-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>\n\n* Fix stale audit fingerprint for builtins after core builtin migration\n\n* Migrate TypedArray static attach\n\nReplace all raw bag.properties.get(\"[[...]]\") internal-slot reads in\nbuiltins_typedarray.mbt with @runtime helper calls:\n- get_typedarray_array_length / get_typedarray_buffer_id\n- get_typedarray_byte_offset / get_typedarray_byte_length\n- get_typedarray_viewed_buffer\n- get_arraybuffer_byte_length / get_arraybuffer_id\n\nReplace raw bag write-backs for constructor back-links with\ninstall_builtin_method, and @@species symbol write with\ninstall_builtin_symbol_accessor.\n\nSymmetric-diff proof: TypedArray failing set identical before/after.\nArchitecture audit: representation-bag-field 66→3 (3 non-slot reads remain).\n\nCo-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>\n\n* Fix stale audit fingerprint for builtins_typedarray after slot migration\n\n* Complete Stage 8 static attach migration\n\nUpdate ROADMAP.md with latest test262 baseline from CI run 27483688641\n(tip 1f727c9, 2026-06-14): strict 95.3% / non-strict 94.0% P/E. Update\nunit test count to 2092, regression baseline delta to +3,567/+2,966, and\nadd Stage 8 PRs #335–#343 and architecture audit PRs #312/#314 to the\ndelta section.\n\nCo-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>\n\n* Document intentional raw write for Function.prototype @@hasInstance\n\n* refactor: promote builtin_method_desc to pub and remove inline descriptor literals\n\nThe Stage 8 migration deleted builtin_install_helpers.mbt, which had\nbuiltin_method_desc() as a stdlib-private helper. Subagents replaced its 8\ncall sites with repeated 7-line inline PropDescriptor literals rather than\npromoting the function. This commit restores the named abstraction:\n\n- Make builtin_method_desc() pub in interpreter/runtime/builtin_install.mbt\n- Replace 8 inline literals across builtins.mbt and builtins_map_set.mbt\n  with @runtime.builtin_method_desc()\n\nThe install helpers (install_builtin_method etc.) handle one-at-a-time\npost-construction installs. The batch-init pattern (Map[String,PropDescriptor]\npassed into ObjectData struct literals) genuinely needs the raw descriptor\nvalue — both call sites coexist by design.\n\nCo-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>\n\n* refactor(stdlib): replace inline PropDescriptor literals with builtin_method_desc()\n\nStage 8 migration deleted builtin_install_helpers.mbt but left ~30 call sites\nwith repeated 6-line PropDescriptor struct literals. This change:\n\n- Promotes builtin_method_desc() to pub in interpreter/runtime so stdlib can\n  call it directly for batch-init patterns (where install_builtin_method is\n  unavailable because the ObjectData struct doesn't exist yet)\n- Adds install_builtin_symbol_frozen_data() helper for frozen symbol-keyed\n  properties; uses it for Function.prototype[@@hasInstance] (ES §20.2.3.3\n  requires writable:false configurable:false, not the standard method desc)\n- Replaces all 30 remaining inline literals across 8 stdlib files with\n  @runtime.builtin_method_desc() or a shared local binding\n\nCo-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>\n\n---------\n\nCo-authored-by: Claude Sonnet 4.6 <noreply@anthropic.com>",
          "timestamp": "2026-06-14T05:32:43Z",
          "url": "https://github.com/dowdiness/js_engine/commit/539fc411d42876c7abf562c0f7e7bceb688d1bda"
        },
        "date": 1781419680771,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "startup/startup/tiny_program",
            "value": 1.1797696643999998,
            "unit": "ms",
            "extra": "category=regression, cv=5.0%, noisy=false"
          },
          {
            "name": "frontend/lexer/small",
            "value": 0.03167613599999959,
            "unit": "ms",
            "extra": "category=regression, cv=26.6%, noisy=true"
          },
          {
            "name": "frontend/lexer/large",
            "value": 0.2652478248,
            "unit": "ms",
            "extra": "category=regression, cv=3.4%, noisy=false"
          },
          {
            "name": "execution/exec/fibonacci_30",
            "value": 13254.200273400002,
            "unit": "ms",
            "extra": "category=regression, cv=0.4%, noisy=false"
          },
          {
            "name": "execution/exec/property_chain",
            "value": 16.195887375000893,
            "unit": "ms",
            "extra": "category=regression, cv=27.1%, noisy=true"
          },
          {
            "name": "frontend/startup/phase/parse_tiny",
            "value": 0.0018141987119998661,
            "unit": "ms",
            "extra": "category=component, cv=0.5%, noisy=false"
          },
          {
            "name": "startup/startup/phase/new_interpreter",
            "value": 1.1661992840000022,
            "unit": "ms",
            "extra": "category=component, cv=12.7%, noisy=false"
          },
          {
            "name": "execution/startup/phase/execute_preparsed_tiny",
            "value": 0.0005681413919999758,
            "unit": "ms",
            "extra": "category=component, cv=0.8%, noisy=false"
          },
          {
            "name": "startup/startup/phase/event_loop_drain_empty",
            "value": 0.0001619948423999711,
            "unit": "ms",
            "extra": "category=component, cv=0.5%, noisy=false"
          },
          {
            "name": "execution/startup/phase/result_stringify_output",
            "value": 0.000026108849999999803,
            "unit": "ms",
            "extra": "category=component, cv=0.4%, noisy=false"
          },
          {
            "name": "execution/exec/array_map_filter",
            "value": 19.475222100000245,
            "unit": "ms",
            "extra": "category=component, cv=25.4%, noisy=true"
          },
          {
            "name": "execution/exec/closure_factory",
            "value": 27.13049436666649,
            "unit": "ms",
            "extra": "category=component, cv=6.9%, noisy=false"
          },
          {
            "name": "execution/baseline/closure_legacy/closure_factory",
            "value": 25.974495033333362,
            "unit": "ms",
            "extra": "category=component, cv=8.7%, noisy=false"
          },
          {
            "name": "execution/baseline/bytecode/closure_factory",
            "value": 14.393648049999802,
            "unit": "ms",
            "extra": "category=component, cv=5.2%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/dispatch_stack",
            "value": 22.559347977778337,
            "unit": "ms",
            "extra": "category=component, cv=0.5%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/local_access",
            "value": 34.893509888889895,
            "unit": "ms",
            "extra": "category=component, cv=0.6%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/env_access",
            "value": 35.04326284444413,
            "unit": "ms",
            "extra": "category=component, cv=0.4%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/captured_access",
            "value": 38.10423862222232,
            "unit": "ms",
            "extra": "category=component, cv=1.4%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/call_frame",
            "value": 15.68908513333267,
            "unit": "ms",
            "extra": "category=component, cv=1.1%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/runtime_helpers",
            "value": 20.411537977776927,
            "unit": "ms",
            "extra": "category=component, cv=5.6%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/property_get",
            "value": 42.45865886666709,
            "unit": "ms",
            "extra": "category=component, cv=1.6%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/property_set",
            "value": 41.59683202222222,
            "unit": "ms",
            "extra": "category=component, cv=0.5%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/method_call",
            "value": 17.28476544444436,
            "unit": "ms",
            "extra": "category=component, cv=0.8%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/object_literal",
            "value": 13.06622495555461,
            "unit": "ms",
            "extra": "category=component, cv=0.9%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/array_literal",
            "value": 13.47516637777832,
            "unit": "ms",
            "extra": "category=component, cv=0.7%, noisy=false"
          },
          {
            "name": "execution/exec/arithmetic_loop",
            "value": 978.9243826249949,
            "unit": "ms",
            "extra": "category=component, cv=0.3%, noisy=false"
          },
          {
            "name": "execution/exec/object_construction",
            "value": 7.048582599999402,
            "unit": "ms",
            "extra": "category=component, cv=8.4%, noisy=false"
          },
          {
            "name": "execution/exec/string_ops",
            "value": 1.8039588300013567,
            "unit": "ms",
            "extra": "category=component, cv=14.4%, noisy=false"
          },
          {
            "name": "frontend/pipeline/exec/lex",
            "value": 0.027125098666669026,
            "unit": "ms",
            "extra": "category=workflow, cv=0.5%, noisy=false"
          },
          {
            "name": "frontend/pipeline/exec/parse",
            "value": 0.02642986196249985,
            "unit": "ms",
            "extra": "category=workflow, cv=2.7%, noisy=false"
          },
          {
            "name": "execution/pipeline/exec/evaluate",
            "value": 25.174390999999012,
            "unit": "ms",
            "extra": "category=workflow, cv=12.1%, noisy=false"
          },
          {
            "name": "execution/pipeline/closure_legacy/evaluate",
            "value": 22.81061899000022,
            "unit": "ms",
            "extra": "category=workflow, cv=4.3%, noisy=false"
          },
          {
            "name": "frontend/pipeline/bytecode/compile",
            "value": 0.02229539866667377,
            "unit": "ms",
            "extra": "category=workflow, cv=31.3%, noisy=true"
          },
          {
            "name": "execution/pipeline/bytecode/evaluate",
            "value": 9.410773369999953,
            "unit": "ms",
            "extra": "category=workflow, cv=1.9%, noisy=false"
          },
          {
            "name": "frontend/pipeline/parse_heavy",
            "value": 0.4786830380000175,
            "unit": "ms",
            "extra": "category=workflow, cv=5.1%, noisy=false"
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
          "id": "e914cb64b9b196b60aa765e18ad27890e17dec93",
          "message": "fix(lexer): regex/division disambiguation after } (#422)\n\nCloses #414\n\nFive-commit fix for regex/division disambiguation after :\n\n- Block vs expression context after : introduced  stack\n  tracking whether each  opens a statement block (declaration bodies, plain\n  blocks) vs an expression (object literals, fn/class expressions).\n- Ternary colon vs label/case colon: replaced scalar  counter\n  with a stack of brace-depths at each ; a  matches only when the depth\n  equals the stack top, so object-property colons in the consequent never\n  consume the ternary slot.\n- Nested class in extends: replaced three class-body-pending scalars with a\n  stack of (is_stmt_pos, paren_depth, brace_depth) tuples, so inner class\n  expressions in heritage clauses don't overwrite outer declaration state.\n- Arrow function bodies: split brace_is_block into two parallel arrays\n  (brace_is_block for closure context, brace_content_is_block for interior\n  context), removing Arrow from is_plain_block so arrow body  does not\n  enable a following  as regex.\n- class as property name: guard Class keyword dispatch with follows_dot and\n  in_object_literal checks so  does not push a stale pending\n  class body entry.",
          "timestamp": "2026-06-21T05:00:18Z",
          "url": "https://github.com/dowdiness/js_engine/commit/e914cb64b9b196b60aa765e18ad27890e17dec93"
        },
        "date": 1782025083894,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "startup/startup/tiny_program",
            "value": 1.1909902471999998,
            "unit": "ms",
            "extra": "category=regression, cv=5.4%, noisy=false"
          },
          {
            "name": "frontend/lexer/small",
            "value": 0.03613960969999992,
            "unit": "ms",
            "extra": "category=regression, cv=30.1%, noisy=true"
          },
          {
            "name": "frontend/lexer/large",
            "value": 0.3013078152000003,
            "unit": "ms",
            "extra": "category=regression, cv=2.8%, noisy=false"
          },
          {
            "name": "execution/exec/fibonacci_30",
            "value": 14418.370539800002,
            "unit": "ms",
            "extra": "category=regression, cv=1.1%, noisy=false"
          },
          {
            "name": "execution/exec/property_chain",
            "value": 14.041157625000778,
            "unit": "ms",
            "extra": "category=regression, cv=10.8%, noisy=false"
          },
          {
            "name": "frontend/startup/phase/parse_tiny",
            "value": 0.0019851204780000843,
            "unit": "ms",
            "extra": "category=component, cv=0.6%, noisy=false"
          },
          {
            "name": "startup/startup/phase/new_interpreter",
            "value": 1.2359483400001192,
            "unit": "ms",
            "extra": "category=component, cv=9.1%, noisy=false"
          },
          {
            "name": "execution/startup/phase/execute_preparsed_tiny",
            "value": 0.0004986391239999647,
            "unit": "ms",
            "extra": "category=component, cv=1.0%, noisy=false"
          },
          {
            "name": "startup/startup/phase/event_loop_drain_empty",
            "value": 0.00018266434359999264,
            "unit": "ms",
            "extra": "category=component, cv=3.8%, noisy=false"
          },
          {
            "name": "execution/startup/phase/result_stringify_output",
            "value": 0.000027931852699999874,
            "unit": "ms",
            "extra": "category=component, cv=0.4%, noisy=false"
          },
          {
            "name": "execution/exec/array_map_filter",
            "value": 20.156251600001998,
            "unit": "ms",
            "extra": "category=component, cv=17.6%, noisy=true"
          },
          {
            "name": "execution/exec/closure_factory",
            "value": 30.139295033333475,
            "unit": "ms",
            "extra": "category=component, cv=6.4%, noisy=false"
          },
          {
            "name": "execution/baseline/closure_legacy/closure_factory",
            "value": 29.089381533333164,
            "unit": "ms",
            "extra": "category=component, cv=7.6%, noisy=false"
          },
          {
            "name": "execution/baseline/bytecode/closure_factory",
            "value": 14.334837849999891,
            "unit": "ms",
            "extra": "category=component, cv=8.1%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/dispatch_stack",
            "value": 24.280099422221408,
            "unit": "ms",
            "extra": "category=component, cv=2.8%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/local_access",
            "value": 38.05952451111128,
            "unit": "ms",
            "extra": "category=component, cv=1.7%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/env_access",
            "value": 38.18722837777976,
            "unit": "ms",
            "extra": "category=component, cv=0.5%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/captured_access",
            "value": 39.375147888889636,
            "unit": "ms",
            "extra": "category=component, cv=1.0%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/call_frame",
            "value": 7.6925925111132925,
            "unit": "ms",
            "extra": "category=component, cv=1.3%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/runtime_helpers",
            "value": 11.569700333335076,
            "unit": "ms",
            "extra": "category=component, cv=3.4%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/property_get",
            "value": 46.14060153333315,
            "unit": "ms",
            "extra": "category=component, cv=4.2%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/property_set",
            "value": 42.31862928888942,
            "unit": "ms",
            "extra": "category=component, cv=2.9%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/method_call",
            "value": 8.735639733333503,
            "unit": "ms",
            "extra": "category=component, cv=1.1%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/object_literal",
            "value": 13.680031355557084,
            "unit": "ms",
            "extra": "category=component, cv=0.9%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/array_literal",
            "value": 15.41669797777884,
            "unit": "ms",
            "extra": "category=component, cv=2.6%, noisy=false"
          },
          {
            "name": "execution/exec/for_of",
            "value": 6.36851556666564,
            "unit": "ms",
            "extra": "category=component, cv=10.6%, noisy=false"
          },
          {
            "name": "execution/exec/arithmetic_loop",
            "value": 832.3586149999901,
            "unit": "ms",
            "extra": "category=component, cv=0.4%, noisy=false"
          },
          {
            "name": "execution/exec/object_construction",
            "value": 7.730631233334135,
            "unit": "ms",
            "extra": "category=component, cv=4.5%, noisy=false"
          },
          {
            "name": "execution/exec/string_ops",
            "value": 1.9943949000001886,
            "unit": "ms",
            "extra": "category=component, cv=24.0%, noisy=true"
          },
          {
            "name": "frontend/pipeline/exec/lex",
            "value": 0.03104578346667306,
            "unit": "ms",
            "extra": "category=workflow, cv=1.5%, noisy=false"
          },
          {
            "name": "frontend/pipeline/exec/parse",
            "value": 0.026935453537498693,
            "unit": "ms",
            "extra": "category=workflow, cv=3.4%, noisy=false"
          },
          {
            "name": "execution/pipeline/exec/evaluate",
            "value": 27.86180699999968,
            "unit": "ms",
            "extra": "category=workflow, cv=7.6%, noisy=false"
          },
          {
            "name": "execution/pipeline/closure_legacy/evaluate",
            "value": 27.878015749999328,
            "unit": "ms",
            "extra": "category=workflow, cv=8.0%, noisy=false"
          },
          {
            "name": "frontend/pipeline/bytecode/compile",
            "value": 0.022246963166660864,
            "unit": "ms",
            "extra": "category=workflow, cv=31.6%, noisy=true"
          },
          {
            "name": "execution/pipeline/bytecode/evaluate",
            "value": 10.407405850000506,
            "unit": "ms",
            "extra": "category=workflow, cv=1.7%, noisy=false"
          },
          {
            "name": "frontend/pipeline/parse_heavy",
            "value": 0.5251057786666207,
            "unit": "ms",
            "extra": "category=workflow, cv=6.1%, noisy=false"
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
          "id": "f6cbb4a577d45fd8afe00ef6f3e5e44bcbd74b80",
          "message": "chore: ratchet test262 baseline after PRs #479-#481 (#482)\n\nnon-strict: 27674 → 27686 (+12)\nstrict:     25911 → 25923 (+12)\n\nCovers gains from:\n- PR #479: SuperCall rest-param/defaults + derived-this TDZ + eval_super_dispatch\n- PR #480: iterator close on abrupt generator resume in dstr\n- PR #481: §10.2.11 TDZ pre-pass for class constructor param binding\n\nCo-authored-by: Claude Sonnet 4.6 <noreply@anthropic.com>",
          "timestamp": "2026-06-27T14:25:43Z",
          "url": "https://github.com/dowdiness/js_engine/commit/f6cbb4a577d45fd8afe00ef6f3e5e44bcbd74b80"
        },
        "date": 1782627939825,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "startup/startup/tiny_program",
            "value": 1.2893613864,
            "unit": "ms",
            "extra": "category=regression, cv=10.7%, noisy=false"
          },
          {
            "name": "frontend/lexer/small",
            "value": 0.03503440440000041,
            "unit": "ms",
            "extra": "category=regression, cv=26.2%, noisy=true"
          },
          {
            "name": "frontend/lexer/large",
            "value": 0.3028574352000014,
            "unit": "ms",
            "extra": "category=regression, cv=0.8%, noisy=false"
          },
          {
            "name": "execution/exec/fibonacci_30",
            "value": 14317.130767400002,
            "unit": "ms",
            "extra": "category=regression, cv=1.2%, noisy=false"
          },
          {
            "name": "execution/exec/property_chain",
            "value": 16.631985249996433,
            "unit": "ms",
            "extra": "category=regression, cv=6.9%, noisy=false"
          },
          {
            "name": "frontend/startup/phase/parse_tiny",
            "value": 0.0019948603620000642,
            "unit": "ms",
            "extra": "category=component, cv=2.1%, noisy=false"
          },
          {
            "name": "startup/startup/phase/new_interpreter",
            "value": 1.2015209319999267,
            "unit": "ms",
            "extra": "category=component, cv=13.1%, noisy=false"
          },
          {
            "name": "execution/startup/phase/execute_preparsed_tiny",
            "value": 0.0006131243320000357,
            "unit": "ms",
            "extra": "category=component, cv=1.2%, noisy=false"
          },
          {
            "name": "startup/startup/phase/event_loop_drain_empty",
            "value": 0.00017984681600001062,
            "unit": "ms",
            "extra": "category=component, cv=1.2%, noisy=false"
          },
          {
            "name": "execution/startup/phase/result_stringify_output",
            "value": 0.00002693486305999977,
            "unit": "ms",
            "extra": "category=component, cv=1.7%, noisy=false"
          },
          {
            "name": "execution/exec/array_map_filter",
            "value": 21.620783099997787,
            "unit": "ms",
            "extra": "category=component, cv=16.8%, noisy=true"
          },
          {
            "name": "execution/exec/closure_factory",
            "value": 31.87077309999999,
            "unit": "ms",
            "extra": "category=component, cv=6.3%, noisy=false"
          },
          {
            "name": "execution/baseline/closure_legacy/closure_factory",
            "value": 30.57168836666679,
            "unit": "ms",
            "extra": "category=component, cv=8.9%, noisy=false"
          },
          {
            "name": "execution/baseline/bytecode/closure_factory",
            "value": 14.962228816667386,
            "unit": "ms",
            "extra": "category=component, cv=7.4%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/dispatch_stack",
            "value": 23.30144855555587,
            "unit": "ms",
            "extra": "category=component, cv=3.3%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/local_access",
            "value": 39.69642177777715,
            "unit": "ms",
            "extra": "category=component, cv=3.0%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/env_access",
            "value": 40.228504355557696,
            "unit": "ms",
            "extra": "category=component, cv=1.0%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/captured_access",
            "value": 38.69843091111139,
            "unit": "ms",
            "extra": "category=component, cv=1.3%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/call_frame",
            "value": 7.554276800001712,
            "unit": "ms",
            "extra": "category=component, cv=1.2%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/runtime_helpers",
            "value": 11.448460466666278,
            "unit": "ms",
            "extra": "category=component, cv=0.9%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/property_get",
            "value": 44.72406617777759,
            "unit": "ms",
            "extra": "category=component, cv=1.2%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/property_set",
            "value": 42.497640488891115,
            "unit": "ms",
            "extra": "category=component, cv=2.0%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/method_call",
            "value": 8.722051533331655,
            "unit": "ms",
            "extra": "category=component, cv=1.1%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/object_literal",
            "value": 13.671022466666503,
            "unit": "ms",
            "extra": "category=component, cv=1.5%, noisy=false"
          },
          {
            "name": "execution/isolate/bytecode/array_literal",
            "value": 15.752419599999364,
            "unit": "ms",
            "extra": "category=component, cv=2.9%, noisy=false"
          },
          {
            "name": "execution/exec/for_of",
            "value": 6.529010450000352,
            "unit": "ms",
            "extra": "category=component, cv=5.1%, noisy=false"
          },
          {
            "name": "execution/exec/arithmetic_loop",
            "value": 1054.2869795000006,
            "unit": "ms",
            "extra": "category=component, cv=0.8%, noisy=false"
          },
          {
            "name": "execution/exec/object_construction",
            "value": 7.553015766666794,
            "unit": "ms",
            "extra": "category=component, cv=8.1%, noisy=false"
          },
          {
            "name": "execution/exec/string_ops",
            "value": 2.080291900000593,
            "unit": "ms",
            "extra": "category=component, cv=22.1%, noisy=true"
          },
          {
            "name": "frontend/pipeline/exec/lex",
            "value": 0.030475314000002498,
            "unit": "ms",
            "extra": "category=workflow, cv=0.6%, noisy=false"
          },
          {
            "name": "frontend/pipeline/exec/parse",
            "value": 0.02803036042500171,
            "unit": "ms",
            "extra": "category=workflow, cv=3.2%, noisy=false"
          },
          {
            "name": "execution/pipeline/exec/evaluate",
            "value": 28.68166420000198,
            "unit": "ms",
            "extra": "category=workflow, cv=8.6%, noisy=false"
          },
          {
            "name": "execution/pipeline/closure_legacy/evaluate",
            "value": 27.205402900000344,
            "unit": "ms",
            "extra": "category=workflow, cv=4.6%, noisy=false"
          },
          {
            "name": "frontend/pipeline/bytecode/compile",
            "value": 0.022835203166658175,
            "unit": "ms",
            "extra": "category=workflow, cv=30.4%, noisy=true"
          },
          {
            "name": "execution/pipeline/bytecode/evaluate",
            "value": 10.154311319999978,
            "unit": "ms",
            "extra": "category=workflow, cv=5.5%, noisy=false"
          },
          {
            "name": "frontend/pipeline/parse_heavy",
            "value": 0.5249414786665972,
            "unit": "ms",
            "extra": "category=workflow, cv=6.6%, noisy=false"
          }
        ]
      }
    ]
  }
}