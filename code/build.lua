local etlua = require 'etlua'
local available_faces = require 'available_faces'
local resty_lock = require 'resty.lock'
local shell = require 'resty.shell'

function render(filename, env)
  local file, err = io.open('/templates/' .. filename)
  if not file then
    return nil, err
  end

  local s = file:read("*a")
  
  file:close()
  s, err = etlua.render(s, env)
  if err then
    ngx.log(ngx.CRIT, tostring(err))
  end
  return s, err
end

function render_to_file(template_filename, output, env)
  local s, err = render(template_filename, env)
  if not s then
    return false, err
  end

  if type(output) == 'string' then
    output, err = io.open(output, "w")
    if not output then
      return false, err
    end
    output:write(s)
    output:close()
  else
    output:write(s)
  end


  return true, nil
end

function abort_with_errors(errors)
  ngx.status = 503
  result, err = render('errors.html', {errors = errors})
  assert(result, "Unable to render error template (now we're in trouble!): " .. tostring(err))
  ngx.say(result)
  ngx.exit(ngx.HTTP_OK)
end

function exists(path)
  local file = io.open(path, "r")
  if (file ~= nil) then
    file:close()
    return true
  else
    return false
  end
end

-- make them all arrays
function normalise_post_arg(arg)
  if arg == nil then
    return {}
  elseif type(arg) == 'string' then
    return {arg}
  elseif arg then
    return arg
  end
end

function process_post_args(args)
  local errors = {}
  if args['faces'] == nil then
    table.insert(errors, 'No faces provided')
  end

  local faces = normalise_post_arg(args['faces'])
  local secondary_faces = normalise_post_arg(args['secondary_faces'])
  local combined_faces = {}

  for _, faces in ipairs({faces, secondary_faces}) do
    for _, face in ipairs(faces) do
      if available_faces[face] then
        table.insert(combined_faces, face)
      else
        table.insert(errors, 'Face ' .. face .. ' not recognised')
      end
    end
  end

  if #errors > 0 then
    abort_with_errors(errors)
  end

  if #secondary_faces == 0 then
    return combined_faces, 0
  else 
    return combined_faces, #faces
  end
end

function generate_build_hash(faces, secondary_face_index)
  return ngx.md5(table.concat(faces, ':') .. ':' .. secondary_face_index)
end

function update_build_list(dir, faces, secondary_face_index)
  local lock, err = resty_lock:new('build_locks')
  if lock then
    _, err = lock:lock('build_list')
  end

  if err then
    -- This is not a problem for the user, so silently fail for them.
    ngx.log(ngx.ERR, 'failed to acquire lock: ' .. tostring(err))
    return
  end

  local previous_builds = '/builds/list.html'
  local count = 0
  -- First, keep the last 50 lines.
  local lines = {}
  local pb_file = assert(io.open(previous_builds))
  for line in pb_file:lines() do
    count = count + 1
    table.insert(lines, line)
    if (count >= 49) then
      break
    end
  end
  pb_file:close()
  pb_file = assert(io.open(previous_builds, 'w'))
  assert(render_to_file('build_record.html', pb_file, {dir = dir, faces = faces, secondary_face_index = secondary_face_index}))
  for _, line in ipairs(lines) do
    pb_file:write(line)
  end
  pb_file:close()
  if not lock:unlock('build_list') then
    ngx.log(ngx.ERR, 'failed to release lock')
  end
end

function build(dir, faces, secondary_face_index)
  assert(shell.run('rm -rf ' .. dir .. ' && mkdir ' .. dir))
  assert(render_to_file('movement_config.h', dir .. 'movement_config.h', {faces = faces, secondary_face_index = secondary_face_index}))

  local ok, stdout, stderr, reason, status = shell.run([[PATH=/bin:/usr/bin exec flock -w 1 -E 250 /tmp/build-sensor-watch /code/build.sh "]] .. dir .. [["]], nil, 35000)
  if status == 250 then
    ngx.log(ngx.ERR, tostring(err))
    abort_with_errors({'Timed out waiting for build lock. System probably overloaded. Try again later.'})
  elseif ok == nil then
    ngx.log(ngx.CRIT, 'internal build error: ' .. tostring(reason))
    abort_with_errors({'Internal error trying to start build: ' .. tostring(reason)})
  end

  return ok, stdout, stderr
end


-- MAIN STUFF
post_args = ngx.req.get_post_args()
faces, secondary_face_index = process_post_args(post_args)
local dir = '/builds/' .. generate_build_hash(faces, secondary_face_index) .. '/'
if not exists(dir .. 'completed') or post_args['flush'] then
  ok, stdout, stderr = build(dir, faces, secondary_face_index)
  if ok then
    assert(render_to_file('success_build.html', dir .. 'index.html', {}))
    update_build_list(dir, faces, secondary_face_index)
  else
    ngx.log(ngx.WARN, 'Build failed: ' .. tostring(stderr))
    assert(render_to_file('fail_build.html', dir .. 'index.html', {stdout = stdout, stderr = stderr}))
  end

  -- touch file so we know this folder is "good"
  local completed_file = assert(io.open(dir .. 'completed', 'w'))
  completed_file:close()
end

ngx.redirect(dir)
