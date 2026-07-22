-- app/lua/lcurl/safe.lua
--
-- Minimal *synchronous* lcurl.safe shim for Path of Building's Qt host.
--
-- It implements only the subset of the lcurl.safe `easy()` API that src/
-- actually calls (UpdateCheck, Launch, Common, TradeQueryGenerator,
-- BuildSiteTools, PoBArchivesProvider, TreeTab, PassiveTree,
-- CompareTradeHelpers, PartyTab) and delegates the real transfer to the C
-- bridge `pob.http` (libcurl, synchronous, see app/src/LuaEngine.cpp).
--
-- This is intentionally NOT a full lcurl port; it exists so the unmodified
-- src/ Lua engine can `require("lcurl.safe")` and run its HTTP call sites
-- headless. Async migration is a later-phase concern (Phase 5).

local curl = { }

-- Option constants. Where the value maps directly onto a pob.http option key
-- we use that key so setopt() can forward it transparently.
curl.OPT_URL             = "url"
curl.OPT_HTTPHEADER      = "httpheader"
curl.OPT_USERAGENT       = "useragent"
curl.OPT_ACCEPT_ENCODING = "accept_encoding"
curl.OPT_FOLLOWLOCATION  = "followlocation"
curl.OPT_POST            = "post"
curl.OPT_POSTFIELDS      = "postfields"
curl.OPT_IPRESOLVE       = "ipresolve"
curl.OPT_PROXY           = "proxy"
curl.OPT_SSL_VERIFYPEER  = "ssl_verifypeer"
curl.OPT_SSL_VERIFYHOST  = "ssl_verifyhost"
curl.OPT_WRITEFUNCTION   = "writefunction"
curl.OPT_HEADERFUNCTION  = "headerfunction"

-- Info constants (values index into the pob.http result table).
curl.INFO_RESPONSE_CODE  = "code"
curl.INFO_REDIRECT_URL   = "redirect_url"
curl.INFO_SIZE_DOWNLOAD  = "size"

-- IPRESOLVE constants — match libcurl (WHATEVER=0, V4=1, V6=2). The engine
-- passes its own connectionProtocol dropdown value (0/1/2) straight through.
curl.IPRESOLVE_WHATEVER = 0
curl.IPRESOLVE_V4       = 1
curl.IPRESOLVE_V6       = 2

-- Percent-encode a string the way lcurl's escape() does (unreserved set
-- [A-Za-z0-9-._~] left intact, everything else hex-encoded).
local function escape(s)
    if s == nil then return "" end
    s = tostring(s)
    return (s:gsub("([^%w%-_.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local easy_mt = { }
easy_mt.__index = easy_mt

function curl.easy()
    local self = {
        opts = { },
        writefunction = nil,
        headerfunction = nil,
        result = nil,
    }
    return setmetatable(self, easy_mt)
end

function easy_mt:setopt_url(url)
    self.opts.url = url
    return self
end

function easy_mt:setopt(opt, value)
    if opt == curl.OPT_POST then
        if value then self.opts.method = "POST" end
    elseif opt == curl.OPT_WRITEFUNCTION then
        self.writefunction = value
    elseif opt == curl.OPT_HEADERFUNCTION then
        self.headerfunction = value
    else
        self.opts[opt] = value
    end
    return self
end

function easy_mt:setopt_writefunction(fn)
    self.writefunction = fn
    return self
end

function easy_mt:setopt_headerfunction(fn)
    self.headerfunction = fn
    return self
end

function easy_mt:escape(s)
    return escape(s)
end

-- Perform the request via the C bridge and replay body/header through the
-- registered callbacks to mimic lcurl's streaming semantics.
function easy_mt:perform()
    local res = pob.http(self.opts)
    if not res then
        return nil, "pob.http returned no result"
    end
    if res.error then
        return nil, res.error
    end
    self.result = res
    if self.headerfunction and type(self.headerfunction) == "function" and res.header then
        self.headerfunction(res.header)
    end
    if self.writefunction and res.body then
        if type(self.writefunction) == "function" then
            self.writefunction(res.body)
        elseif type(self.writefunction) == "table" and self.writefunction.write then
            -- lcurl also accepts a file handle as the write target.
            self.writefunction:write(res.body)
        end
    end
    return 0, nil
end

function easy_mt:getinfo(info)
    local res = self.result
    if not res then return nil end
    if info == curl.INFO_SIZE_DOWNLOAD then
        return res.body and #res.body or 0
    elseif info == curl.INFO_RESPONSE_CODE then
        return res.code
    elseif info == curl.INFO_REDIRECT_URL then
        return res.redirect_url
    end
    return nil
end

function easy_mt:close()
    self.result = nil
    return self
end

return curl
