--[[
	LOMP ( Lua Open Music Player )
	Copyright (C) 2007- daurnimator

	This program is free software: you can redistribute it and/or modify it under the terms of version 3 of the GNU General Public License as published by the Free Software Foundation.

	This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

	You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

local ipairs = ipairs

module ( "lomp.fileinfo.tagfrompath" , package.see ( lomp ) )

local subs = {
	["album artist"] = "([^/]+)" ,
	["artist"] = "([^/]+)" ,
	["album"] = "([^/]+)" ,
	["year"] = "(%d%d%d%d)" ,
	["track"] = "(%d+)" ,
	["title"] = "([^/]+)" ,
	["release"] = "([^/]+)" ,
}

function info ( path , pattern , donotescapepattern )
	if not pattern then return false end
	local a = { }
	if not donotescapepattern then pattern = pattern:gsub ( "[%%%.%^%$%+%*%[%]%-%(%)]" , function ( str ) return "%" .. str end ) end-- Escape any characters that may need it except "?"
	pattern = pattern:gsub ( "//_//" , "[^/]-" ) -- Junk operator
	pattern = pattern:gsub ( "//([^/]-)//" , 
		function ( tag ) 
			tag = tag:lower ( ) 
			a [ #a + 1 ] = tag 
			return subs [ tag ] 
		end )
	pattern = pattern .. "%.[^/]-$" -- extension
	local r = { path:match ( pattern ) }
	
	local t = { }
	for i , v in ipairs ( a ) do
		t [ v ] = r [ i ]
	end
	return t
end
