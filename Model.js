// Pure helpers for the loocist.iot panel: JSON parsing, device grouping,
// and the human-readable strings the rows and hero render.

function parseResponse(raw) {
  try {
    return JSON.parse(String(raw))
  } catch (e) {
    return null
  }
}

function devicesOf(parsed) {
  return parsed && parsed.ok === true ? (parsed.devices || []) : []
}

function controllableOf(devices) {
  var out = []
  for (var i = 0; i < devices.length; i++)
    if (devices[i].controllable === true)
      out.push(devices[i])
  return out
}

function othersOf(devices) {
  var out = []
  for (var i = 0; i < devices.length; i++)
    if (devices[i].controllable !== true)
      out.push(devices[i])
  return out
}

function countOn(devices) {
  var n = 0
  for (var i = 0; i < devices.length; i++)
    if (devices[i].on === true)
      n++
  return n
}

function totalPower(devices) {
  var w = 0
  for (var i = 0; i < devices.length; i++)
    if (typeof devices[i].power === "number")
      w += devices[i].power
  return w
}

// Second line of a switch row: ip · model · power, or a busy/locked variant.
function deviceMeta(dev, busy, busyAction) {
  if (busy)
    return busyAction === "on" ? "Switching on…" : "Switching off…"
  if (dev.reachable === false)
    return dev.ip + " · unreachable"
  var bits = [dev.ip]
  if (dev.model && dev.model.length > 0)
    bits.push(dev.model)
  if (dev.locked === true)
    bits.push("protected")
  if (typeof dev.power === "number")
    bits.push(dev.power + " W")
  return bits.join(" · ")
}

// Second line of a non-drivable row: what it is and where its web UI lives.
function otherMeta(dev) {
  var bits = []
  if (dev.vendor && dev.vendor.length > 0)
    bits.push(dev.vendor)
  bits.push(dev.ip)
  return bits.join(" · ")
}

function heroMeta(devices, loading) {
  if (devices.length === 0)
    return loading ? "Scanning the network…" : "No IoT devices found"
  var meta = devices.length + (devices.length === 1 ? " device" : " devices")
  var on = countOn(devices)
  if (on > 0)
    meta += " · " + on + " on"
  var w = totalPower(devices)
  if (w > 0)
    meta += " · " + Math.round(w) + " W"
  return meta
}

function barTooltip(devices, loading) {
  if (devices.length === 0)
    return loading ? "IoT — scanning…" : "IoT — no devices found"
  return "IoT — " + heroMeta(devices, loading)
}
