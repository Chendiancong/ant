local rdebug = require 'remotedebug'
local cdebug = require 'debugger.core'
local json = require 'cjson'
local variables = require 'new-debugger.worker.variables'
local source = require 'new-debugger.worker.source'
local breakpoint = require 'new-debugger.worker.breakpoint'

local state = 'running'
local stopReason = 'unknown'
local stepLevel = -1
local stepContext = ''
local stepCurrentLevel = -1

local CMD = {}

local masterThread = cdebug.start('worker', function(msg)
    local pkg = assert(json.decode(msg))
    if CMD[pkg.cmd] then
        CMD[pkg.cmd](pkg)
    end
end)

local function sendToMaster(msg)
    masterThread:send(assert(json.encode(msg)))
end

breakpoint.event(function(reason, bp)
    sendToMaster {
        cmd = 'eventBreakpoint',
        reason = reason,
        breakpoint = bp,
    }
end)

function CMD.stackTrace(pkg)
    local startFrame = pkg.startFrame
    local endFrame = pkg.endFrame
    local curFrame = 0
    local depth = 0
    local info = {}
    local res = {}

    while rdebug.getinfo(depth, info) do
        if curFrame ~= 0 and ((curFrame < startFrame) or (curFrame >= endFrame)) then
            depth = depth + 1
            curFrame = curFrame + 1
            goto continue
        end
        if info.what == 'C' and curFrame == 0 then
            depth = depth + 1
            goto continue
        end
        if (curFrame < startFrame) or (curFrame >= endFrame) then
            depth = depth + 1
            curFrame = curFrame + 1
            goto continue
        end
        curFrame = curFrame + 1
        if info.what == 'C' then
            res[#res + 1] = {
                id = depth,
                name = info.what == 'main' and "[main chunk]" or info.name,
                line = 0,
                column = 0,
                presentationHint = 'label',
            }
        else
            local src = source.create(info.source)
            if source.valid(src) then
                res[#res + 1] = {
                    id = depth,
                    name = info.what == 'main' and "[main chunk]" or info.name,
                    line = info.currentline,
                    column = 1,
                    source = source.output(src),
                }
            else 
                res[#res + 1] = {
                    id = depth,
                    name = info.what == 'main' and "[main chunk]" or info.name,
                    line = info.currentline,
                    column = 1,
                    presentationHint = 'label',
                }
            end
        end
        depth = depth + 1
        ::continue::
    end
    sendToMaster {
        cmd = 'stackTrace',
        command = pkg.command,
        seq = pkg.seq,
        stackFrames = res,
        totalFrames = curFrame
    }
end

function CMD.source(pkg)
    sendToMaster {
        cmd = 'source',
        command = pkg.command,
        seq = pkg.seq,
        content = source.getCode(pkg.sourceReference),
    }
end

function CMD.scopes(pkg)
    sendToMaster {
        cmd = 'scopes',
        command = pkg.command,
        seq = pkg.seq,
        scopes = variables.scopes(pkg.frameId),
    }
end

function CMD.variables(pkg)
    local vars, err = variables.variables(pkg.frameId, pkg.valueId)
    if not vars then
        sendToMaster {
            cmd = 'variables',
            command = pkg.command,
            seq = pkg.seq,
            success = false,
            message = err,
        }
        return
    end
    sendToMaster {
        cmd = 'variables',
        command = pkg.command,
        seq = pkg.seq,
        success = true,
        variables = vars,
    }
end

function CMD.setBreakpoints(pkg)
    if not source.valid(pkg.source) then
        return
    end
    breakpoint.update(pkg.source, pkg.breakpoints)
end

function CMD.stop(pkg)
    state = 'stopped'
    stopReason = pkg.reason
end

function CMD.run(pkg)
    state = 'running'
end

function CMD.stepOver(pkg)
    state = 'stepOver'
    stepContext = rdebug.context()
    stepLevel = rdebug.stacklevel()
    stepCurrentLevel = stepLevel
end

function CMD.stepIn(pkg)
    state = 'stepIn'
    stepContext = ''
end

function CMD.stepOut(pkg)
    state = 'stepOut'
    stepContext = rdebug.context()
    stepLevel = rdebug.stacklevel() - 1
    stepCurrentLevel = stepLevel
end

local function runLoop(reason)
    sendToMaster {
        cmd = 'eventStop',
        reason = reason,
    }

    while true do
        cdebug.sleep(10)
        masterThread:update()
        if state ~= 'stopped' then
            variables.clean()
            return
        end
    end
end

local hook = {}

hook['update'] = function()
    masterThread:update()
end

hook['call'] = function()
    local currentContext = rdebug.context()
    if currentContext == stepContext then
        stepCurrentLevel = stepCurrentLevel + 1
    end
    bp_list = nil
    rdebug.hookmask "crl"
end

hook['return'] = function ()
    local currentContext = rdebug.context()
    if currentContext == stepContext then
        stepCurrentLevel = rdebug.stacklevel() - 1
    end
    bp_list = nil
    rdebug.hookmask "crl"
end

hook['tail call'] = function ()
    bp_list = nil
    rdebug.hookmask "crl"
end

hook['line'] = function(line)
    local bp = breakpoint.find(line)
    if bp then
        state = 'stopped'
        runLoop('breakpoint')
        return
    end

    masterThread:update()
    if state == 'running' then
        return
    elseif state == 'stepOver' or state == 'stepOut' then
        local currentContext = rdebug.context()
        if currentContext ~= stepContext or stepCurrentLevel > stepLevel then
            return
        end
        state = 'stopped'
    elseif state == 'stepIn' then
        state = 'stopped'
    end
    if state == 'stopped' then
        runLoop(stopReason)
    end
end

rdebug.hookmask "cr"

rdebug.sethook(function(event, line)
    xpcall(function()
        if hook[event] then
            hook[event](line)
        end
    end, debug.traceback)
end)
