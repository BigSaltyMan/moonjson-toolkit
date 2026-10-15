///|
/// Limits are independent of the CLI input parser's --max-depth option.
let schema_compile_depth_limit : Int = 128

///|
let schema_compile_node_limit : Int = 100000

///|
let schema_evaluation_depth_limit : Int = 128

///|
let schema_evaluation_visit_limit : Int = 100000

///|
pub(all) enum SchemaEvaluationErrorKind {
  ReferenceCycle
  ResourceLimit
} derive(Eq, Debug)

///|
/// Both paths are RFC 6901 JSON Pointers; the empty string denotes the root.
pub(all) struct SchemaEvaluationError {
  kind : SchemaEvaluationErrorKind
  message : String
  instance_path : String
  schema_path : String
} derive(Eq, Debug)

///|
pub(all) enum SchemaValidationFailure {
  SchemaProblems(Array[SchemaProblem])
  EvaluationFailed(SchemaEvaluationError)
} derive(Debug)

///|
fn pointer_child(parent : String, token : String) -> String {
  parent + "/" + token.replace(old="~", new="~0").replace(old="/", new="~1")
}

///|
fn ref_hex(ch : Char) -> Int? {
  let n = ch.to_int()
  if n >= 48 && n <= 57 {
    Some(n - 48)
  } else if n >= 65 && n <= 70 {
    Some(n - 55)
  } else if n >= 97 && n <= 102 {
    Some(n - 87)
  } else {
    None
  }
}

///|
/// URI decoding is performed exactly once, with strict UTF-8 validation.
/// Literal plus signs are not form-encoded spaces.
fn decode_ref_fragment(raw : String) -> Result[String, String] {
  let chars = raw.to_array()
  let out = StringBuilder()
  let mut i = 0
  while i < chars.length() {
    if chars[i] != '%' {
      out.write_char(chars[i])
      i = i + 1
      continue
    }
    let bytes : Array[Int] = []
    while i < chars.length() && chars[i] == '%' {
      if i + 2 >= chars.length() {
        return Err("incomplete percent escape")
      }
      match (ref_hex(chars[i + 1]), ref_hex(chars[i + 2])) {
        (Some(a), Some(b)) => bytes.push(a * 16 + b)
        _ => return Err("invalid percent escape")
      }
      i = i + 3
    }
    let mut j = 0
    while j < bytes.length() {
      let first = bytes[j]
      let (width, initial, minimum) = if first < 128 {
        (1, first, 0)
      } else if first >= 194 && first <= 223 {
        (2, first - 192, 128)
      } else if first >= 224 && first <= 239 {
        (3, first - 224, 2048)
      } else if first >= 240 && first <= 244 {
        (4, first - 240, 65536)
      } else {
        return Err("invalid UTF-8 in reference fragment")
      }
      if j + width > bytes.length() {
        return Err("incomplete UTF-8 in reference fragment")
      }
      let mut cp = initial
      for k in 1..<width {
        let byte = bytes[j + k]
        if byte < 128 || byte > 191 {
          return Err("invalid UTF-8 continuation byte")
        }
        cp = cp * 64 + byte - 128
      }
      if cp < minimum || cp > 1114111 {
        return Err("invalid UTF-8 code point")
      }
      match cp.to_char() {
        Some(ch) => out.write_char(ch)
        None => return Err("invalid UTF-8 code point")
      }
      j = j + width
    }
  }
  Ok(out.to_string())
}

///|
fn decode_pointer_token(raw : String) -> Result[String, String] {
  let chars = raw.to_array()
  let out = StringBuilder()
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '~' {
      if i + 1 >= chars.length() {
        return Err("incomplete JSON Pointer escape")
      }
      match chars[i + 1] {
        '0' => out.write_char('~')
        '1' => out.write_char('/')
        _ => return Err("invalid JSON Pointer escape")
      }
      i = i + 2
    } else {
      out.write_char(chars[i])
      i = i + 1
    }
  }
  Ok(out.to_string())
}

///|
/// A normalized pointer and its schema target, without copying the subtree.
fn resolve_schema_ref(
  root : @pjson.Json,
  raw : String,
) -> Result[(String, @pjson.Json), (SchemaProblemKind, String)] {
  if !raw.has_prefix("#") {
    return Err((UnsupportedFeature, "external references are not supported"))
  }
  let fragment = match decode_ref_fragment(raw[1:].to_owned()) {
    Ok(text) => text
    Err(reason) => return Err((InvalidSchema, reason))
  }
  if fragment != "" && !fragment.has_prefix("/") {
    return Err((UnsupportedFeature, "named anchors are not supported"))
  }
  let mut target = root
  let mut pointer = ""
  if fragment != "" {
    let tokens = fragment[1:]
      .to_owned()
      .split("/")
      .map(fn(s) { s.to_owned() })
      .collect()
    for encoded in tokens {
      let token = match decode_pointer_token(encoded) {
        Ok(token) => token
        Err(reason) => return Err((InvalidSchema, reason))
      }
      pointer = pointer_child(pointer, token)
      target = match target {
        Object(members~) =>
          match find_member(members, token) {
            Some(value) => value
            None =>
              return Err(
                (InvalidSchema, "reference target does not exist: " + pointer),
              )
          }
        Array(items~) => {
          let chars = token.to_array()
          if chars.is_empty() ||
            (chars.length() > 1 && chars[0] == '0') ||
            !chars.all(fn(ch) { ch >= '0' && ch <= '9' }) {
            return Err(
              (InvalidSchema, "invalid array index in reference: " + token),
            )
          }
          // Compare incrementally to the actual array size before arithmetic.
          let mut index = 0
          for ch in chars {
            let digit = ch.to_int() - 48
            if index > items.length() / 10 ||
              (index == items.length() / 10 && digit >= items.length() % 10) {
              return Err(
                (InvalidSchema, "reference array index is out of bounds"),
              )
            }
            index = index * 10 + digit
          }
          if index >= items.length() {
            return Err(
              (InvalidSchema, "reference array index is out of bounds"),
            )
          }
          items[index]
        }
        _ =>
          return Err(
            (InvalidSchema, "reference cannot traverse a scalar value"),
          )
      }
    }
  }
  match target {
    Object(_) | Bool(_) => Ok((pointer, target))
    _ =>
      Err(
        (InvalidSchema, "reference target must be an object or boolean schema"),
      )
  }
}

