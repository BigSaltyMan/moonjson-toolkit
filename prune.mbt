///|
/// Return `json` without the object members whose value is `null`.
///
/// A member holding `null` says no more than the member being absent, so a
/// document that carries them is one where `null` stood in for "no value": worth
/// writing once and not worth reading every time. The members that stay keep the
/// order they were written in, and every other value is left exactly as it was —
/// including an object that is left empty once its null members are gone, since
/// emptying out is a separate thing to ask for.
///
/// An array keeps every item it had, null ones included. An array is a sequence
/// and its positions are part of what it says, so dropping an item out of the
/// middle would renumber everything after it: a null inside an object is a name
/// with no value and removing it removes a name, while a null inside an array is
/// a value in a place and removing it changes what the items around it are.
///
/// As with sorting and trimming, the tree handed in is left as it was found:
/// every container is rebuilt rather than edited.
pub fn prune_null(json : @pjson.Json) -> @pjson.Json {
  match json {
    Object(members~) => {
      let out : Array[(String, @pjson.Json)] = []
      for entry in members {
        let (key, value) = entry
        match value {
          Null => ()
          _ => out.push((key, prune_null(value)))
        }
      }
      Object(members=out)
    }
    Array(items~) => Array(items=items.map(fn(item) { prune_null(item) }))
    // A bare `null` is the document, not a member of one, so there is nothing
    // holding it that could be dropped.
    leaf => leaf
  }
}

///|
/// Return `json` with every empty object and every empty array removed.
///
/// A container with nothing in it is a container that says nothing, so they go
/// wherever they are — as a member of an object or as an item of an array — and
/// the containers left empty by that go too, however far up the document that
/// reaches: `{"a":{"b":{}}}` comes back as `{}` in one pass.
///
/// The document itself is kept even when it ends up empty. It is not a member of
/// anything, so there is no container to be told that it has nothing in it, and
/// removing it would leave nothing at all where a document was asked for: `{}`
/// and `[]` come back as they were.
pub fn prune_empty(json : @pjson.Json) -> @pjson.Json {
  match json {
    Object(members~) => {
      let out : Array[(String, @pjson.Json)] = []
      for entry in members {
        let (key, value) = entry
        match prune_empty_value(value) {
          Some(value) => out.push((key, value))
          None => ()
        }
      }
      Object(members=out)
    }
    Array(items~) => {
      let out : Array[@pjson.Json] = []
      for item in items {
        match prune_empty_value(item) {
          Some(item) => out.push(item)
          None => ()
        }
      }
      Array(items=out)
    }
    leaf => leaf
  }
}

///|
/// Prune one value, answering `None` when it is an empty container.
///
/// This is where a container is actually dropped, and it is done on the way out
/// of the recursion: by the time a container is looked at here, everything
/// inside it has already been pruned, so one that is empty now is one that was
/// empty or emptied. That is what makes the cascade work — the caller drops this
/// one and then finds itself empty in turn.
///
/// The distinction between `None` and an empty container is the distinction
/// between a value inside a document and the document itself, which is why the
/// two `prune_empty` arms above build their container unconditionally.
fn prune_empty_value(value : @pjson.Json) -> @pjson.Json? {
  match prune_empty(value) {
    Object(members=inner) =>
      if inner.is_empty() {
        None
      } else {
        Some(Object(members=inner))
      }
    Array(items~) => if items.is_empty() { None } else { Some(Array(items~)) }
    other => Some(other)
  }
}
