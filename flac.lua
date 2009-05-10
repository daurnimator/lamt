--[[
	LOMP ( Lua Open Music Player )
	Copyright (C) 2007- daurnimator

	This program is free software: you can redistribute it and/or modify it under the terms of version 3 of the GNU General Public License as published by the Free Software Foundation.

	This program is distributed in the hope that it will be useful,	but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

	You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]

require "general"

module ( "lomp.fileinfo.flac" , package.see ( lomp ) )

require "vstruct"

_NAME = "FLAC reader"

function info ( fd )
	fd:seek ( "set" ) -- Rewind file to start
	-- Format info found at http://flac.sourceforge.net/format.html
	if fd:read ( 4 ) == "fLaC" then 
		local item = { format = "flac" , extra = { } }
		
		local t
		local tags = { }
		repeat
			t = vstruct.unpack ( "< m1 > u3" , fd )
			
			local lastmetadatablock = vstruct.implode { unpack ( t [ 1 ] , 8 , 8 ) }
			local blocktype = vstruct.implode { unpack ( t [ 1 ] , 1 , 7 ) }		
			local blocklength = t [ 2 ] -- Is in bytes
			
			--print ( lastmetadatablock , blocktype , blocklength )
			
			if blocktype == 0 then -- Stream info
				t = vstruct.unpack ( "> u2 u2 u3 u3 <m8> u16" , fd )
				item.extra.minblocksize = t [ 1 ]
				item.extra.maxblocksize = t [ 2 ]
				item.extra.minframesize = t [ 3 ]
				item.extra.maxframesize = t [ 4 ]
				item.extra.samplerate = vstruct.implode { unpack ( t [ 5 ] , 45 , 64 ) }
				item.extra.channels = vstruct.implode { unpack ( t [ 5 ] , 42 , 44 ) } + 1
				item.extra.bitspersample = vstruct.implode { unpack ( t [ 5 ] , 37 , 41 ) }
				item.extra.totalsamples = vstruct.implode { unpack ( t [ 5 ] , 1 , 36 ) }
				item.extra.md5rawaudio = t [ 6 ]
				item.extra.length = item.extra.totalsamples / item.extra.samplerate
				--t [ 1 ] = nil
				--samplerate = t [ 5 ]
				--channels = t [ 6 ] + 1
				--bitspersample = t [ 7 ]
				--totalsamples = t [ 8 ]
			elseif blocktype == 1 then -- Padding
				item.extra.padding = item.extra.padding or { }
				table.insert ( item.extra.padding , { start = fd:seek ( ) , length = blocklength , } )
				t = vstruct.unpack ( "> x" .. blocklength , fd )
			elseif blocktype == 2 then -- Application
				t = vstruct.unpack ( "> u4 s" .. ( blocklength - 4 ) , fd )
				item.extra.applications = item.extra.applications or { }
				table.insert ( item.extra.applications , { appID = t [ 1 ] , appdata = t [ 2 ] } )
			elseif blocktype == 3 then -- Seektable
				t = vstruct.unpack ( "> x" .. blocklength , fd ) -- We don't deal with seektables, skip over it
			elseif blocktype == 4 then -- Vorbis_Comment http://www.xiph.org/vorbis/doc/v-comment.html
				item.tagtype = "vorbis"
				item.extra.startvorbis = fd:seek ( ) - 4
				
				require "modules.fileinfo.vorbiscomments"
				
				t = vstruct.unpack ( "< u4" , fd )
				vendor_length = t [ 1 ]
				t = vstruct.unpack ( "< s" .. vendor_length .. "u4" , fd )
				item.extra.vendor_string = t [ 1 ]
				user_comment_list_length = t [ 2 ]
				
				local comment = { }
				for i = 1 , ( user_comment_list_length ) do
					t = vstruct.unpack ( "< u4" , fd )
					local length = t [ 1 ]
					t = vstruct.unpack ( "< s" .. length , fd )
					comment [ i ] = t [ 1 ]
					local fieldname , value = string.match ( comment [ i ] , "([^=]+)=(.+)")
					fieldname = string.lower ( fieldname )
					tags [ fieldname ] = tags [ fieldname ] or { }
					table.insert ( tags [ fieldname ] , value )
				end
			elseif blocktype == 5 then -- Cuesheet
				t = vstruct.unpack ( "> s128 u8 x259 x1 x" .. ( blocklength - ( 128 + 8 + 259 + 1 ) ) , fd ) -- cbf, TODO: cuesheet reading
			elseif blocktype == 6 then -- Picture
				t = vstruct.unpack ( "> u4 u4" , fd )
				picturetype = t [ 1 ]
				mimelength = t [ 2 ]
				t = vstruct.unpack ( "> s" .. mimelength .. "u4" , fd )
				mimetype = t [ 1 ]
				descriptionlength = t [ 2 ]
				t = vstruct.unpack ( "> s" .. descriptionlength .. " u4 u4 u4 u4 u4" , fd )
				width = t [ 1 ]
				height = t [ 2 ]
				colourdepth = t [ 3 ]
				numberofcolours = t [ 4 ]
				picturelength = t [ 5 ]
				t = vstruct.unpack ( "> s" .. picturelength , fd )
				picturedata = t [ 1 ]
			end
		until lastmetadatablock == 1
		item.length = math.floor( item.extra.length + 0.5 )
		item.tags = tags or { }
		return item
	else
		-- not a flac file
		return false
	end
end

function edit ( fd , tags )
	local item = info ( fd )
	
	local vendor_string = item.extra.vendor_string or "Xiph.Org libVorbis I 20020717"
	local vendor_length = string.len ( vendor_string )
	
	local commentcount = 0
	local s = ""
	for k , v in ipairs ( tags ) do
		for i , v in ipairs ( v ) do
			commentcount = commentcount + 1
			local comment = k .. "=" .. v
			local length = string.len ( comment )
			s = s .. vstruct.pack ( "u4 s" , length , comment )
		end
	end
	
	s = vstruct.pack ( "u4 s u4" , vendor_length , vendor_string , commentcount ) .. s
	local length = string.len ( s )
	s = vstruct.pack ( "u3" , length ) .. s
	
	local space_needed = string.len ( s )
	
	local oldblocksize = 0
	if item.extra.startvorbis then
		fd:seek ( item.extra.startvorbis + 1 )
		oldblocksize = vstruct.unpack ( "u3" , fd ) [ 1 ]
	end
	
	if space_needed ~= oldblocksize then
		-- Look for padding blocks
		if type ( item.extra.padding ) == "table" then
			
		end
		
		if space_needed < oldblocksize then
			
		else --space_needed > oldblocksize then
			
		end
	end
	
	-- Write
	
end