///|
/// Property names are synthetic strings at the containing object's pointer.
/// Their identity must differ from both that object and its member values.
priv enum SchemaInstanceKind {
  InstanceValue
  PropertyName(String)
} derive(Eq, Hash)

///|
priv struct SchemaEvaluationContext {
  compiled : CompiledSchema
  active : Map[(Int, String, SchemaInstanceKind), Bool]
  depth_limit : Int
  visit_limit : Int
  mut visits : Int
  mut failure : SchemaEvaluationError?
  mut schema_pointer : String
  mut instance_pointer : String
  mut instance_kind : SchemaInstanceKind
  mut depth : Int
}

///|
fn evaluation_fail(
  ctx : SchemaEvaluationContext,
  kind : SchemaEvaluationErrorKind,
  reason : String,
  schema_pointer : String,
) -> Unit {
  if ctx.failure == None {
    ctx.failure = Some({
      kind,
      message: match ctx.instance_kind {
        InstanceValue => reason
        PropertyName(name) =>
          "property name \"" + escape_json_string(name) + "\": " + reason
      },
      instance_path: ctx.instance_pointer,
      schema_path: schema_pointer,
    })
  }
}

///|
/// Mutable state is per invocation, never held on CompiledSchema. The first
/// execution failure wins and is returned independently of ordinary violations.
fn evaluate_schema_with_limits(
  json : @pjson.Json,
  compiled : CompiledSchema,
  depth_limit : Int,
  visit_limit : Int,
) -> Result[Array[SchemaError], SchemaEvaluationError] {
  let ctx : SchemaEvaluationContext = {
    compiled,
    active: Map([]),
    depth_limit,
    visit_limit,
    visits: 0,
    failure: None,
    schema_pointer: "",
    instance_pointer: "",
    instance_kind: InstanceValue,
    depth: 0,
  }
  let errors = []
  evaluate_schema_node(json, "", "", "", errors, ctx)
  match ctx.failure {
    Some(error) => Err(error)
    None => Ok(errors)
  }
}

///|
fn evaluate_schema_node(
  value : @pjson.Json,
  pointer : String,
  instance : String,
  display : String,
  errors : Array[SchemaError],
  ctx : SchemaEvaluationContext,
) -> Unit {
  if ctx.failure != None {
    return
  }
  let node = ctx.compiled.nodes[ctx.compiled.node_ids[pointer]]
  let previous_instance = ctx.instance_pointer
  ctx.instance_pointer = instance
  let key = (node.id, instance, ctx.instance_kind)
  if ctx.active.contains(key) {
    // The location of the edge that closed the cycle, rather than the target.
    evaluation_fail(
      ctx,
      ReferenceCycle,
      "reference cycle",
      pointer_child(ctx.schema_pointer, "$ref"),
    )
    ctx.instance_pointer = previous_instance
    return
  }
  if ctx.depth >= ctx.depth_limit || ctx.visits >= ctx.visit_limit {
    evaluation_fail(
      ctx,
      ResourceLimit,
      "schema evaluation depth or node visit limit exceeded",
      pointer,
    )
    ctx.instance_pointer = previous_instance
    return
  }
  ctx.visits = ctx.visits + 1
  ctx.depth = ctx.depth + 1
  ctx.active[key] = true
  let previous_schema = ctx.schema_pointer
  ctx.schema_pointer = pointer
  check_value(value, node.schema, display, errors, ctx)
  ctx.schema_pointer = previous_schema
  ctx.instance_pointer = previous_instance
  ctx.depth = ctx.depth - 1
  ctx.active.remove(key) |> ignore
}

///|
fn evaluate_schema_child(
  value : @pjson.Json,
  schema_tokens : Array[String],
  instance_token : String?,
  display : String,
  errors : Array[SchemaError],
  ctx : SchemaEvaluationContext,
) -> Unit {
  let mut pointer = ctx.schema_pointer
  for token in schema_tokens {
    pointer = pointer_child(pointer, token)
  }
  let instance = match instance_token {
    Some(token) => pointer_child(ctx.instance_pointer, token)
    None => ctx.instance_pointer
  }
  let previous_kind = ctx.instance_kind
  if instance_token is Some(_) {
    ctx.instance_kind = InstanceValue
  }
  evaluate_schema_node(value, pointer, instance, display, errors, ctx)
  ctx.instance_kind = previous_kind
}
