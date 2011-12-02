local assert , error = assert , error
local strsub = string.sub

local function get_from_string ( s )
	local i = 0
	return function ( n )
		i = i + n
		if i > #s then return error ( "End of string" ) end
		return strsub ( s , i-n+1 , i )
	end
end

local function get_from_fd ( fd )
	return function ( n )
		local r = assert ( fd:read ( n ) )
		if #r < n then return error ( "End of string" ) end
		return r
	end
end

return {
	get_from_string = get_from_string ;
	get_from_fd = get_from_fd ;
}