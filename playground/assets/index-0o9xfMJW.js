(function(){const n=document.createElement("link").relList;if(n&&n.supports&&n.supports("modulepreload"))return;for(const t of document.querySelectorAll('link[rel="modulepreload"]'))l(t);new MutationObserver(t=>{for(const a of t)if(a.type==="childList")for(const _ of a.addedNodes)_.tagName==="LINK"&&_.rel==="modulepreload"&&l(_)}).observe(document,{childList:!0,subtree:!0});function s(t){const a={};return t.integrity&&(a.integrity=t.integrity),t.referrerPolicy&&(a.referrerPolicy=t.referrerPolicy),t.crossOrigin==="use-credentials"?a.credentials="include":t.crossOrigin==="anonymous"?a.credentials="omit":a.credentials="same-origin",a}function l(t){if(t.ep)return;t.ep=!0;const a=s(t);fetch(t.href,a)}})();const O=1,z=1e5,A=`console.log(42);
console.log((10 + 20) * 3);
`,C=`function makeCounter() {
  var count = 0;
  return function() {
    count = count + 1;
    return count;
  };
}

var counter = makeCounter();
console.log(counter()); // 1
console.log(counter()); // 2
console.log(counter()); // 3
`,H=`function factorial(n) {
  if (n <= 1) return 1;
  return n * factorial(n - 1);
}

console.log(factorial(5)); // 120
`,L=`var a = 0;
var b = 1;
while (b < 100) {
  console.log(b);
  var temp = a + b;
  a = b;
  b = temp;
}
`,M=`for (var i = 1; i <= 20; i = i + 1) {
  if (i % 15 == 0) {
    console.log("Fizz Buzz");
  } else if (i % 3 == 0) {
    console.log("Fizz");
  } else if (i % 5 == 0) {
    console.log("Buzz");
  } else {
    console.log(i);
  }
}
`,G=`// 100万個のオブジェクトを作っては捨てる
for (var i = 0; i < 1000000; i++) {
  var temp = { id: i, data: "junk" }; // ここでメモリ確保
  // ループが回るとtempは参照されなくなり、ゴミになる
}
console.log("Survived!");
`,P=`// Array iteration
for (const x of [1, 2, 3]) console.log(x);

// String iteration
for (const c of "abc") console.log(c);

// Array iterator methods
[1, 2, 3].keys();    // Iterator: 0, 1, 2
[1, 2, 3].values();  // Iterator: 1, 2, 3
[1, 2, 3].entries(); // Iterator: [0,1], [1,2], [2,3]

// Custom iterator (if implemented)
const obj = {
  [Symbol.iterator]() {
    let i = 0;
    return {
      next() {
        return i < 3 ? {value: i++, done: false} : {done: true};
      }
    };
  }
};
for (const x of obj) console.log(x); // 0, 1, 2
`,R=`/**
 * マンデルブロ集合 ASCIIアート版
 */
function drawMandelbrot() {
  const width = 70; // 描画幅
  const height = 40; // 描画高さ
  const maxIteration = 50; // 最大計算回数

  // ASCIIアート用の文字（集合の内部ほど文字が濃くなる）
  const chars = " .:-=+*#%@";

  let result = "";

  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      // 画面座標を複素平面上の座標に変換 (-2.0 < re < 1.0, -1.0 < im < 1.0)
      let c_re = (x - width / 1.5) * 3.0 / width;
      let c_im = (y - height / 2) * 2.0 / height;

      let z_re = 0;
      let z_im = 0;
      let iteration = 0;

      // マンデルブロの繰り返し計算: z = z^2 + c
      while (z_re * z_re + z_im * z_im <= 4 && iteration < maxIteration) {
        let next_re = z_re * z_re - z_im * z_im + c_re;
        let next_im = 2 * z_re * z_im + c_im;
        z_re = next_re;
        z_im = next_im;
        iteration++;
      }

      // 発散までの速度で文字を決める
      if (iteration === maxIteration) {
        result += "@"; // 集合内部
      } else {
        result += chars[Math.floor(iteration / maxIteration * (chars.length - 1))];
      }
    }
    result += "\\n"; // 改行
  }

  console.log(result);
}

drawMandelbrot();
`,D=`function Hero(name) {
  this.name = name;
  this.hp = 100;
}

Hero.prototype.attack = function(monster) {
  console.log(this.name + " attacks " + monster.name + "!");
  monster.hp = monster.hp - 10;
};

var hero = new Hero("JS-Warrior");
var slime = { name: "Slime", hp: 30 };

hero.attack(slime); // JS-Warrior attacks Slime!
console.log(slime.hp); // 20
`,$=`// Test Map and Set implementations

console.log("=== Map Tests ===");

// Create a new Map
const map = new Map();
console.log("Created new Map");
console.log("Size:", map.size); // Should be 0

// Test set and get
map.set("key1", "value1");
map.set("key2", "value2");
console.log("After adding 2 entries, size:", map.size); // Should be 2
console.log("Get key1:", map.get("key1")); // Should be "value1"
console.log("Get key2:", map.get("key2")); // Should be "value2"
console.log("Get nonexistent:", map.get("key3")); // Should be undefined

// Test has
console.log("Has key1:", map.has("key1")); // Should be true
console.log("Has key3:", map.has("key3")); // Should be false

// Test delete
console.log("Delete key1:", map.delete("key1")); // Should be true
console.log("After delete, size:", map.size); // Should be 1
console.log("Has key1 after delete:", map.has("key1")); // Should be false
console.log("Delete nonexistent:", map.delete("key3")); // Should be false

// Test clear
map.set("a", 1);
map.set("b", 2);
console.log("Before clear, size:", map.size);
map.clear();
console.log("After clear, size:", map.size); // Should be 0

// Test with different key types
map.set(1, "number key");
map.set(true, "boolean key");
map.set(null, "null key");
console.log("Get number key:", map.get(1));
console.log("Get boolean key:", map.get(true));
console.log("Get null key:", map.get(null));

// Test NaN equality (SameValueZero)
map.set(NaN, "NaN value");
console.log("Get NaN:", map.get(NaN)); // Should work because NaN === NaN in SameValueZero

console.log("\\n=== Set Tests ===");

// Create a new Set
const set = new Set();
console.log("Created new Set");
console.log("Size:", set.size); // Should be 0

// Test add
set.add("value1");
set.add("value2");
console.log("After adding 2 values, size:", set.size); // Should be 2

// Test add duplicate
set.add("value1");
console.log("After adding duplicate, size:", set.size); // Should still be 2

// Test has
console.log("Has value1:", set.has("value1")); // Should be true
console.log("Has value3:", set.has("value3")); // Should be false

// Test delete
console.log("Delete value1:", set.delete("value1")); // Should be true
console.log("After delete, size:", set.size); // Should be 1
console.log("Has value1 after delete:", set.has("value1")); // Should be false
console.log("Delete nonexistent:", set.delete("value3")); // Should be false

// Test clear
set.add("a");
set.add("b");
console.log("Before clear, size:", set.size);
set.clear();
console.log("After clear, size:", set.size); // Should be 0

// Test with different value types
set.add(1);
set.add(true);
set.add(null);
console.log("Has number 1:", set.has(1));
console.log("Has boolean true:", set.has(true));
console.log("Has null:", set.has(null));

// Test NaN equality (SameValueZero)
set.add(NaN);
set.add(NaN); // Should not add duplicate
console.log("After adding NaN twice, has NaN:", set.has(NaN)); // Should be true
console.log("Size after adding NaN twice:", set.size); // Should not have duplicates

console.log("\\n=== Map from iterable ===");
const map2 = new Map([["a", 1], ["b", 2], ["c", 3]]);
console.log("Map from array, size:", map2.size); // Should be 3
console.log("Get 'a':", map2.get("a")); // Should be 1

console.log("\\n=== Set from iterable ===");
const set2 = new Set([1, 2, 3, 2, 1]);
console.log("Set from array, size:", set2.size); // Should be 3 (no duplicates)
console.log("Has 1:", set2.has(1)); // Should be true
console.log("Has 4:", set2.has(4)); // Should be false

console.log("\\n=== All tests completed ===");
`,B=Object.assign({"../generated/examples/arith.js":A,"../generated/examples/closure.js":C,"../generated/examples/factorial.js":H,"../generated/examples/fibonacci.js":L,"../generated/examples/fizzbuzz.js":M,"../generated/examples/gc.js":G,"../generated/examples/iterator.js":P,"../generated/examples/mandelbrot.js":R,"../generated/examples/prototype.js":D,"../generated/examples/test_map_set.js":$});function U(e){const n=e.split("/").pop();if(!n||!n.endsWith(".js"))throw new Error(`Invalid example path: ${e}`);return n.slice(0,-3)}const y=Object.fromEntries(Object.entries(B).map(([e,n])=>[U(e),n])),c=p(document.querySelector("#editor"),"editor"),u=p(document.querySelector("#console"),"console"),d=p(document.querySelector("#result"),"result"),m=p(document.querySelector("#diagnostics"),"diagnostics"),k=p(document.querySelector("#status"),"status");function p(e,n){if(!e)throw new Error(`Playground markup is missing ${n}`);return e}function x(){return c.value}function N(e){c.value=e}function W(){c.focus()}function F(e){e&&(c.focus(),c.setSelectionRange(e.start.offset,e.end?.offset??e.start.offset))}function K(){g("Running","running"),r(u,""),r(d,""),r(m,"")}function V(e,n){g("Complete","complete"),r(u,e.join(`
`)),r(d,n),r(m,"")}function b(e,n=!0){g("Failed","failed"),r(u,e.output.join(`
`)),r(d,""),r(m,Z(e.diagnostic)),n&&F(e.diagnostic.location)}function S(e){g(e.reason==="timeout"?"Execution terminated":"Stopped","terminated"),r(u,""),r(d,""),r(m,e.reason==="timeout"?"The worker exceeded the 2 second wall-clock limit and was replaced.":"The running worker was discarded.")}function J(){g("Ready","idle"),r(u,""),r(d,""),r(m,"")}function g(e,n){k.textContent=e,k.dataset.state=n}function r(e,n){e.textContent=n}function Z(e){const n=e.location?`
line ${e.location.start.line}, column ${e.location.start.column}`:"";return`${e.failureKind}: ${e.message}${n}`}const X=2e3,I=document.querySelector("#run"),T=document.querySelector("#stop"),E=document.querySelector("#clear"),i=document.querySelector("#example");if(!I||!T||!E||!i)throw new Error("Playground controls are incomplete");const j=i.querySelector("optgroup");if(!j)throw new Error("Playground example group is incomplete");const v=Object.keys(y).sort();if(v.length===0)throw new Error("Playground examples are empty");for(const e of v){const n=document.createElement("option");n.value=e,n.textContent=Y(e),j.append(n)}i.value=v[0];function Y(e){return e.split("_").map(n=>n.charAt(0).toUpperCase()+n.slice(1)).join(" ")}let f=h(),o;I.addEventListener("click",()=>q());T.addEventListener("click",()=>w("stopped"));E.addEventListener("click",()=>{w("stopped"),J()});i.addEventListener("change",()=>{const e=y[i.value];e!==void 0&&N(e),W()});document.addEventListener("keydown",e=>{(e.metaKey||e.ctrlKey)&&e.key==="Enter"&&(e.preventDefault(),q())});function q(){w("stopped");const e=x();if(e.length>z){b({output:[],diagnostic:{failureKind:"source-too-large",message:`Source is limited to ${z} UTF-16 code units.`,operation:"run",phase:"request",sourceId:null,location:null,engineIntegrity:"not-applicable",retainedEffects:"none",pendingJobs:"unknown"}});return}const n=crypto.randomUUID(),s=f,l=window.setTimeout(()=>{!o||o.requestId!==n||(s.terminate(),o=void 0,f=h(),S({reason:"timeout"}))},X);o={requestId:n,timerId:l,worker:s,source:e},K();const t={protocolVersion:O,requestId:n,operation:"run",source:e};s.postMessage(t)}function w(e){o&&(window.clearTimeout(o.timerId),o.worker.terminate(),o.requestId,o=void 0,f=h(),S({reason:e}))}function h(){const e=new Worker(new URL("/js_engine/playground/assets/engine-worker-CZ3x78Yp.js",import.meta.url),{type:"module"});return e.addEventListener("message",n=>{const s=o,l=n.data;!s||s.worker!==e||l.requestId!==s.requestId||(window.clearTimeout(s.timerId),o=void 0,l.kind==="completed"?V(l.output,l.result):l.kind==="failed"?b(l,x()===s.source):S(l))}),e.addEventListener("error",n=>{if(!o||o.worker!==e)return;window.clearTimeout(o.timerId);const s=o.requestId;o=void 0,e.terminate(),f=h(),b({output:[],diagnostic:{failureKind:"worker-failure",message:n.message||"The engine worker failed.",operation:"run",phase:"worker",sourceId:`playground:${s}`,location:null,engineIntegrity:"not-applicable",retainedEffects:"none",pendingJobs:"unknown"}})}),e}N(y[i.value]);
