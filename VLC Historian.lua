-------------------------------------------------------------------------------------------
-- VLC Addon: VLC Historian
-- p8np - 2022
-- MIT License
-------------------------------------------------------------------------------------------
-- Installation, drop this file in the extensions directory...
--  The extension must me activated when you run VLC
--
-- Linux:   /usr/lib/vlc/lua/extensions/
-- Windows: %ProgramFiles%\VideoLAN\VLC\lua\extensions\
-- Mac:     /Applications/VLC.app/Contents/MacOS/share/lua/extensions/
-------------------------------------------------------------------------------------------

-------------------------------------------------------------------------------------------
-- Extension VLC Registration Parameters
-------------------------------------------------------------------------------------------
vlc_cfg =
{ title = "VLC Historian",
  version = "1.0",
  author = "p8np",
  url = "https://github.com/p8np/VLC-Historian",
  description = "Track what content is played through VLC via http POST message.",
  capabilities = { "input-listener" }
}

-------------------------------------------------------------------------------------------
-- Setup information for VLC
-------------------------------------------------------------------------------------------
function descriptor()
  return vlc_cfg
end

-------------------------------------------------------------------------------------------
-- Extension parameters (later- set by dialog)
-- in my case, the path for the POST is formed by 3 parameters:
--     /evt/<app-code>/<user-code>/<auth-code>
-------------------------------------------------------------------------------------------
app_cfg =
{ host = "ripley.plb",
  port = "8081",
  evt_app_code = "01234567890",
  evt_user_code = "1",
  evt_auth_code = "0"
}

-------------------------------------------------------------------------------------------
-- activate addon, initialize
-------------------------------------------------------------------------------------------
function activate()
  vlc.msg.dbg("Activate " .. vlc_cfg["title"] .. " version {" .. vlc_cfg["version"] .. "}")
end

-------------------------------------------------------------------------------------------
-- deactivate addon
-------------------------------------------------------------------------------------------
function deactivate()
  vlc.msg.dbg("Deactivate " .. vlc_cfg["title"] .. " version {" .. vlc_cfg["version"] .. "}")
end

-------------------------------------------------------------------------------------------
-- Make the POST path on the host - Used in input_changed
-------------------------------------------------------------------------------------------
function make_path()
  return "/evt/" .. app_cfg["evt_app_code"] .. "/"
    .. app_cfg["evt_user_code"] .. "/" .. app_cfg["evt_auth_code"]
end

-------------------------------------------------------------------------------------------
--
-------------------------------------------------------------------------------------------
function meta_changed()
end

-------------------------------------------------------------------------------------------
-- This global prevents duplicate messages for the same song, sometimes VLC signals
--  input_changed more often than I expect, and song restarts don't concern me.
-------------------------------------------------------------------------------------------
g_last_uri = "";

-------------------------------------------------------------------------------------------
-- Input changed event from VLC
-------------------------------------------------------------------------------------------
function input_changed()
  if not vlc.input.is_playing() then return end
  if vlc.playlist.status() ~= "playing" then return end
  local dttm = os.date("%Y-%m-%d-%H-%M-%S-%Z")

  -- sometimes, input_changed is called before the meta-data is available,
  -- got this logic from vlc...
  --    https://github.com/videolan/vlc/blob/master/share/lua/intf/dumpmeta.lua
  -- probably should add some upper limit on iterations to prevent endless condition,
  -- trust for now.
  local item
  repeat
      item = vlc.input.item()
  until (item and item:is_preparsed())

  -- not really possible, but accept defeat.
  if not item then return end

  -- vlc: preparsing doesn't always provide all the information we want (like duration)
  -- me: i think this is waiting for the content buffers to start loading, which is probably after
  -- all the metadata and item members are set.
  repeat
  until (item:stats()["demux_read_bytes"] > 0)

  -- make sure this is not a repeat of the last item.
  if g_last_uri == item:uri() then return end
  g_last_uri = item:uri()

  -- still cautious about meta data reliability
  local meta_inf = item:metas()
  local title=""
  local artist=""
  if meta_inf ~= nil then
    title = clean_for_json(meta_inf["title"])
    artist = clean_for_json(meta_inf["artist"])
  end

  -- forming my POST body in JSON
  local post_body = '{ "dttm": "' .. dttm .. '", "title": "'
    .. title .. '", "artist": "' .. artist .. '", "uri": "' .. g_last_uri .. '" }'
  -- vlc.msg.dbg("++++++++ " .. post_body)

  http_post(post_body, app_cfg["host"], app_cfg["port"], make_path())
end

-------------------------------------------------------------------------------------------
-- remove double quotes and prevent nil
-------------------------------------------------------------------------------------------
function clean_for_json(str)
  if str == nil then return "" end
  if string.find(str, '"') == nil then return str end
  return str:gsub('"', '')
end

-------------------------------------------------------------------------------------------
-- Do the POST work
-- got this from approxiblue at ...
--    https://stackoverflow.com/questions/15795385/how-can-i-write-a-plugin-for-vlc-that-responds-to-play-pause-and-stop-events
-------------------------------------------------------------------------------------------
function http_post(body, host, port, path)
  local header =
  { "POST "..path.." HTTP/1.1",
    "Host: "..host,
    "Content-Type: application/json",
    "Content-Length: " .. string.len(body),
    "",
    ""
  }
  local request = table.concat(header, "\r\n") .. body
  local fd = vlc.net.connect_tcp(host, port)
  if not fd then return false end
  local pollfds = {}
  pollfds[fd] = vlc.net.POLLIN
  vlc.net.send(fd, request)
  vlc.net.poll(pollfds)
  local chunk = vlc.net.recv(fd, 2048)
  while chunk do
    vlc.net.poll(pollfds)
    chunk = vlc.net.recv(fd, 1024)
  end
  vlc.net.close(fd)
end

-- EOF
