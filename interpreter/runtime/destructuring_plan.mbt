///|
// An immutable, closed representation of the destructuring subset lowered by
// bytecode. The fields are private and the constructors copy their input
// arrays, so a verified plan cannot be mutated by its lowering caller.
pub struct DestructurePlan {
  priv node : DestructurePlanNode
}

///|
priv enum DestructurePlanNode {
  BindName(String)
  ArrayPattern(Array[DestructurePlan?], DestructurePlan?)
  ObjectPattern(Array[DestructurePropertyPlan], DestructurePlan?)
}

///|
pub struct DestructurePropertyPlan {
  priv key : String
  priv target : DestructurePlan
}

///|
pub fn destructure_plan_bind_name(name : String) -> DestructurePlan {
  { node: BindName(name) }
}

///|
pub fn destructure_plan_array(
  elements : Array[DestructurePlan?],
  rest : DestructurePlan?,
) -> DestructurePlan {
  { node: ArrayPattern(elements.copy(), rest) }
}

///|
pub fn destructure_plan_property(
  key : String,
  target : DestructurePlan,
) -> DestructurePropertyPlan {
  { key, target }
}

///|
pub fn destructure_plan_object(
  properties : Array[DestructurePropertyPlan],
  rest : DestructurePlan?,
) -> DestructurePlan {
  { node: ObjectPattern(properties.copy(), rest) }
}

///|
// The tree-walker remains the owner of the existing destructuring semantics.
// This adapter materializes the equivalent AST only inside that runtime owner;
// the compiler and VM carry and dispatch the immutable plan above. No source
// pattern is retained or consulted as a second authority.
pub fn Interpreter::eval_destructure_assign_plan(
  self : Interpreter,
  ctx : ExecContext,
  plan : DestructurePlan,
  value : Value,
  env : Environment,
) -> Value raise Error {
  self.eval_destructure_assign(ctx, plan.to_ast(), value, env)
}

///|
fn DestructurePlan::to_ast(self : DestructurePlan) -> @ast.Pattern {
  match self.node {
    BindName(name) => @ast.Pattern::IdentPat(name)
    ArrayPattern(elements, rest) => {
      let ast_elements : Array[@ast.Pattern?] = []
      for element in elements {
        ast_elements.push(
          match element {
            Some(plan) => Some(plan.to_ast())
            None => None
          },
        )
      }
      let ast_rest : @ast.Pattern? = match rest {
        Some(plan) => Some(plan.to_ast())
        None => None
      }
      @ast.Pattern::ArrayPat(ast_elements, ast_rest)
    }
    ObjectPattern(properties, rest) => {
      let ast_properties : Array[@ast.PropPat] = []
      for property in properties {
        ast_properties.push({
          key: property.key,
          key_lex_form: @token.LexForm::LexNormal,
          key_loc: @token.Loc::default(),
          value: property.target.to_ast(),
          default_val: None,
          computed_key: None,
        })
      }
      let ast_rest : @ast.Pattern? = match rest {
        Some(plan) => Some(plan.to_ast())
        None => None
      }
      @ast.Pattern::ObjectPat(ast_properties, ast_rest)
    }
  }
}
