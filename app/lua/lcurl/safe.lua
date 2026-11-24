-- app/lua/lcurl/safe.lua
--
-- Minimal lcurl.safe shim for Path of Building's Qt host.
--
-- Implements the subset of the lcurl.safe `easy()` API that src/ calls
-- (UpdateCheck, Launch, Common, TradeQueryGenerator, BuildSiteTools,
-- PoBArchivesProvider, TreeTab, PassiveTree, CompareTradeHelpers, PartyTab)
-- and delegates the transfer to `pob.http` (off-UI-thread libcurl inside
-- SubScriptManager worker states, or synchronous libcurl on main state).

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
curl.OPT_TIMEOUT         = "timeout"
curl.OPT_CONNECTTIMEOUT  = "connecttimeout"
curl.OPT_WRITEFUNCTION   = "writefunction"
curl.OPT_HEADERFUNCTION  = "headerfunction"

-- Info constants (values index into the pob.http result table).
curl.INFO_RESPONSE_CODE  = "code"
curl.INFO_REDIRECT_URL   = "redirect_url"
curl.INFO_EFFECTIVE_URL  = "effective_url"
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
curl.escape = escape

-- lcurl error object: Launch.lua:316 & UpdateCheck.lua:45 call `error:msg()`,
-- while diagnostic logging may also pass the error to `tostring(error)`.
local err_mt = { }
err_mt.__index = err_mt

function err_mt:msg()
    return self._msg
end

function err_mt:no()
    return self._no or -1
end

function err_mt:name()
    return self._name or "CURLE_ERROR"
end

function err_mt:__tostring()
    return self._msg
end

local function make_error(msg, no, name)
    if type(msg) == "table" and getmetatable(msg) == err_mt then
        return msg
    end
    return setmetatable({
        _msg = tostring(msg or "unknown curl error"),
        _no = no or -1,
        _name = name or "CURLE_ERROR",
    }, err_mt)
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

function easy_mt:setopt_useragent(ua)
    self.opts.useragent = ua
    return self
end

function easy_mt:setopt_post(v)
    if v and v ~= 0 then
        self.opts.method = "POST"
    else
        self.opts.method = "GET"
    end
    return self
end

function easy_mt:setopt_postfields(v)
    self.opts.postfields = v
    if v ~= nil then
        self.opts.method = "POST"
    end
    return self
end

function easy_mt:setopt_httpheader(v)
    self.opts.httpheader = v
    return self
end

function easy_mt:setopt_accept_encoding(v)
    self.opts.accept_encoding = v
    return self
end

function easy_mt:setopt_followlocation(v)
    self.opts.followlocation = v
    return self
end

function easy_mt:setopt_ipresolve(v)
    self.opts.ipresolve = v
    return self
end

function easy_mt:setopt_proxy(v)
    self.opts.proxy = v
    return self
end

function easy_mt:setopt_ssl_verifypeer(v)
    self.opts.ssl_verifypeer = v
    return self
end

function easy_mt:setopt_ssl_verifyhost(v)
    self.opts.ssl_verifyhost = v
    return self
end

function easy_mt:setopt_timeout(v)
    self.opts.timeout = v
    return self
end

function easy_mt:setopt_connecttimeout(v)
    self.opts.connecttimeout = v
    return self
end

function easy_mt:setopt(opt, value)
    if opt == curl.OPT_POST then
        if value and value ~= 0 then
            self.opts.method = "POST"
        else
            self.opts.method = "GET"
        end
    elseif opt == curl.OPT_POSTFIELDS then
        self.opts.postfields = value
        if value ~= nil then
            self.opts.method = "POST"
        end
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
    local res, httpErr = pob.http(self.opts)
    if not res then
        self.result = nil
        return nil, make_error(httpErr or "pob.http returned no result")
    end
    if res.error then
        self.result = res
        return nil, make_error(res.error)
    end
    self.result = res
    if self.headerfunction and type(self.headerfunction) == "function" and res.header then
        self.headerfunction(res.header)
    end
    if self.writefunction and res.body then
        if type(self.writefunction) == "function" then
            self.writefunction(res.body)
        elseif type(self.writefunction) == "table" and self.writefunction.write then
            -- lcurl also accepts a file handle as the write target (UpdateCheck.lua:73).
            self.writefunction:write(res.body)
        end
    end
    return true, nil
end

function easy_mt:getinfo(info)
    local res = self.result
    if not res then
        if info == curl.INFO_RESPONSE_CODE or info == curl.INFO_SIZE_DOWNLOAD then
            return 0
        end
        return nil
    end
    if info == curl.INFO_SIZE_DOWNLOAD then
        return res.body and #res.body or 0
    elseif info == curl.INFO_RESPONSE_CODE then
        return res.code or 0
    elseif info == curl.INFO_REDIRECT_URL then
        return res.redirect_url
    elseif info == curl.INFO_EFFECTIVE_URL then
        return res.effective_url
    end
    return nil
end

-- Shorthand info getters called by BuildSiteTools.lua:72 & PoBArchivesProvider.lua:72.
function easy_mt:getinfo_response_code()
    return self:getinfo(curl.INFO_RESPONSE_CODE) or 0
end

function easy_mt:getinfo_redirect_url()
    return self:getinfo(curl.INFO_REDIRECT_URL)
end

function easy_mt:getinfo_effective_url()
    return self:getinfo(curl.INFO_EFFECTIVE_URL)
end

function easy_mt:getinfo_size_download()
    return self:getinfo(curl.INFO_SIZE_DOWNLOAD) or 0
end

function easy_mt:close()
    self.result = nil
    return self
end

return curl
