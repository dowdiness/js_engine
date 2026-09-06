///|
test "String match and search invoke the generated RegExp symbol method" {
  let source =
    #|var name = 'METHOD';
    #|var marker = {};
    #|var observed;
    #|RegExp.prototype[Symbol[name]] = function (text) {
    #|  observed = [this instanceof RegExp, this.source, this.flags,
    #|              this.lastIndex, arguments.length, text];
    #|  return marker;
    #|};
    #|var result = RECEIVER[name]('source');
    #|observed.push(result === marker);
    #|JSON.stringify(observed);
  for method_name in ["match", "search"] {
    for receiver in ["'target'", "new String('target')"] {
      let script = source
        .replace(old="METHOD", new=method_name)
        .replace(old="RECEIVER", new=receiver)
      assert_eq(
        run(script).to_string(),
        "[true,\"source\",\"\",0,1,\"target\",true]",
        msg=method_name + " on " + receiver,
      )
    }
  }
}

///|
test "String match and search with omitted patterns create an empty RegExp" {
  let source =
    #|JSON.stringify(['abc'.match()[0], 'abc'.match(undefined)[0],
    #|                'abc'.search(), 'abc'.search(undefined)]);
  assert_eq(run(source).to_string(), "[\"\",\"\",0,0]")
}
