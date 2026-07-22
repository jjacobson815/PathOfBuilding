-- app/lua/lzip.lua
--
-- Minimal lzip stub for the Qt host. Real zip extraction (minizip / QuaZip /
-- Qt) is deferred to a later phase (the update feature, Phase 5/6). The only
-- requirement for Phase 0d is that `require("lzip")` succeeds and returns a
-- table; UpdateCheck.lua (the sole consumer) is never exercised by the
-- headless selftest, so a no-op open() is acceptable.

local lzip = { }

-- Returns nil so callers treat the archive as unavailable (no-op extraction).
function lzip.open(path)
    return nil
end

return lzip
