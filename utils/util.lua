local _M = { _VERSION = '0.0.1' }   -- 局部变量，模块名称

-- 分割字符串
function _M.split( szFullString, szSeparator, ... )
	local nFindStartIndex = 1
	local nSplitIndex = 1
	local nSplitArray = {}
	while true do
		local nFindLastIndex = string.find(szFullString, szSeparator, nFindStartIndex,...)
		if not nFindLastIndex then
			nSplitArray[nSplitIndex] = string.sub(szFullString, nFindStartIndex, string.len(szFullString))
			break
		end
		nSplitArray[nSplitIndex] = string.sub(szFullString, nFindStartIndex, nFindLastIndex - 1)
		nFindStartIndex = nFindLastIndex + string.len(szSeparator)
		nSplitIndex = nSplitIndex + 1
	end
	return nSplitArray
end

function _M.strip(str)
    local r = str:gsub('^%s+', ''):gsub('%s+$', '')
    return r
end

function _M.isInTable(value, tbl)
	for k,v in ipairs(tbl) do
		if v == value then
		return true;
		end
	end
	return false;
end

return _M