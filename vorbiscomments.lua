--[[
	LOMP ( Lua Open Music Player )
	Copyright (C) 2007- daurnimator

	This program is free software: you can redistribute it and/or modify it under the terms of version 3 of the GNU General Public License as published by the Free Software Foundation.

	This program is distributed in the hope that it will be useful,	but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

	You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

require "general"

module ( "lomp.fileinfo.vorbiscomments" , package.see ( lomp ) )

require "vstruct"

_NAME = "Vorbis comments reader"

-- unpacks a string from file descriptor thats stored in with length (as unsigned 4 byte int) before it
function getstring ( fd )
	return vstruct.unpack ( "< s" .. 
		vstruct.unpack ( "< u4" , fd ) [ 1 ] -- length of string
	, fd ) [ 1 ]
end

function info ( fd , item )
	item.extra = item.extra or { }
	item.tags = item.tags or { }
	
	item.extra.vendor_string = getstring ( fd )
	
	for i = 1 , vstruct.unpack ( "< u4" , fd ) [ 1 ] do -- 4 byte interger indicating how many comments.
		local fieldname , value = string.match ( getstring ( fd ) , "([^=]+)=(.+)")
		fieldname = string.lower ( fieldname )
		item.tags [ fieldname ] = item.tags [ fieldname ] or { }
		table.insert ( item.tags [ fieldname ] , value )
	end
end
