--[[
	LOMP ( Lua Open Music Player )
	Copyright (C) 2007- daurnimator

	This program is free software: you can redistribute it and/or modify it under the terms of version 3 of the GNU General Public License as published by the Free Software Foundation.

	This program is distributed in the hope that it will be useful,	but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

	You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

require "general"

module ( "lomp.fileinfo.ogg" , package.seeall )

require "vstruct"

function info ( item )
	fd = io.open ( item.path , "rb" )
	
	local t = vstruct.unpack ( "< magic:s4 version:u1 header_type_flag:m1 granule_position:i8 bitstream_serial_number:u4 page_sequence_number:u4 CRC_checksum:i4 number_page_segments:u1" , fd )
end

function edit ( item , edits , inherit )

end

return { {} , info , edit }
