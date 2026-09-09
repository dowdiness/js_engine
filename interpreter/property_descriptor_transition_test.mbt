///|
test "accessor transitions discard the previous data value" {
  let source =
    #|var targets = [{}, [], new Map(), new Set(), Promise.resolve(), function() {}];
    #|var keys = ['x', Symbol('x'), '0', '4294967294'];
    #|for (var target of targets) {
    #|  for (var key of keys) {
    #|    Object.defineProperty(target, key, {value: 1, writable: true, configurable: true});
    #|    Object.defineProperty(target, key, {get: function() { return 7; }});
    #|    if (target[key] !== 7) throw Error('getter');
    #|    Object.defineProperty(target, key, {get: undefined});
    #|    if (target[key] !== undefined) throw Error('stale own value: ' + String(key));
    #|    if (Reflect.get(target, key) !== undefined) throw Error('stale Reflect value');
    #|    var child = Object.create(target);
    #|    if (child[key] !== undefined) throw Error('stale inherited value');
    #|    var desc = Object.getOwnPropertyDescriptor(target, key);
    #|    if (desc.get !== undefined || 'value' in desc) throw Error('descriptor');
    #|    Object.defineProperty(target, key, {writable: true});
    #|    if (target[key] !== undefined) throw Error('stale converted value');
    #|    target[key] = 3;
    #|    Object.defineProperty(target, key, {enumerable: false});
    #|    if (target[key] !== 3) throw Error('generic descriptor lost data');
    #|  }
    #|}
    #|console.log('ok');
  let output = run_output(source)
  json_inspect(output, content=["ok"])
}
