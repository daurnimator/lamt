require "vstruct"

print("FLAC reader")

file = "/media/temp/Done Torrents/Gotye - Like Drawing Blood (2006) [FLAC]/03 - Hearts A Mess.flac"

print(file)

fd = io.open ( file , r )
local s = fd:read ( 4 )

-- Format info found at http://flac.sourceforge.net/format.html
if s == "fLaC" then 
	filetyp = "flac"
	local t
	local sampleinfo = { }
	local tags = { }
	repeat
		t = vstruct.unpack ( "< m1 > u3" , fd )
		
		local lastmetadatablock = vstruct.implode { unpack ( t [ 1 ] , 8 , 8 ) }
		local blocktype = vstruct.implode { unpack ( t [ 1 ] , 1 , 7 ) }		
		local blocklength = t [ 2 ] -- Is in bytes
		
		if blocktype == 0 then -- Stream info
			t = vstruct.unpack ( "> u2 u2 u3 u3 <m8> u16" , fd )
			sampleinfo.minblocksize = t [ 1 ]
			sampleinfo.maxblocksize = t [ 2 ]
			sampleinfo.minframesize = t [ 3 ]
			sampleinfo.maxframesize = t [ 4 ]
			sampleinfo.samplerate = vstruct.implode { unpack ( t [ 5 ] , 45 , 64 ) }
			sampleinfo.channels = vstruct.implode { unpack ( t [ 5 ] , 42 , 44 ) } + 1
			sampleinfo.bitspersample = vstruct.implode { unpack ( t [ 5 ] , 37 , 41 ) }
			sampleinfo.totalsamples = vstruct.implode { unpack ( t [ 5 ] , 1 , 36 ) }
			sampleinfo.md5rawaudio = t [ 6 ]
			--t [ 1 ] = nil
			--samplerate = t [ 5 ]
			--channels = t [ 6 ] + 1
			--bitspersample = t [ 7 ]
			--totalsamples = t [ 8 ]
			for k,v in pairs ( sampleinfo ) do print ( k,v) end
		elseif blocktype == 1 then -- Padding
			t = vstruct.unpack ( "> x" .. blocklength , fd )
		elseif blocktype == 2 then -- Application
			t = vstruct.unpack ( "> u4 s" .. ( blocklength - 4 ) , fd )
			appID = t [ 1 ]
			appdata = t [ 2 ]
		elseif blocktype == 3 then -- Seektable
			t = vstruct.unpack ( "> x" .. blocklength , fd ) -- We don't deal with seektables, skip over it
		elseif blocktype == 4 then -- Vorbis_Comment http://www.xiph.org/vorbis/doc/v-comment.html
			t = vstruct.unpack ( "< u4" , fd )
			vendor_length = t [ 1 ]
			t = vstruct.unpack ( "<s" .. vendor_length .. "u4" , fd )
			vendor_string = t [ 1 ]
			user_comment_list_length = t [ 2 ]
			
			comment = { }
			for i = 1 , ( user_comment_list_length ) do
				t = vstruct.unpack ( "< u4" , fd )
				local length = t [ 1 ]
				t = vstruct.unpack ( "< s" .. length , fd )
				comment [ i ] = t [ 1 ]
				local fieldname , value = string.match ( comment [ i ] , "([^=]+)=(.+)")
				tags [ fieldname ] = tags [ fieldname ] or { }
				table.insert ( tags [ fieldname ] , value )
			end
			
		elseif blocktype == 5 then -- Cuesheet
			t = vstruct.unpack ( ">s128u8x259x1x" .. ( blocklength - ( 128 + 8 + 259 + 1 ) ) , fd ) -- cbf, TODO: cuesheet reading
		elseif blocktype == 6 then -- Picture
			t = vstruct.unpack ( ">u4u4" , fd )
			picturetype = t [ 1 ]
			mimelength = t [ 2 ]
			t = vstruct.unpack ( ">s" .. mimelength .. "u4" , fd )
			mimetype = t [ 1 ]
			descriptionlength = t [ 2 ]
			t = vstruct.unpack ( ">s" .. descriptionlength .. "u4u4u4u4u4" , fd )
			width = t [ 1 ]
			height = t [ 2 ]
			colourdepth = t [ 3 ]
			numberofcolours = t [ 4 ]
			picturelength = t [ 5 ]
			t = vstruct.unpack ( ">s" .. picturelength , fd )
			picturedata = t [ 1 ]
		end
	until lastmetadatablock == 1
	local item = { }
	item.format = "flac"
	item.length = sampleinfo.totalsamples / sampleinfo.samplerate
	item.tags = tags
	item.extra = sampleinfo
	
	return item
end
fd:close ( )