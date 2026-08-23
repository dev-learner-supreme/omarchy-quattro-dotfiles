-- WirePlumber 0.5 user script for Intel SOF / ALC256 automatic headphone/speaker profile switching
cutils = require ("common-utils")
log = Log.open_topic ("s-device")

function switchProfile(device, target_keyword)
  local cur_profile = nil
  for p in device:iterate_params ("Profile") do
    cur_profile = cutils.parseParam (p, "Profile")
  end

  for p in device:iterate_params ("EnumProfile") do
    local profile = cutils.parseParam (p, "EnumProfile")
    if profile and string.find (profile.name, target_keyword) then
      if cur_profile == nil or cur_profile.index ~= profile.index then
        local pod = Pod.Object {
          "Spa:Pod:Object:Param:Profile", "Profile",
          index = profile.index,
          save = false
        }
        log:info (device, string.format ("SOF AutoSwitch: Switching from profile %s to %s",
          cur_profile and cur_profile.name or "none", profile.name))
        device:set_params ("Profile", pod)
      end
      return
    end
  end
end

function evaluateDevice(device)
  local dev_name = device.properties["device.name"] or ""
  if not string.find(dev_name, "skl_hda_dsp_generic") and not string.find(dev_name, "sof") then
    return
  end

  local hp_available = false
  for p in device:iterate_params ("EnumRoute") do
    local route = cutils.parseParam (p, "EnumRoute")
    if route and route.name == "[Out] Headphones" and route.available == "yes" then
      hp_available = true
      break
    end
  end

  if hp_available then
    switchProfile(device, "Headphones")
  else
    switchProfile(device, "Speaker")
  end
end

SimpleEventHook {
  name = "sof-autoswitch/on-route-change",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "device-added" },
    },
    EventInterest {
      Constraint { "event.type", "=", "device-params-changed" },
      Constraint { "event.subject.param-id", "=", "EnumRoute" },
    },
    EventInterest {
      Constraint { "event.type", "=", "device-params-changed" },
      Constraint { "event.subject.param-id", "=", "Route" },
    },
  },
  execute = function (event)
    local device = event:get_subject ()
    evaluateDevice(device)
  end
}:register()
