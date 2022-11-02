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

local md5 = require '/code/md5'
local m = md5.new()
for i, face in ipairs(faces) do
  m:update(i .. face)
end
m:update(tostring(secondary_face_index))

dir = '/builds/' .. md5.tohex(m:finish()) .. '/'

if args['flush'] then
  os.execute('rm -rf ' .. dir)
end

if exists(dir) then
  ngx.redirect(dir)
end

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

movement_config_fname = dir .. 'movement_config.h'
f = assert(io.open(movement_config_fname, 'w'))
f:write(movement_config)
f:close()


-- Do the build
build_exit_code = os.execute('setsid --fork flock /tmp/build-sensor-watch /code/build.sh ' .. dir)

if build_exit_code == nil then
  os.execute('rm -rf ' .. dir)
  ngx.status = 503
  ngx.say('<html><body>')
  ngx.say('Failed to trigger build')
  ngx.say('</body></html>')
  ngx.exit(ngx.HTTP_OK)
end

ngx.say('<html><body>')
ngx.say('<p>Wait a couple of seconds (I hope), then <a href="' .. dir .. '">click here</a>.<p>')
ngx.say('<p>If that 404s after 30 seconds, something terrible has happened. It\'s probably your fault, and you should be sad.</p>')
ngx.say('</body></html>')
ngx.exit(ngx.HTTP_OK)
