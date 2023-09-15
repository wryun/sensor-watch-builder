local etlua = require 'etlua'
local available_faces = require 'available_faces'
local resty_lock = require 'resty.lock'
local shell = require 'resty.shell'

local function render(filename, env)
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

local function render_to_file(template_filename, output, env)
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

local function abort_with_errors(errors)
  ngx.status = 503
  local result, err = render('errors.html', {errors = errors})
  assert(result, "Unable to render error template (now we're in trouble!): " .. tostring(err))
  ngx.say(result)
  ngx.exit(ngx.HTTP_OK)
end

local function exists(path)
  local file = io.open(path, "r")
  if (file ~= nil) then
    file:close()
    return true
  else
    return false
  end
end

-- make them all arrays
local function normalise_post_arg(arg)
  if arg == nil then
    return {}
  elseif type(arg) == 'string' then
    return {arg}
  elseif arg then
    return arg
  end
end

local function sanitise(arg)
    return arg:gsub("[^%w_]", "")
end

local function process_post_args(args)
  local errors = {}
  if args['faces'] == nil then
    table.insert(errors, 'No faces provided')
  end

  local defines = {}
  local makeargs = {}
  for k, v in pairs(args) do
    if k:match('^defgroup') then
      defines[v] = 1
    end
    local res = k:match('^makearg[-]([%u_]+)$')
    if res then
      makeargs[res] = sanitise(v)
    end
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
    return makeargs, defines, combined_faces, 0
  else 
    return makeargs, defines, combined_faces, #faces
  end
end

local function generate_build_hash(faces, secondary_face_index)
  return ngx.md5(table.concat(faces, ':') .. ':' .. secondary_face_index)
end

local function update_build_list(dir, makeargs, defines, faces, secondary_face_index)
  -- Read in existing 'previous builds'.
  local previous_builds = '/builds/list.html'
  local count = 0
  -- First, keep the last 30 lines.
  local lines = {}
  local pb_file = assert(io.open(previous_builds))
  for line in pb_file:lines() do
    count = count + 1
    table.insert(lines, line)
    if (count >= 29) then
      break
    end
  end
  pb_file:close()

  -- Update 'previous builds' with new entry.
  pb_file = assert(io.open(previous_builds, 'w'))
  pb_file:write(assert(render('build_record.html', {dir = dir, makeargs = makeargs, defines = defines, faces = faces, secondary_face_index = secondary_face_index})):gsub("\n", ""), "\n")
  for _, line in ipairs(lines) do
    pb_file:write(line, "\n")
  end
  pb_file:close()
end

local function build(dir, makeargs, defines, faces, secondary_face_index)
  assert(shell.run('rm -rf ' .. dir .. ' && mkdir ' .. dir))
  assert(render_to_file('movement_config.h', dir .. 'movement_config.h', {defines = defines, faces = faces, secondary_face_index = secondary_face_index}))

  local argslist = {}
  for k, v in pairs(makeargs) do
    table.insert(argslist, k .. '=' .. v)
  end

  local ok, stdout, stderr, reason, status = shell.run([[PATH=/bin:/usr/bin exec /code/build.sh "]] .. dir .. [[" ]] .. makeargs['COLOR'] .. ' ' .. table.concat(argslist, ' '), nil, 20000)
  if ok == nil then
    error('Internal error trying to start build: ' .. tostring(reason))
  end

  return ok, stdout, stderr
end

-- echoing a Python with block - trying to make sure we clean up our lock regardless of what happens in fn.
local function with_lock(fn)
  local lock, err = resty_lock:new('build_locks', {exptime = 30, timeout = 40, step = 0.5, max_step = 1})
  if lock == nil then
    error(err)
  end
  local elapsed
  elapsed, err = lock:lock('build')
  if elapsed == nil then
    return false, err
  end
  local ok
  ok, err = xpcall(fn, debug.traceback)
  -- not much to be done if the unlock fails here...
  lock:unlock()
  if not ok then
    error(err)
  end

  return true, nil
end


-- MAIN STUFF
local makeargs, defines, faces, secondary_face_index = process_post_args(ngx.req.get_post_args())
local dir = '/builds/' .. generate_build_hash(faces, secondary_face_index) .. '/'

if not exists(dir .. 'completed') then
  -- only one build at a time, please.
  -- NB we could support multiple builds targeting different dirs easily enough, but it
  -- might overload the system, so it's nicer to do one at a time. We could get cheap
  -- paralellism here by having a random number added to the lock, I guess...
  -- (as long as we also added a 'dir' lock and a 'build_list' lock separately).
  local ok, err = with_lock(function ()
    -- if someone got in before us and finished the job, nothing to do here.
    if exists(dir .. 'completed') then
      return
    end

    local ok, stdout, stderr = build(dir, makeargs, defines, faces, secondary_face_index)
    if ok then
      assert(render_to_file('success_build.html', dir .. 'index.html', {makeargs = makeargs, stdout = stdout, stderr = stderr}))
      update_build_list(dir, makeargs, defines, faces, secondary_face_index)
    else
      ngx.log(ngx.WARN, 'Build failed: ' .. tostring(stderr))
      assert(render_to_file('fail_build.html', dir .. 'index.html', {stdout = stdout, stderr = stderr}))
    end

    -- touch file so we know this dir is "good"
    local completed_file = assert(io.open(dir .. 'completed', 'w'))
    completed_file:close()
  end)

  if not ok then
    abort_with_errors({'Unable to acquire lock; builder probably overloaded: ' .. tostring(err)})
  end
end

ngx.redirect(dir)
