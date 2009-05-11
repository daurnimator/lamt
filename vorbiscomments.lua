--[[
	LOMP ( Lua Open Music Player )
	Copyright (C) 2007- daurnimator

	This program is free software: you can redistribute it and/or modify it under the terms of version 3 of the GNU General Public License as published by the Free Software Foundation.

	This program is distributed in the hope that it will be useful,	but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

	You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

require "general"

module ( "lomp.fileinfo.vorbiscomments" , package.seeall )

require "vstruct"

_NAME = "Vorbis comment tag reader/writer"
-- Vorbis_Comment http://www.xiph.org/vorbis/doc/v-comment.html

function info ( fd , item )
	item.extra = item.extra or { }
	item.tags = item.tags or { }
	
	item.extra.vendor_string = vstruct.unpack ( "< c4" , fd ) [ 1 ]
	
	for i = 1 , vstruct.unpack ( "< u4" , fd ) [ 1 ] do -- 4 byte interger indicating how many comments.
		local fieldname , value = string.match ( vstruct.unpack ( "< c4" , fd ) [ 1 ] , "([^=]+)=(.+)")
		fieldname = string.lower ( fieldname )
		item.tags [ fieldname ] = item.tags [ fieldname ] or { }
		table.insert ( item.tags [ fieldname ] , value )
	end
end

function generatetag ( tags )
	local vendor_string = core._PROGRAM .. " " .. _NAME
	
	local vstructstring = "< "
	local vstructdata = { }
	
	vstructstring  = vstructstring  .. "{ u4 s } "
	table.insert ( vstructdata , { #vendor_string , vendor_string } )
	
	local commenttbl = { }
	for k , v in pairs ( tags ) do
		k = string.lower (  string.gsub ( k , "=" , "" ) ) -- Remove any equals signs, change to lowercase
		for i , v in ipairs ( v ) do
			local str = k .."="..v
			table.insert ( commenttbl ,  { #str , str } )
		end
	end
	vstructstring = vstructstring .. "u4 { " .. #commenttbl .. " * { u4 s } } "
	table.insert ( vstructdata , #commenttbl )
	table.insert ( vstructdata , commenttbl )
	
	return vstruct.pack ( vstructstring , vstructdata )
end
