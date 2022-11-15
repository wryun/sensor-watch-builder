valid_faces = {
  simple_clock_face = true,
  world_clock_face = true,
  preferences_face = true,
  set_time_face = true,
  pulsometer_face = true,
  thermistor_readout_face = true,
  thermistor_logging_face = true,
  thermistor_testing_face = true,
  character_set_face = true,
  beats_face = true,
  day_one_face = true,
  voltage_face = true,
  stopwatch_face = true,
  totp_face = true,
  totp_face_lfs = true,
  lis2dw_logging_face = true,
  demo_face = true,
  hello_there_face = true,
  sunrise_sunset_face = true,
  countdown_face = true,
  counter_face = true,
  blinky_face = true,
  moon_phase_face = true,
  accelerometer_data_acquisition_face = true,
  mars_time_face = true,
  orrery_face = true,
  astronomy_face = true,
  tomato_face = true,
  probability_face = true,
  wake_face = true,
  frequency_correction_face = true,
  alarm_face = true,
  ratemeter_face = true,
}

function exists(path)
  local file = io.open(path, "r")
  if (file ~= nil) then
    io.close(file)
    return true
  else
    return false
  end
end

local args = ngx.req.get_post_args()
errors = {}
if args['faces'] == nil then
  table.insert(errors, 'No faces provided')
elseif type(args['faces']) == 'string' then
  faces = {args['faces']}
else
  faces = args['faces']
end

secondary_face_index = #args['faces']

if args['secondary_faces'] ~= nil then
  if type(args['secondary_faces']) == 'string' then
    table.insert(faces, args['secondary_faces'])
  else
    for _, face in ipairs(args['secondary_faces']) do
      table.insert(faces, face)
    end
  end
end

for _, face in ipairs(faces) do
  if valid_faces[face] == nil then
    -- do html escape face so we can display
    table.insert(errors, 'Face not recognised')
  end
end

if #errors > 0 then
  ngx.status = 503
  ngx.say('<html><body><ul>')
  for _, error in ipairs(errors) do
    ngx.say('<li>' .. error)
  end
  ngx.say('</ul></body></html>')
  ngx.exit(ngx.HTTP_OK)
end

hash = ngx.md5(table.concat(faces, ':') .. ':' .. secondary_face_index)

dir = '/builds/' .. hash .. '/'

if args['flush'] then
  os.execute('rm -rf ' .. dir)
end

if exists(dir .. 'completed') then
  ngx.redirect(dir)
end

os.execute('rm -rf ' .. dir)
code = os.execute('mkdir ' .. dir)
if code == nil then
  ngx.status = 400
  ngx.say('<html><body>')
  ngx.say('<p>Unable to create build dir</p>')
  ngx.say('</body></html>')
  ngx.exit(ngx.HTTP_OK)
end


-- Generate config file
movement_config = [[
#ifndef MOVEMENT_CONFIG_H_
#define MOVEMENT_CONFIG_H_

#include "movement_faces.h"

const watch_face_t watch_faces[] = {
]] .. table.concat(faces, ", ") .. [[ ,
};

#define MOVEMENT_NUM_FACES (sizeof(watch_faces) / sizeof(watch_face_t))
#define MOVEMENT_SECONDARY_FACE_INDEX ]] .. secondary_face_index .. [[

#endif // MOVEMENT_CONFIG_H_
]]

f = assert(io.open(dir .. 'movement_config.h', 'w'))
f:write(movement_config)
f:close()

-- Generate list item in case build is successful
html_item = [[
    <li>
      <a href="]] .. dir .. [[">
        <strong>(]] .. table.concat(faces, ", ") .. [[) - (]] .. secondary_face_index .. [[)</strong>
      </a>
      -- ]] .. os.date("%c") .. [[
    </li>
]]
f = assert(io.open(dir .. 'build.html', 'w'))
f:write(html_item)
f:close()


-- Do the build
build_exit_code = os.execute('setsid --fork /code/start-build.sh ' .. dir)

if build_exit_code == nil then
  os.execute('rm -rf ' .. dir)
  ngx.status = 503
  ngx.say('<html><body>')
  ngx.say('Failed to trigger build')
  ngx.say('</body></html>')
  ngx.exit(ngx.HTTP_OK)
end

-- spinner from https://loading.io/css/
ngx.say([[
<html>
<head>
<style>
.lds-dual-ring {
  display: inline-block;
  width: 80px;
  height: 80px;
}
.lds-dual-ring:after {
  content: " ";
  display: block;
  width: 64px;
  height: 64px;
  margin: 8px;
  border-radius: 50%;
  border: 6px solid #000;
  border-color: #000 transparent #000 transparent;
  animation: lds-dual-ring 1.2s linear infinite;
}
@keyframes lds-dual-ring {
  0% {
    transform: rotate(0deg);
  }
  100% {
    transform: rotate(360deg);
  }
}
</style>
<script>

async function checkFinished() {
  try {
    const response = await fetch("]] .. dir .. [[")
    if (response.status === 200) {
      window.location.replace("]] .. dir .. [[")
    }
  } catch (e) {
  } finally {
    setTimeout(checkFinished, 1000);
  }
}

setTimeout(checkFinished, 2000);

</script>
</head>
<body>
<div class="lds-dual-ring"></div>
<p>Wait a couple of seconds (I hope) and the JS should take you to a build, or <a href="]] .. dir .. [[">click here</a></p>
<p>If that page is still not there after 30 seconds, something terrible has happened. It\'s probably your fault, and you should be sad.</p>
</body></html>
]])
ngx.exit(ngx.HTTP_OK)
