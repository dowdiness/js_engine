///|
#skip("blocked by #608 runtime evaluator stack safety")
test "post-parse stack safety: 512 comma expressions" {
  inspect(run(nested_comma_source(512, "7")), content="7")
}
