///|
priv enum DispatchOrdinaryPropertyLookup {
  DispatchOrdinaryPropertyValue(Value)
  DispatchOrdinaryPropertyGetter(Value)
  DispatchOrdinaryPropertyUnsupported
}

///|
fn dispatch_ordinary_property_lookup(
  work : DispatchPropertyGetResume,
) -> DispatchOrdinaryPropertyLookup {
  let property = match work.property_key {
    String_(found) => found
    _ => return DispatchOrdinaryPropertyUnsupported
  }
  let mut current = work.target
  while true {
    match current {
      Array(data) if property == "0" =>
        if data.elements.length() > 0 && !data.holes.contains(0) {
          return DispatchOrdinaryPropertyValue(data.elements[0])
        } else {
          return DispatchOrdinaryPropertyUnsupported
        }
      Object(data) if data.class_name == "Object" =>
        match data.bag.descriptors.get(property) {
          Some(descriptor) =>
            match descriptor.getter {
              Some(getter) => return DispatchOrdinaryPropertyGetter(getter)
              None =>
                if descriptor.is_accessor || descriptor.setter is Some(_) {
                  return DispatchOrdinaryPropertyValue(Undefined)
                } else {
                  return DispatchOrdinaryPropertyValue(
                    data.bag.properties.get(property).unwrap_or(Undefined),
                  )
                }
            }
          None =>
            match data.bag.properties.get(property) {
              Some(value) => return DispatchOrdinaryPropertyValue(value)
              None => current = data.prototype
            }
        }
      Null => return DispatchOrdinaryPropertyValue(Undefined)
      _ => return DispatchOrdinaryPropertyUnsupported
    }
  } nobreak {
    DispatchOrdinaryPropertyUnsupported
  }
}
