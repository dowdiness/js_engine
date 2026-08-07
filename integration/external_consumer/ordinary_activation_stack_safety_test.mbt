///|
test "external consumer traverses changing receivers without host stack growth" {
  let engine = @js_engine.Engine()
  engine.eval(
    (
      #|function Link(next) { this.next = next; }
      #|Link.prototype.walk = function(depth) {
      #|  if (depth === 0) return 0;
      #|  return 1 + this.next.walk(depth - 1);
      #|};
      #|function traverseChangingReceivers(depth) {
      #|  let link = new Link(null);
      #|  for (let index = 0; index < depth; index++) {
      #|    link = new Link(link);
      #|  }
      #|  return link.walk(depth);
      #|}
    ),
  )
  json_inspect(
    engine.call_json("traverseChangingReceivers", [Json::number(2048.0)]),
    content=2048,
  )
}
