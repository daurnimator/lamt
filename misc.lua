local rel_dir = assert ( debug.getinfo ( 1 , "S" ).source:match ( [=[^@(.-[/\]?)[^/\]*$]=] ) , "Current directory unknown" ) .. "./"
package.path = package.path .. ";" .. rel_dir .. "?/init.lua"

local assert , error = assert , error
local strfind , strsub = string.find , string.sub
local tblinsert , tblconcat = table.insert , table.concat
local os_date , os_time = os.date , os.time

local iconv = require "iconv"

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

local function get_from_string ( s , i )
	i = i or 1
	return function ( n )
		if not n then -- Rest of string
			n = #s - i
		end
		i = i + n
		assert ( i-1 <= #s , "Unable to read enough characters" )
		return strsub ( s , i-n , i-1 )
	end , function ( new_i )
		if new_i then i = new_i end
		return i
	end
end

local function get_from_fd ( fd )
	return function ( n )
		if not n then
			return assert ( fd:read ( "*a" ) )
		else
			local r = assert ( fd:read ( n ) )
			if #r < n then return error ( "Unable to read enough characters" ) end
			return r
		end
	end , function ( newpos )
		if newpos then return assert ( fd:seek ( "set" , newpos ) ) end
		return assert ( fd:seek ( ) )
	end
end

local function string_to_array_of_chars ( s )
	local t = { }
	for i = 1 , #s do
		t [ i ] = strsub ( s , i , i )
	end
	return t
end

local function read_terminated_string ( get , terminators )
	local terminators = string_to_array_of_chars ( terminators or "\0" )
	local str = { }
	local found = 0
	while found < #terminators do
		local c = get ( 1 )
		if c == terminators [ found + 1 ] then
			found = found + 1
		else
			found = 0
		end
		tblinsert ( str , c )
	end
	return tblconcat ( str , "" , 1 , #str - #terminators )
end

-- Explodes a string on seperator
function strexplode ( str , seperator , plain )
	if type ( seperator ) ~= "string" or seperator == "" then
		error ( "Provide a valid seperator (a string of length >= 1)" )
	end

	local t , nexti = { } , 1
	local pos = 1
	while true do
		local st , sp = strfind ( str , seperator , pos , plain )
		if not st then break end -- No more seperators found

		if pos ~= st then
			t [ nexti ] = strsub ( str , pos , st - 1 ) -- Attach chars left of current divider
			nexti = nexti + 1
		end
		pos = sp + 1 -- Jump past current divider
	end
	t [ nexti ] = strsub ( str , pos ) -- Attach chars right of last divider
	return t
end

local function text_encoding ( str , from , to )
	local c = iconv.new ( from , to )
	return c ( str )
end

local date_mt = {
	__tostring = function ( t )
		local date = ""
		if rawget ( t , "year" ) then
			date = date .. "%Y"
			if rawget ( t , "month" ) then
				date = date .. "-%m"
				if rawget ( t , "day" ) then
					date = date .. "-%d"
				end
			end
		end

		local time = ""
		if rawget ( t , "hour" ) and rawget ( t , "min" ) then
			time = "T%H:%M"
			if rawget ( t , "sec" ) then
				time = time .. ":%S"
			end
			time = time .. "+%Z"
		end

		return os_date ( date .. time , os_time ( t ) )
	end ;
	__index = function ( t , k )
		return 0
	end ;
}
local function new_date ( t )
	return setmetatable ( t , date_mt )
end

return {
	file_insert = file_insert ;

	get_from_string = get_from_string ;
	get_from_fd = get_from_fd ;

	read_terminated_string = read_terminated_string ;

	strexplode = strexplode ;

	text_encoding = text_encoding ;

	new_date = new_date ;
}
