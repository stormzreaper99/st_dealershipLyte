--- Creates a dealership job with 5 grades (0=Sales, 1=Service,
--- 2=Finance/Inventory, 3=Management, 4=Owner) matching the permission
--- tiers st_dealership already expects (Config.DefaultGradeRequirements -
--- grade 4 in particular has to exist or nobody could ever reach Owner
--- for this job).
---
--- qbx_core has no jobs *database table* to write to - jobs live in
--- qbx_core/shared/jobs.lua, and its job-editing exports
--- (UpsertJobData/UpsertJobGrade) are explicitly documented as
--- runtime-only: they don't touch any file and don't survive a restart.
--- So this does both layers:
---   1. Calls those exports for immediate, same-session use - no restart
---      needed to start assigning people to it right away.
---   2. Appends the same job definition into shared/jobs.lua on disk, so
---      it's also there normally after the next restart. The resulting
---      file content is verified with Lua's own `load()` before it's
---      ever written - if that check fails for any reason, the file is
---      left completely untouched and only the runtime layer applies.
local GRADE_DEFS = {
    { level = 0, name = 'Sales Associate',    payment = 50 },
    { level = 1, name = 'Service Technician', payment = 60 },
    { level = 2, name = 'Finance Manager',    payment = 75 },
    { level = 3, name = 'General Manager',    payment = 100 },
    { level = 4, name = 'Owner',              payment = 150, isboss = true },
}

local function escapePattern(s)
    return (s:gsub('[%^%$%(%)%%%.%[%]%*%+%-%?]', '%%%1'))
end

local function applyRuntimeJob(jobName, label)
    if GetResourceState('qbx_core') ~= 'started' then return false end

    return pcall(function()
        exports.qbx_core:UpsertJobData(jobName, {
            label = label, defaultDuty = true, offDutyPay = false,
        })
        for _, g in ipairs(GRADE_DEFS) do
            exports.qbx_core:UpsertJobGrade(jobName, g.level, {
                name = g.name, payment = g.payment, isboss = g.isboss or nil,
            })
        end
    end)
end

local function buildJobLuaSnippet(jobName, label)
    local gradeLines = {}
    for _, g in ipairs(GRADE_DEFS) do
        gradeLines[#gradeLines + 1] = g.isboss
            and ('            [%d] = { name = %q, payment = %d, isboss = true },'):format(g.level, g.name, g.payment)
            or  ('            [%d] = { name = %q, payment = %d },'):format(g.level, g.name, g.payment)
    end

    return ('\n    [%q] = {\n        label = %q,\n        defaultDuty = true,\n        offDutyPay = false,\n        grades = {\n%s\n        },\n    },\n'):format(
        jobName, label, table.concat(gradeLines, '\n')
    )
end

--- Returns runtimeOk (bool), fileResult (string) describing what happened
--- to shared/jobs.lua: 'persisted' | 'already_in_file' | 'no_file' |
--- 'unrecognized_file_shape' | 'parse_check_failed' | 'file_write_failed'.
function ST.CreateDealershipJob(jobName, label)
    local runtimeOk = applyRuntimeJob(jobName, label)

    local content = LoadResourceFile('qbx_core', 'shared/jobs.lua')
    if not content then
        return runtimeOk, 'no_file'
    end

    -- Already defined in the file (e.g. re-creating a dealership under a
    -- name that used to exist) - leave the file alone, the runtime layer
    -- above already makes it usable again.
    if content:find('%[%s*[\'"]' .. escapePattern(jobName) .. '[\'"]%s*%]') then
        return runtimeOk, 'already_in_file'
    end

    local closePos = content:match('()%}%s*$')
    if not closePos then
        return runtimeOk, 'unrecognized_file_shape'
    end

    local snippet = buildJobLuaSnippet(jobName, label)
    local newContent = content:sub(1, closePos - 1) .. snippet .. content:sub(closePos)

    -- Never write anything that doesn't actually parse as valid Lua -
    -- verified with load(), not assumed.
    local chunk, parseErr = load(newContent, 'jobs.lua')
    if not chunk then
        print(('[st_dealership] Could not safely add job "%s" to qbx_core/shared/jobs.lua (parse check failed): %s'):format(jobName, tostring(parseErr)))
        return runtimeOk, 'parse_check_failed'
    end

    -- Single-slot backup of the pre-change file, just in case.
    SaveResourceFile('qbx_core', 'shared/jobs.lua.st_dealership_backup', content, -1)
    local saved = SaveResourceFile('qbx_core', 'shared/jobs.lua', newContent, -1)

    if not saved then
        return runtimeOk, 'file_write_failed'
    end

    return runtimeOk, 'persisted'
end
