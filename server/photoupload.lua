-- ---------------------------------------------------------------------------
-- SERVER-SIDE PHOTO UPLOAD
--
-- Why this exists rather than the client doing the upload:
--
--   1. A Discord webhook URL is a credential. Anything in config/ ships to
--      every connecting client, so the old client-side
--      requestScreenshotUpload path handed the webhook to every player on
--      the server - they could pull it out and post to your channel at
--      will. Here the URL is read from a server convar and never leaves
--      the server.
--
--   2. It removes the size limit completely. screenshot-basic's SERVER
--      export uploads the capture to the server over HTTP instead of
--      through a net event, so FiveM's event size cap doesn't apply and
--      full-resolution photos work fine.
--
-- Set the webhook in server.cfg with `set` (NOT `setr` - setr replicates
-- to clients, which would undo the whole point):
--
--     set st_dealership:photoWebhook "https://discord.com/api/webhooks/..."
-- ---------------------------------------------------------------------------

local B64_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

local b64Lookup = {}
for i = 1, #B64_CHARS do
    b64Lookup[B64_CHARS:sub(i, i)] = i - 1
end

--- Decodes base64 to a raw byte string. Discord wants the actual image
--- bytes in a multipart body; it has no base64 intake.
local function base64Decode(input)
    input = input:gsub('[^' .. B64_CHARS .. '=]', '')

    local out = {}
    local bits, bitCount = 0, 0

    for i = 1, #input do
        local char = input:sub(i, i)
        if char ~= '=' then
            local value = b64Lookup[char]
            if value then
                bits = bits * 64 + value
                bitCount = bitCount + 6
                if bitCount >= 8 then
                    bitCount = bitCount - 8
                    local byte = math.floor(bits / (2 ^ bitCount)) % 256
                    out[#out + 1] = string.char(byte)
                end
            end
        end
    end

    return table.concat(out)
end

--- Splits "data:image/jpeg;base64,XXXX" into its mime type and payload.
local function parseDataUri(dataUri)
    local mime, payload = dataUri:match('^data:([%w/%-%.%+]+);base64,(.+)$')
    if not mime then return nil end
    return mime, payload
end

local function mimeToExtension(mime)
    if mime == 'image/png' then return 'png' end
    if mime == 'image/webp' then return 'webp' end
    return 'jpg'
end

function ST.GetPhotoWebhook()
    local url = GetConvar('st_dealership:photoWebhook', '')
    if url == '' then return nil end
    return url
end

--- POSTs raw image bytes to a Discord webhook as multipart/form-data and
--- hands back the CDN URL Discord responds with. `cb(url, errorReason)`.
local function uploadToDiscord(imageBytes, extension, description, cb)
    local webhook = ST.GetPhotoWebhook()
    if not webhook then
        cb(nil, 'no webhook configured')
        return
    end

    local boundary = ('----STDealership%d%d'):format(os.time(), math.random(100000, 999999))
    local filename = ('vehicle_%d.%s'):format(os.time(), extension)

    local body = table.concat({
        '--', boundary, '\r\n',
        'Content-Disposition: form-data; name="payload_json"\r\n',
        'Content-Type: application/json\r\n\r\n',
        json.encode({ content = description or '' }), '\r\n',

        '--', boundary, '\r\n',
        ('Content-Disposition: form-data; name="files[0]"; filename="%s"\r\n'):format(filename),
        'Content-Type: application/octet-stream\r\n\r\n',
        imageBytes, '\r\n',

        '--', boundary, '--\r\n',
    })

    PerformHttpRequest(webhook .. '?wait=true', function(status, response)
        if status ~= 200 and status ~= 201 then
            cb(nil, ('Discord rejected the upload (HTTP %s)'):format(tostring(status)))
            return
        end

        local ok, decoded = pcall(json.decode, response)
        local url = ok and decoded and decoded.attachments
            and decoded.attachments[1] and decoded.attachments[1].url

        if not url then
            cb(nil, 'Discord accepted the upload but returned no attachment URL')
            return
        end

        cb(url, nil)
    end, 'POST', body, {
        ['Content-Type'] = 'multipart/form-data; boundary=' .. boundary,
    })
end

--- Takes a photo on `src`'s client and returns a stored-ready string:
--- a Discord CDN URL when a webhook is configured, or the raw data URI
--- when it isn't. `cb(photoString, errorReason)`.
---
--- The capture itself comes back over screenshot-basic's own HTTP channel,
--- not a net event, so there is no size ceiling on this path.
function ST.CaptureClientPhoto(src, cb)
    if GetResourceState('screenshot-basic') ~= 'started' then
        cb(nil, "screenshot-basic isn't running on the server")
        return
    end

    local options = {
        encoding = Config.VehiclePhotos.encoding or 'jpg',
        quality = Config.VehiclePhotos.quality or 0.8,
    }

    local settled = false
    local function settle(result, reason)
        if settled then return end
        settled = true
        cb(result, reason)
    end

    -- If the client disconnects mid-capture the callback never fires, so
    -- the request is bounded rather than leaking a pending promise.
    SetTimeout(20000, function()
        settle(nil, 'the capture timed out')
    end)

    local ok, err = pcall(function()
        exports['screenshot-basic']:requestClientScreenshot(src, options, function(captureErr, data)
            if captureErr or not data then
                settle(nil, tostring(captureErr or 'no image data'))
                return
            end

            if not ST.GetPhotoWebhook() then
                -- No webhook: store the data URI as-is. It never crossed a
                -- net event to get here, so its size is not a problem.
                settle(data, nil)
                return
            end

            local mime, payload = parseDataUri(data)
            if not payload then
                settle(nil, 'the capture was not a readable image')
                return
            end

            uploadToDiscord(base64Decode(payload), mimeToExtension(mime), nil, function(url, uploadErr)
                settle(url, uploadErr)
            end)
        end)
    end)

    if not ok then
        settle(nil, 'screenshot-basic rejected the request: ' .. tostring(err))
    end
end

CreateThread(function()
    Wait(1000)
    if ST.GetPhotoWebhook() then
        print('[st_dealership] vehicle photos: uploading to Discord webhook (server-side)')
    else
        print('[st_dealership] vehicle photos: stored as base64 in the database. Set `st_dealership:photoWebhook` in server.cfg to upload to Discord instead.')
    end
end)
