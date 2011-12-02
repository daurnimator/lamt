local assert , error = assert , error
local strsub = string.sub


-- Inserts the given string (block) at the current position in the file; moving all other data down.
-- Uses BLOCKSIZE chunks
local function file_insert ( fd , block , BLOCKSIZE )
	BLOCKSIZE = BLOCKSIZE or 2^20
	assert ( #block <= BLOCKSIZE )

	while true do
		local nextblock , e = fd:read ( BLOCKSIZE )

		local seekto
		if nextblock ~= nil then
			assert ( fd:seek ( "cur" , -#nextblock ) )
		elseif e then
			error ( e )
		end

		assert ( fd:write ( block ) )
		if nextblock == nil then break end
		assert ( fd:write ( strsub ( nextblock , 1 , BLOCKSIZE-#block ) ) )
		assert ( fd:flush ( ) )
		block = strsub ( nextblock , BLOCKSIZE-#block+1 , -1 )
	end
	assert ( fd:flush ( ) )
end

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
	file_insert = file_insert ;

	get_from_string = get_from_string ;
	get_from_fd = get_from_fd ;
}
