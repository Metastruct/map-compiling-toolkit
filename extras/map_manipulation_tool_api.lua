--[[
By Mohamed RACHID
Please follow the license "Mozilla Public License 2.0" or greater. https://www.mozilla.org/en-US/MPL/2.0/
To be simple: if you distribute a modified version then you share the sources.

Limitations:
- You cannot do several operations on the same BspContext at once.
--]]
-- https://developer.valvesoftware.com/wiki/Source_BSP_File_Format
-- https://developer.valvesoftware.com/wiki/Source_BSP_File_Format/Game-Specific
-- TODO - objets de contexte contenant :
	-- id Stéam du jeu ou 0 ?
-- TODO - membres par défaut, avec commentaires descriptifs
-- TODO - fichier journal
-- TODO - interdire remplacement (sans effet) & suppression (sans effet) de LUMP_GAME_LUMP


print("map_manipulation_tool_api")


-- Local copies, not changing how the code is written, for greater loop efficiency:
local SysTime = SysTime
local bit = bit
local coroutine = coroutine
local ipairs = ipairs
local math = math
local pairs = pairs
local string = string
local unpack = unpack
local table = table


module("map_manipulation_tool_api", package.seeall)


--- Constants ---
BUFFER_LENGTH = 4194304 -- 4 MiB
FULL_ZERO_BUFFER = nil -- BUFFER_LENGTH of null data, set only on 1st API use
local WEAK_KEYS = {__mode = "k"}
local WEAK_VALUES = {__mode = "v"}
local DICTIONARY_DEFAULT_0 = {__index = function() return 0 end}
local FLOAT_TEXT_NAN
local FLOAT_TEXT_INF_POSI
local FLOAT_TEXT_INF_NEGA

-- lump_t variants:
local LUMP_T_USUAL = nil -- usual
local LUMP_T_L4D2 = 1 -- Left 4 Dead 2 / Contagion


--- Utility ---

do
	-- 32-bit integers are signed, other lengths are unsigned
	
	local bit_bor = bit.bor
	local bit_lshift = bit.lshift
	local string_byte = string.byte
	
	function data_to_le(data)
		-- Decode a binary string into a 4-byte-max little-endian integer
		local result = 0
		local bytes = {string_byte(data, 1, #data)}
		for i = #bytes, 1, -1 do
			result = bit_bor(bit_lshift(result, 8), bytes[i])
		end
		return result
	end
	
	function data_to_be(data)
		-- 32-bit integers are signed, other lengths are unsigned
		local result = 0
		local bytes = {string_byte(data, 1, #data)}
		for i = 1, #bytes, 1 do
			result = bit_bor(bit_lshift(result, 8), bytes[i])
		end
		return result
	end
end


do
	-- Functions to decode single-precision floats:
	
	local _nan = math.log(-1.)
	local _inf_posi = 1./0.
	local _inf_nega = -1./0.
	FLOAT_TEXT_NAN = tostring(_nan)
	FLOAT_TEXT_INF_POSI = tostring(_inf_posi)
	FLOAT_TEXT_INF_NEGA = tostring(_inf_nega)
	local specialValues = {
		-- Includes positive & negative int32 equivalents
		[0x00000000] = 0., -- 0
		[0x80000000] = -0., -- -0
		[-2147483648] = -0., -- -0
		[0x7f800000] = _inf_posi, -- inf
		[0xff800000] = _inf_nega, -- -inf
		[-8388608] = _inf_nega, -- -inf
		[0xffc00001] = _nan, -- qNaN
		[-4194303] = _nan, -- qNaN
		[0xff800001] = _nan, -- sNaN
		[-8388607] = _nan, -- sNaN
	}
	local bit_rshift = bit.rshift
	local bit_band = bit.band
	local bit_bor = bit.bor
	local function _integer_to_float32(integer_)
		-- Decode a single-precision float from its a 32-bit integer representation
		-- It also returns the original integer, which is accuracy-safe.
		local exponent
		local float_ = specialValues[integer_]
		if not float_ then
			exponent = bit_band(bit_rshift(integer_, 23), 0xFF) -- unsigned: exponent as a signed integer is uncommon
			if exponent == 0xFF then
				-- zero & most NaN representations already handled with specialValues
				float_ = _nan
			end
		end
		if not float_ then
			local negative_bit = bit_rshift(integer_, 31)
			local mantissa = bit_band(integer_, 0x7FFFFF)
			if exponent ~= 0 then
				exponent = exponent - 127
				mantissa = bit_bor(0x800000, mantissa) -- implicit '1' bit (before point)
			else -- subnormal
				exponent = -126
				mantissa = mantissa
			end
			-- - 23 to offset the binary point by 23 digits to the left
			float_ = mantissa * (2 ^ (exponent - 23))
			float_ = (negative_bit ~= 1) and float_ or -float_
		end
		return float_
	end
	
	function data_to_float32_le(data)
		-- TODO - tester
		return _integer_to_float32(data_to_le(data))
	end
	
	function data_to_float32_be(data)
		return _integer_to_float32(data_to_be(data))
	end
end

function int32_to_le_data(num)
	local bytes = {
		bit.band(num, 0xFF),
		bit.band(bit.rshift(num, 8), 0xFF),
		bit.band(bit.rshift(num, 16), 0xFF),
		bit.band(bit.rshift(num, 24), 0xFF),
	}
	return string.char(unpack(bytes))
end

function int16_to_le_data(num)
	local bytes = {
		bit.band(num, 0xFF),
		bit.band(bit.rshift(num, 8), 0xFF),
	}
	return string.char(unpack(bytes))
end

function int32_to_be_data(num)
	local bytes = {
		bit.band(bit.rshift(num, 24), 0xFF),
		bit.band(bit.rshift(num, 16), 0xFF),
		bit.band(bit.rshift(num, 8), 0xFF),
		bit.band(num, 0xFF),
	}
	return string.char(unpack(bytes))
end

function int16_to_be_data(num)
	local bytes = {
		bit.band(bit.rshift(num, 8), 0xFF),
		bit.band(num, 0xFF),
	}
	return string.char(unpack(bytes))
end

do
	-- Functions to encode single-precision floats
	-- Note: values are clamped naturally below min/max values and explicitly around +/- 0.
	
	local bit_band = bit.band
	local bit_bor = bit.bor
	local bit_lshift = bit.lshift
	local math_floor = math.floor
	local tostring = tostring
	local string_format = string.format
	local string_match = string.match
	local tonumber = tonumber
	local math_max = math.max
	
	local specialValues = {
		-- To ensure proper conversion, the string representation is used.
		[tostring( 0.)] = 0x00000000, -- 0
		[tostring(-0.)] = 0x80000000, -- -0
		[tostring( 1./0.)] = 0x7f800000, -- inf
		[tostring(-1./0.)] = 0xff800000, -- -inf
		[tostring(math.log(-1.))] = 0xffc00001, -- qNaN
	}
	
	--[[
	local function _debug_binary_float32(integer_)
		-- Only for debugging
		local digits = {"\t\t"}
		for digitId = 31, 0, -1 do
			digits[#digits + 1] = tostring(bit.band(bit.rshift(integer_, digitId), 1))
			if digitId == 31 or digitId == 23 then
				digits[#digits + 1] = " "
			end
		end
		print(table.concat(digits))
	end
	]]
	
	local function _float32_to_int32(float_)
		local integer_ = specialValues[tostring(float_)]
		if not integer_ then
			-- Take away the sign:
			local negative = (float_ < 0.)
			if negative then
				float_ = -float_
			end
			
			local exponent
			local mantissa -- as written (without the explicit '1' bit)
			local subnormal = false
			local roundUp
			
			-- Find the proper exponent & calculate the mantissa:
			for exponent_ = 127, -127, -1 do
				-- -127 is fake and means that it is a subnormal number.
				if exponent_ == -127 then
					exponent_ = -126
					subnormal = true
				end
				mantissa = float_ / (2 ^ (exponent_ - 23)) -- as float, including implicit #23 bit
				roundUp = ((mantissa % 1.) >= 0.5) -- supposedly it is not >=, but it should not matter
				mantissa = math_floor(mantissa) -- as 24-bit integer (more bits if overflow)
				if subnormal or mantissa >= 0x800000 then -- found 1st '1' bit in 24-bit mantissa
					exponent = exponent_
					break
				end
			end
			
			-- Correct the mantissa:
			if mantissa >= 0xffffff then
				if exponent >= 127 then
					-- prevent overflow:
					exponent = 127
					mantissa = 0xffffff
				elseif roundUp or mantissa > 0xffffff then
					-- round-up by incrementing exponent:
					exponent = exponent + 1
					mantissa = 0x800000
				end
			elseif roundUp then
				-- round up if appropriate:
				mantissa = mantissa + 1
			end
			if subnormal and mantissa == 0 then
				-- Clamp tiny non-zero to minimum non-zero value:
				mantissa = 1
			end
			mantissa = bit_band(0x7fffff, mantissa) -- as 23-bit integer, excluding implicit #23 bit
			
			-- Calculate the encoded exponent (applying bias):
			if not subnormal then
				exponent = exponent + 127 -- range: 0x01 to 0xfe
			else
				exponent = 0x00
			end
			
			-- Putting everything together in the final value:
			integer_ = bit_bor(
				negative and 0x80000000 or 0x00000000,
				bit_lshift(exponent, 23),
				mantissa
			)
		end
		return integer_
	end
	
	function float32_to_le_data(float_)
		return int32_to_le_data(_float32_to_int32(float_))
	end
	
	function float32_to_be_data(float_)
		return int32_to_be_data(_float32_to_int32(float_))
	end
	
	--[[
	if CLIENT then
		-- "([0-9a-f]{2})([0-9a-f]{2}) ([0-9a-f]{2})([0-9a-f]{2})"
		-- "\\x$1\\x$2\\x$3\\x$4"
		print("Example values from Wikipedia:")
		for _, convertAttempts in ipairs({
			{"\t1.4012984643e-45 =", "\x00\x00\x00\x01"},
			{"\t1.1754942107e-38 =", "\x00\x7f\xff\xff"},
			{"\t1.1754943508e-38 =", "\x00\x80\x00\x00"},
			{"\t3.4028234664e+38 =", "\x7f\x7f\xff\xff"},
			{"\t0.9999999404     =", "\x3f\x7f\xff\xff"},
			{"\t1                =", "\x3f\x80\x00\x00"},
			{"\t1.0000001192     =", "\x3f\x80\x00\x01"},
			{"\t−2               =", "\xc0\x00\x00\x00"},
			{"\t+0               =", "\x00\x00\x00\x00"},
			{"\t-0               =", "\x80\x00\x00\x00"},
			{"\t+infinity        =", "\x7f\x80\x00\x00"},
			{"\t-infinity        =", "\xff\x80\x00\x00"},
			{"\t3.14159274101    =", "\x40\x49\x0f\xdb"},
			{"\t0.333333343267   =", "\x3e\xaa\xaa\xab"},
			{"\tqNaN             =", "\xff\xc0\x00\x01"},
			{"\tsNaN             =", "\xff\x80\x00\x01"},
		}) do
			local float_ = data_to_float32_be(convertAttempts[2])
			local float2 = data_to_float32_be(float32_to_be_data(float_))
			print(convertAttempts[1], string.format("%9s\t%9s", tostring(float_), tostring(float2)))
		end
		print(data_to_float32_be(float32_to_be_data( 5e+120)))
		print(data_to_float32_be(float32_to_be_data( 5e-120)))
		print(data_to_float32_be(float32_to_be_data(-5e-120)))
		print(data_to_float32_be(float32_to_be_data(-5e+120)))
	end
	]]
	
	function float32_to_decimal_string(float_, decimals)
		-- float_: number to convert
		-- decimals: number of expected decimals by default (for Vector & Angle), or nil for automatic precision, ignored for large numbers
		-- Convert a single-precision number into a string with its decimal representation (like %f), with guaranteed precision.
		-- For precision: 8 significant digits are required (2^24), +1 because maybe needed, +1 for extended precision just-in-case.
		local text
		local base, powerOf10 = string_match(string_format("%.9e", float_), "^([%d%.%-%+ ]+)e([%d%-%+ ]+)$")
		base, powerOf10 = tonumber(base), tonumber(powerOf10)
		if base and powerOf10 then
			if powerOf10 < 9 then
				-- usual case:
				local minimumDecimals = 9 - powerOf10
				decimals = decimals and math_max(decimals, minimumDecimals) or minimumDecimals
			else
				-- at least 10 significant digits before decimal point:
				decimals = 0 -- shorter ouput
			end
			text = string_format("%." .. decimals .. "f", float_)
		else
			-- special number:
			text = tostring(float_)
		end
		return text
	end
end

do
	local isstring = isstring
	local string_sub = string.sub
	local Vector = Vector
	local Angle = Angle
	local table_concat = table.concat
	local string_format = string.format
	
	local function read3Float32s(context, from)
		local data_to_float32 = context.data_to_float32
		if not isstring(from) then
			from = from:Read(12)
		end
		return data_to_float32(string_sub(from, 1, 4)),
		       data_to_float32(string_sub(from, 5, 8)),
		       data_to_float32(string_sub(from, 9, 12))
	end
	
	function decode_Vector(context, from)
		-- TODO - supporter Vector chelous encodés bruts
		return Vector(read3Float32s(context, from))
	end
	
	function decode_QAngle(context, from)
		-- TODO - supporter Angle chelous encodés bruts
		return Angle(read3Float32s(context, from))
	end
	
	function Vector_to_data(context, from)
		-- TODO - supporter Vector chelous encodés bruts
		local pieces = {
			context.float32_to_data(from.x),
			context.float32_to_data(from.y),
			context.float32_to_data(from.z),
		}
		return table_concat(pieces)
	end
	
	function QAngle_to_data(context, from)
		-- TODO - supporter Angle chelous encodés bruts
		local pieces = {
			context.float32_to_data(from.p),
			context.float32_to_data(from.y),
			context.float32_to_data(from.r),
		}
		return table_concat(pieces)
	end
	
	function Vector_to_string(from)
		-- Very big values are truncated with Vector:__tostring()!
		-- There is a loss of precision for small values Vector:__tostring().
		-- Note: Vector() probably handles long strings.
		-- TODO - supporter Vector chelous encodés bruts
		return string_format("%s %s %s",
			float32_to_decimal_string(from.x, 6),
			float32_to_decimal_string(from.y, 6),
			float32_to_decimal_string(from.z, 6)
		)
	end
	
	function Angle_to_string(from)
		-- Very big values are truncated with Angle:__tostring()!
		-- There is a loss of precision for small values Angle:__tostring().
		-- Note: Angle() probably handles long strings.
		-- TODO - supporter Angle chelous encodés bruts
		return string_format("%s %s %s",
			float32_to_decimal_string(from.p, 3),
			float32_to_decimal_string(from.y, 3),
			float32_to_decimal_string(from.r, 3)
		)
	end
end

do
	local isstring = isstring
	local Color = Color
	local string_byte = string.byte
	local string_char = string.char
	
	function decode_color32(from)
		if not isstring(from) then
			from = from:Read(4)
		end
		return Color(string_byte(from, 1, 4))
	end
	
	function ColorFromText(rendercolor, renderamt)
		local r, g, b, a
		if rendercolor then
			do
				r, g, b, a = string.match(rendercolor, "^%s*([1-2]?[0-9]?[0-9])%s+([1-2]?[0-9]?[0-9])%s+([1-2]?[0-9]?[0-9])%s+([1-2]?[0-9]?[0-9])")
			end
			if not r then
				r, g, b = string.match(rendercolor, "^%s*([1-2]?[0-9]?[0-9])%s+([1-2]?[0-9]?[0-9])%s+([1-2]?[0-9]?[0-9])")
			end
		end
		if not r then
			r, g, b = 255, 255, 255
		end
		if renderamt then
			a = renderamt
		end
		if not a then
			a = 255
		end
		return Color(tonumber(r), tonumber(g), tonumber(b), tonumber(a))
	end
	
	function color32_to_data(from)
		return string_char(from.r, from.g, from.b, from.a)
	end
end

local writeZeroesInFile
do
	local math_min = math.min
	local string_rep = string.rep
	function writeZeroesInFile(streamDst, remainingBytes)
		-- Write remainingBytes NULL bytes in streamDst
		
		while remainingBytes > 0 do
			local toWrite_bytes = math_min(BUFFER_LENGTH, remainingBytes)
			local buffer = FULL_ZERO_BUFFER
			if toWrite_bytes ~= BUFFER_LENGTH then
				buffer = string_rep("\0", toWrite_bytes) -- expensive!
			end
			streamDst:Write(buffer)
			remainingBytes = remainingBytes - toWrite_bytes
		end
	end
end

do
	local math_min = math.min
	local math_max = math.max
	local string_sub = string.sub
	local NOT_IMPLEMENTED = "Not implemented"
	
	BytesIO = {
		-- Class to manipulate a string like a File (currently only read-only)
		-- Returned types should be the same for every case.
		-- Borrowed from Python
		
		_wrapped = nil, -- the string to wrap / nil when closed
		_length = -1, -- the length of _wrapped
		_cursor = -1, -- the current location in the string
		_writeable = false, -- always false: read-only
		
		new = function(cls, wrapped, mode)
			-- mode: always "rb"
			
			local instance = {}
			setmetatable(instance, cls)
			
			if mode == "rb" then
				instance._wrapped = wrapped
				instance._length = #wrapped
				instance._cursor = 0
			else
				error("Argument mode: invalid value")
			end
			
			return instance
		end,
		
		Close = function(self)
			self._wrapped = nil -- free memory
			self._length = -1
			self._cursor = -1
		end,
		
		Flush = function(self)
			-- nothing
		end,
		
		Read = function(self, length)
			if self._wrapped then
				if length > 0 then
					local oldCursor = self._cursor
					local newCursor = math_min(oldCursor + length, self._length)
					if newCursor ~= oldCursor then
						self._cursor = newCursor
						return string_sub(self._wrapped, oldCursor + 1, newCursor)
					else
						-- nothing left
						return
					end
				else
					return
				end
			else
				return
			end
		end,
		
		ReadBool = function(self)
			error(NOT_IMPLEMENTED)
		end,
		
		ReadByte = function(self)
			error(NOT_IMPLEMENTED)
		end,
		
		ReadDouble = function(self)
			error(NOT_IMPLEMENTED)
		end,
		
		ReadFloat = function(self)
			error(NOT_IMPLEMENTED)
		end,
		
		ReadLine = function(self)
			error(NOT_IMPLEMENTED)
		end,
		
		ReadLong = function(self)
			error(NOT_IMPLEMENTED)
		end,
		
		ReadShort = function(self)
			error(NOT_IMPLEMENTED)
		end,
		
		ReadULong = function(self)
			error(NOT_IMPLEMENTED)
		end,
		
		ReadUShort = function(self)
			error(NOT_IMPLEMENTED)
		end,
		
		Seek = function(self, pos)
			if self._wrapped then
				self._cursor = math_min(math_max(0, pos), self._length)
			end
		end,
		
		Size = function(self)
			if self._wrapped then
				return self._length
			else
				return
			end
		end,
		
		Skip = function(self, amount)
			if self._wrapped then
				self._cursor = math_min(math_max(0, self._cursor + amount), self._length)
			end
		end,
		
		Tell = function(self)
			if self._wrapped then
				return self._cursor
			else
				return
			end
		end,
	}
	BytesIO.__index = BytesIO
	setmetatable(BytesIO, FindMetaTable("File"))
end

do
	local File = FindMetaTable("File")
	local File_Tell = File.Tell
	local File_Seek = File.Seek
	-- Not using members because instance is a userdata:
	local _sizes = setmetatable({}, WEAK_KEYS)
	local _sizesUntruncated = setmetatable({}, WEAK_KEYS)
	
	FileForWrite = {
		-- Replacement for the File class that keeps trace of the actual current file size
		-- It is useless if the file is open in read mode.
		
		new = function(cls, ...)
			local instance = file.Open(...)
			if instance then
				local rawSize = instance:Size()
				_sizes[instance] = rawSize
				_sizesUntruncated[instance] = rawSize
				debug.setmetatable(instance, cls)
			end
			return instance
		end,
		
		Size = function(self)
			return _sizes[self]
		end,
		
		sizeUntruncated = function(self)
			return _sizesUntruncated[self]
		end,
		
		truncate = function(self)
			-- Erase the rest of the file with NULL-bytes and update the fake size
			-- Already truncated space is not erased again.
			-- This method does not come standard.
			local pos = File_Tell(self)
			local lengthOfZeroes = _sizes[self] - pos
			if lengthOfZeroes >= 0 then
				writeZeroesInFile(self, lengthOfZeroes)
				File_Seek(self, pos)
				_sizes[self] = pos
			else
				print("Attempted to FileForWrite:truncate() with FileForWrite:Size() < File:Tell()!")
			end
		end,
	}
	do
		local function updateSize(stream)
			local pos = File_Tell(stream)
			if pos > _sizes[stream] then
				_sizes[stream] = pos
			end
			if pos > _sizesUntruncated[stream] then
				_sizesUntruncated[stream] = pos
			end
		end
		for methodName, parentMethod in pairs(File) do
			if isstring(methodName) and string.sub(methodName, 1, 5) == "Write" and isfunction(parentMethod) then
				FileForWrite[methodName] = function(self, ...)
					parentMethod(self, ...)
					updateSize(self)
				end
			end
		end
	end
	FileForWrite.__index = FileForWrite
	setmetatable(FileForWrite, File)
end

do
	function lzmaVbspToStandard(lzmaVbsp)
		local id = string.sub(lzmaVbsp, 1, 4)
		if id ~= "LZMA" and id ~= "AMZL" then
			error("Invalid VBSP LZMA data!")
		end
		local actualSize = string.sub(lzmaVbsp, 5, 8) -- 32-bit little-endian
		local lzmaSize = data_to_le(string.sub(lzmaVbsp, 9, 12)) -- 32-bit little-endian
		local lzmaSizeExpected = #lzmaVbsp - 17
		local properties = string.sub(lzmaVbsp, 13, 17)
		if lzmaSize < lzmaSizeExpected then
			print("Warning: lzmaVbspToStandard() - compressed lump with lzmaSize (" .. tostring(lzmaSize) .. " bytes) not filling the whole lump payload (" .. tostring(lzmaSizeExpected) .. " bytes)")
		elseif lzmaSize > lzmaSizeExpected then
			print("Warning: lzmaVbspToStandard() - compressed lump with lzmaSize (" .. tostring(lzmaSize) .. " bytes) exceeding the lump payload capacity (" .. tostring(lzmaSizeExpected) .. " bytes), expect errors!")
		end
		return table.concat({
			properties,
			actualSize, "\0\0\0\0", -- 64-bit little-endian
			string.sub(lzmaVbsp, 18),
		})
	end
	
	function lzmaStandardToVbsp(context, lzmaStandard)
		local id
		if context.data_to_integer == data_to_le then
			id = "LZMA"
		else
			id = "AMZL"
		end
		local actualSize = string.sub(lzmaStandard, 6, 9) -- dropping most significant bits from 64-bit little-endian
		local lzmaSize = int32_to_le_data(#lzmaStandard - 13)
		local properties = string.sub(lzmaStandard, 1, 5)
		return table.concat({
			id,
			actualSize,
			lzmaSize,
			properties,
			string.sub(lzmaStandard, 14),
		})
	end
end

-- The asynchronous mechanism:
local yieldIfTimeout
do
	-- TODO - gérer automatiquement l'ajout d'un hook pour poursuivre le traitement + callback statut + callback fini [avec info succès / échec]
	local SysTime = SysTime
	local coroutine_running = coroutine.running
	local coroutine_yield = coroutine.yield
	yieldIfTimeout = function(step, stepCount, stepProgress)
		-- Function to be invoked by functions to support asynchronous operation
		local work = coroutine_running()
		if work ~= nil and work.yieldAt ~= nil and SysTime() >= work.yieldAt then
			coroutine_yield(step, stepCount, stepProgress)
		end
	end
	
	function asyncWork(onFinishedOk, onError, onProgress, interval_s, func, ...)
		-- Invoke the given function with the given arguments in a coroutine
		-- onFinishedOk : onFinishedOk(vararg result)
		-- onError : onError(string errorMessage)
		-- onProgress : onProgress(int step, int stepCount, float stepProgress)
		-- TODO : asynchrone pour de vrai
		-- TODO : SERVER != CLIENT
		-- TODO : CLIENT : stopper rendu si menu Echap visible
		-- TODO : retourner objet avec : fonction d'annulation
		local callData = {xpcall(func, function(errorMessage)
			ErrorNoHalt(errorMessage .. "\n" .. debug.traceback())
			return errorMessage
		end, ...)}
		local success = callData[1]
		if success then
			if onFinishedOk then
				onFinishedOk(unpack(callData, 2)) -- return result of func call
			end
		else
			if onError then
				onError(unpack(callData, 2)) -- return error message
				ErrorNoHalt(callData[2])
			end
		end
		return {--[[TODO]]}
	end
end

local callSafe
do
	local pcall = pcall
	local unpack = unpack
	function callSafe(...)
		local resultInfo = {pcall(...)}
		if not resultInfo[1] then
			ErrorNoHalt(resultInfo[2])
		end
		return unpack(resultInfo)
	end
end

local stringToLuaString
do
	local string_gsub = string.gsub
	local replacements = {
		['\0'] = '\\0',
		['"'] = '\\"',
		["\\"] = "\\\\",
	}
	for c = 0x01, 0x1F do
		replacements[string.char(c)] = string.format("\\x%02X", c)
	end
	function stringToLuaString(initial)
		return '"' .. string_gsub(initial, '.', replacements) .. '"'
	end
end

local anyToKeyValueString
do
	local string_gsub = string.gsub
	local tostring = tostring
	local isvector = isvector
	local isangle = isangle
	local isnumber = isnumber
	local string_format = string.format
	
	local replacements = {
		["\0"] = "",
		['"'] = '\\"',
	}
	function anyToKeyValueString(initial)
		if isvector(initial) then
			return '"' .. Vector_to_string(initial) .. '"'
		elseif isangle(initial) then
			return '"' .. Angle_to_string(initial) .. '"'
		elseif isnumber(initial) then
			if initial % 1 == 0 and initial >= -2147483648 and initial <= 4294967295 then
				-- int32 value:
				if initial >= 0 then
					return string_format('"%u"', initial)
				else
					return string_format('"%d"', initial)
				end
			else
				-- float value:
				return '"' .. float32_to_decimal_string(initial) .. '"'
			end
		else
			return '"' .. string_gsub(tostring(initial), '.', replacements) .. '"'
		end
	end
end

--[[
local dictionaryKeysToLowerCase
do
	-- Return a copy of dictionary with keys converted to lowercase
	-- Bug "maxdxlevel", "Flags" https://github.com/Facepunch/garrysmod-issues/issues/4400
	local string_lower = string.lower
	function dictionaryKeysToLowerCase(dictionary)
		local dictionary_ = {}
		for k, v in pairs(dictionary_) do
			dictionary_[string_lower(k)] = v
		end
		return dictionary_
	end
end
-- Solution: preserveKeyCase = false
]]

local keyValuesTextKeepNumberPrecision
do
	-- Avoid automatically decoding numbers in the text by adding a space after each quoted number
	-- This is necessary because util.KeyValuesToTable() automatically decodes numbers as either int or float32!
	-- Reading back Lua numbers (float64) losts precision because the conversion rounds down.
	local string_gsub = string.gsub
	function keyValuesTextKeepNumberPrecision(text)
		text = string_gsub(text, '"([0-9]+%.?[0-9]*)"', '"%1 "')
		return text
	end
end

local keyValuesIntoStringValues
do
	-- Set all values as strings in a keyvalues table
	-- This alters the given table.
	-- This is useful because values may be strings as well as numbers.
	local istable = istable
	local next = next
	local pairs = pairs
	local tostring = tostring
	function keyValuesIntoStringValues(keyValues)
		local firstEntryValue = ({next(keyValues)})[2]
		if istable(firstEntryValue) and firstEntryValue.Key ~= nil then
			-- Case: table returned by util.KeyValuesToTablePreserveOrder()
			for i = 1, #keyValues do
				local keyValue = keyValues[i]
				keyValue.Value = tostring(keyValue.Value)
			end
		else
			-- Case: table returned by util.KeyValuesToTable() or any other sort of dictionary
			for Key, Value in pairs(keyValues) do
				keyValues[Key] = tostring(Value)
			end
		end
		return keyValues
	end
end


--- Entities ---

--[[
local noLuaEntityClasses = {
	-- Crash if missing (or suspected):
	["worldspawn"] = true,
	["info_node"] = true, -- suspected
	["info_node_air"] = true, -- suspected
	["info_node_air_hint"] = true, -- suspected
	["info_node_climb"] = true,
	["info_node_hint"] = true,
	-- Not working if missing:
	["env_skypaint"] = true, -- for 2D skybox
	["env_tonemap_controller"] = true, -- for lighting parameters (especially HDR)
	["sky_camera"] = true, -- for 3D skybox
}
]]

-- There are many entity classes that do not support being created in Lua: non-working state or crashes can happen.

--[[
local entityClassesWithoutModelIntoLua = {
	-- Entity classes that do not have a model but can be moved into Lua:
	["ambient_generic"] = true,
	--["game_text"] = true, -- no: branding purpose
	--["infodecal"] = true, -- no: branding purpose
	["light"] = true,
	--["light_spot"] = true, -- unknown
	--["lua_run"] = true, -- no: branding & protection purposes
	--["point_spotlight"] = true, -- unknown
	
	-- Spawn points [garrysmod\gamemodes\base\gamemode\player.lua]:
	["info_player_start"] = true,
	["info_player_deathmatch"] = true,
	["info_player_combine"] = true,
	["info_player_rebel"] = true,
	["info_player_counterterrorist"] = true,
	["info_player_terrorist"] = true,
	["info_player_axis"] = true,
	["info_player_allies"] = true,
	["gmod_player_start"] = true,
	["info_player_teamspawn"] = true,
	["ins_spawnpoint"] = true,
	["aoc_spawnpoint"] = true,
	["dys_spawn_point"] = true,
	["info_player_pirate"] = true,
	["info_player_viking"] = true,
	["info_player_knight"] = true,
	["diprip_start_team_blue"] = true,
	["diprip_start_team_red"] = true,
	["info_player_red"] = true,
	["info_player_blue"] = true,
	["info_player_coop"] = true,
	["info_player_human"] = true,
	["info_player_zombie"] = true,
	["info_player_zombiemaster"] = true,
	["info_survivor_rescue"] = true,
}

local entityClassesWithModelNoLua = {
	-- Entity classes that have a model but should not be moved into Lua:
	["trigger_hurt"] = true, -- no: used for map protection
	["func_occluder"] = true, -- not working
	
	["func_physbox"] = true, -- removed after creation?!
	["func_door"] = true, -- investigation
	["func_rotating"] = true, -- investigation
	
	["trigger_hurt"] = true, -- investigation
	["trigger_multiple"] = true, -- investigation
	["trigger_push"] = true, -- investigation
}
]]

local entityClassesForceLua = {
	-- Entity classes that should be moved into Lua despite having no model or a built-in model:
	-- In addition, class names starting with npc_ / weapon_ / item_ are forced too.
	["ambient_generic"] = true,
	["env_sprite"] = true,
	["func_breakable"] = true,
	["func_breakable_surf"] = true,
	["func_brush"] = true,
	["func_button"] = true,
	["func_door"] = true,
	["func_door_rotating"] = true,
	["func_movelinear"] = true,
	["func_platrot"] = true,
	--["func_rotating"] = true, -- investigation
	["light"] = true,
	["light_dynamic"] = true, -- almost sure
	--["light_spot"] = true, -- TODO - investigation
	--["point_spotlight"] = true, -- TODO - investigation
	
	-- Spawn points [garrysmod\gamemodes\base\gamemode\player.lua]:
	["info_player_start"] = true,
	["info_player_deathmatch"] = true,
	["info_player_combine"] = true,
	["info_player_rebel"] = true,
	["info_player_counterterrorist"] = true,
	["info_player_terrorist"] = true,
	["info_player_axis"] = true,
	["info_player_allies"] = true,
	["gmod_player_start"] = true,
	["info_player_teamspawn"] = true,
	["ins_spawnpoint"] = true,
	["aoc_spawnpoint"] = true,
	["dys_spawn_point"] = true,
	["info_player_pirate"] = true,
	["info_player_viking"] = true,
	["info_player_knight"] = true,
	["diprip_start_team_blue"] = true,
	["diprip_start_team_red"] = true,
	["info_player_red"] = true,
	["info_player_blue"] = true,
	["info_player_coop"] = true,
	["info_player_human"] = true,
	["info_player_zombie"] = true,
	["info_player_zombiemaster"] = true,
	["info_survivor_rescue"] = true,
}

local entityClassesAvoidLua = {
	-- Entity classes that should not be moved into Lua despite having a non-built-in model:
	["env_credits"] = true, -- branding purpose [not tested]
	["env_message"] = true, -- branding purpose [not tested]
	["env_projectedtexture"] = true, -- branding purpose [not tested]
	["game_text"] = true, -- branding purpose [not tested]
	["infodecal"] = true, -- branding purpose [not tested]
	["lua_run"] = true, -- branding & protection purposes
	["point_message"] = true, -- branding purpose [not tested]
}

local entityKeyValuesNotInLua = {
	-- Keys are lowercase.
	["classname"] = true,
	["parentname"] = true,
}

local entityClassesForceRespawn = {
	-- Entity classes that should be respawned because they may depend on missing entities during their initial spawn:
	-- In addition, class names starting with filter_ / func_ / logic_ are forced too.
	["func_areaportalwindow"] = true,
	["point_template"] = true,
}

local entityClassesAvoidRespawn = {
	-- Entity classes that should not be respawned despite having a prefix mentioned above:
	["func_useableladder"] = true,
}

local staticPropsKeyValuesOrder = {
	-- Order in which to list keyvalues & properties for prop_static's
	-- Look at BspContext.extractLumpAsText() and StaticPropLump_t.
	-- Every field from StaticPropLump_t should be listed here!
	-- Keys are case-sensitive.
	"origin",
	"angles",
	"model",
	"FirstLeaf",
	"LeafCount",
	"solid",
	"Flags",
	"skin",
	"fademindist",
	"fademaxdist",
	"lightingorigin~",
	"fadescale",
	"mindxlevel",
	"maxdxlevel",
	"mincpulevel",
	"maxcpulevel",
	"mingpulevel",
	"maxgpulevel",
	"rendercolor",
	"renderamt",
	"disableX360",
	"FlagsEx",
	"modelscale",
}

local staticPropsToDynamicKeyValues = {
	-- Keyvalues that are maintained when transforming a prop_static into a prop_dynamic
	-- Keys are case-sensitive.
	["origin"] = true,
	["angles"] = true,
	["model"] = true,
	["solid"] = true,
	["skin"] = true,
	["fademindist"] = true,
	["fademaxdist"] = true,
	["fadescale"] = true,
	["mindxlevel"] = true,
	["maxdxlevel"] = true,
	["mincpulevel"] = true,
	["maxcpulevel"] = true,
	["mingpulevel"] = true,
	["maxgpulevel"] = true,
	["rendercolor"] = true,
	["renderamt"] = true,
	["disableX360"] = true,
	["modelscale"] = true,
}

local infoOverlaysKeyValuesOrder = {
	-- Order in which to list keyvalues & properties for info_overlays's
	-- Look at BspContext.extractLumpAsText() and doverlay_t.
	-- Every field from doverlay_t should be listed here!
	-- Keys are case-sensitive.
	-- This content is taken from a .vmf file and completed with extra fields (excluding Ofaces items).
	--"id",
	--"classname",
	"Id",
	"BasisNormal",
	"BasisOrigin",
	--"BasisU",
	--"BasisV",
	"EndU",
	"EndV",
	--"fademindist",
	"TexInfo",
	"material",
	--"sides",
	"StartU",
	"StartV",
	"uv0",
	"uv1",
	"uv2",
	"uv3",
	"origin",
	"RenderOrder",
	"FaceCount",
}

local infoOverlaysKeyValuesAsComment = {
	-- Keyvalues / properties for info_overlays's that are just here for information
	["material"] = true,
	["origin"] = true,
}

-- Entity classes that do not belong in the LUMP_ENTITIES to {isGameLump, id}:
local entityClassesToLumpLookup


--- Data structures ---

local lumpLuaIndexToName = {} -- +1 from the original list
local lumpNameToLuaIndex = {} -- +1 from the original list
do
	local function add(cIndex, name)
		lumpLuaIndexToName[cIndex + 1] = name
		lumpNameToLuaIndex[name] = cIndex + 1
	end
	add( 0, "LUMP_ENTITIES")
	add( 1, "LUMP_PLANES")
	add( 2, "LUMP_TEXDATA")
	add( 3, "LUMP_VERTEXES")
	add( 4, "LUMP_VISIBILITY")
	add( 5, "LUMP_NODES")
	add( 6, "LUMP_TEXINFO")
	add( 7, "LUMP_FACES")
	add( 8, "LUMP_LIGHTING")
	add( 9, "LUMP_OCCLUSION")
	add(10, "LUMP_LEAFS")
	add(11, "LUMP_FACEIDS")
	add(12, "LUMP_EDGES")
	add(13, "LUMP_SURFEDGES")
	add(14, "LUMP_MODELS")
	add(15, "LUMP_WORLDLIGHTS")
	add(16, "LUMP_LEAFFACES")
	add(17, "LUMP_LEAFBRUSHES")
	add(18, "LUMP_BRUSHES")
	add(19, "LUMP_BRUSHSIDES")
	add(20, "LUMP_AREAS")
	add(21, "LUMP_AREAPORTALS")
	add(22, "LUMP_UNUSED0") -- + Source 2007
	add(22, "LUMP_PROPCOLLISION") -- + Source 2009
	add(22, "LUMP_PORTALS")
	add(23, "LUMP_UNUSED1") -- + Source 2007
	add(23, "LUMP_PROPHULLS") -- + Source 2009
	add(23, "LUMP_CLUSTERS")
	add(24, "LUMP_UNUSED2") -- + Source 2007
	add(24, "LUMP_PROPHULLVERTS") -- + Source 2009
	add(24, "LUMP_PORTALVERTS")
	add(25, "LUMP_UNUSED3") -- + Source 2007
	add(25, "LUMP_PROPTRIS") -- + Source 2009
	add(25, "LUMP_CLUSTERPORTALS")
	add(26, "LUMP_DISPINFO")
	add(27, "LUMP_ORIGINALFACES")
	add(28, "LUMP_PHYSDISP")
	add(29, "LUMP_PHYSCOLLIDE")
	add(30, "LUMP_VERTNORMALS")
	add(31, "LUMP_VERTNORMALINDICES")
	add(32, "LUMP_DISP_LIGHTMAP_ALPHAS")
	add(33, "LUMP_DISP_VERTS")
	add(34, "LUMP_DISP_LIGHTMAP_SAMPLE_POSITIONS")
	add(35, "LUMP_GAME_LUMP")
	add(36, "LUMP_LEAFWATERDATA")
	add(37, "LUMP_PRIMITIVES")
	add(38, "LUMP_PRIMVERTS")
	add(39, "LUMP_PRIMINDICES")
	add(40, "LUMP_PAKFILE")
	add(41, "LUMP_CLIPPORTALVERTS")
	add(42, "LUMP_CUBEMAPS")
	add(43, "LUMP_TEXDATA_STRING_DATA")
	add(44, "LUMP_TEXDATA_STRING_TABLE")
	add(45, "LUMP_OVERLAYS")
	add(46, "LUMP_LEAFMINDISTTOWATER")
	add(47, "LUMP_FACE_MACRO_TEXTURE_INFO")
	add(48, "LUMP_DISP_TRIS")
	add(49, "LUMP_PROP_BLOB") -- + Source 2009
	add(49, "LUMP_PHYSCOLLIDESURFACE")
	add(50, "LUMP_WATEROVERLAYS")
	add(51, "LUMP_LIGHTMAPPAGES") -- + Source 2006
	add(51, "LUMP_LEAF_AMBIENT_INDEX_HDR")
	add(52, "LUMP_LIGHTMAPPAGEINFOS") -- + Source 2006
	add(52, "LUMP_LEAF_AMBIENT_INDEX")
	add(53, "LUMP_LIGHTING_HDR")
	add(54, "LUMP_WORLDLIGHTS_HDR")
	add(55, "LUMP_LEAF_AMBIENT_LIGHTING_HDR")
	add(56, "LUMP_LEAF_AMBIENT_LIGHTING")
	add(57, "LUMP_XZIPPAKFILE")
	add(58, "LUMP_FACES_HDR")
	add(59, "LUMP_MAP_FLAGS")
	add(60, "LUMP_OVERLAY_FADES")
	add(61, "LUMP_OVERLAY_SYSTEM_LEVELS")
	add(62, "LUMP_PHYSLEVEL")
	add(63, "LUMP_DISP_MULTIBLEND")
end
function getLumpLuaIndexToName(luaIndex)
	return lumpLuaIndexToName[luaIndex]
end
function getLumpNameToLuaIndex(name)
	return lumpNameToLuaIndex[name]
end
function getLumpIdFromLumpName(idText)
	local id
	local isGameLump = (string.sub(idText, 1, 5) ~= "LUMP_")
	if isGameLump then
		id = data_to_be(idText)
	else
		id = lumpNameToLuaIndex[idText]
	end
	return id, isGameLump
end
function getLumpNameFromLumpId(isGameLump, id)
	local idText
	if isGameLump then
		idText = int32_to_be_data(id)
	else
		idText = lumpLuaIndexToName[id] -- id is the Lua table index!
	end
	return idText
end
local lumpsNeverCompressed = {
	[lumpNameToLuaIndex.LUMP_PAKFILE] = true,
	[lumpNameToLuaIndex.LUMP_GAME_LUMP] = true,
	[lumpNameToLuaIndex.LUMP_XZIPPAKFILE] = true,
}

local BaseDataStructure = {
	-- Base class for data structures in a .bsp file
	-- Warning: new() alters the current position in streamSrc.
	-- Note: streamSrc can refer to the source map or an external source!
	
	context = nil,
	streamSrc = nil,
	offset = nil,
	
	new = function(cls, context, streamSrc, offset)
		-- streamSrc: optional
		-- offset: optional (nil for relative access or undefined streamSrc)
		
		local instance = {}
		setmetatable(instance, cls)
		
		if context == nil then
			error("context cannot be nil!")
		end
		instance.context = context
		
		instance.streamSrc = streamSrc
		
		instance.offset = offset
		if offset ~= nil and streamSrc then
			streamSrc:Seek(offset)
		end
		return instance
	end,
	
	newClass = function(base, cls)
		cls = cls or {}
		setmetatable(cls, base)
		return cls
	end,
}
BaseDataStructure.__index = BaseDataStructure

lump_t = false -- defined later
dgamelump_t = false -- defined later

local LumpPayload = BaseDataStructure:newClass({
	-- Wrapper around a lump payload
	-- No content is held in here.
	-- This class & its children are referred to in this file as: (LumpPayload|GameLumpPayload|payloadType)
	-- This class is not used for LUMP_GAME_LUMP!
	
	lumpInfoType = lump_t, -- static; nil for now (filled after lump_t definition)
	
	compressed = nil,
	lumpInfoSrc = nil,
	lumpInfoDst = nil, -- created upon writing to a destination stream
	
	new = function(cls, context, streamSrc, lumpInfo)
		local offset = lumpInfo.fileofs
		local instance = BaseDataStructure:new(context, streamSrc, offset)
		setmetatable(instance, cls)
		
		instance.compressed = false
		local compressMagic = streamSrc:Read(4)
		if (context.data_to_integer == data_to_le and compressMagic == "LZMA")
		or (context.data_to_integer == data_to_be and compressMagic == "AMZL") then
			instance.compressed = true
		end
		instance.lumpInfoSrc = lumpInfo
		return instance
	end,
	
	seekToPayload = function(self)
		-- Seek streamSrc to the payload start
		if self.streamSrc == nil then
			error("This object has no streamSrc!")
		end
		self.streamSrc:Seek(self.offset)
	end,
	
	readAll = function(self, noDecompress)
		-- Return the uncompressed payload of the current lump
		-- noDecompress: return the payload as-is without decompressing
		local payload
		self:seekToPayload()
		if self.compressed and not noDecompress then
			payload = util.Decompress(lzmaVbspToStandard(self.streamSrc:Read(self.lumpInfoSrc.filelen)))
			if payload == nil or #payload == 0 then
				error("Could not decompress this lump")
			end
		else
			payload = self.streamSrc:Read(self.lumpInfoSrc.filelen)
		end
		return payload
	end,
	
	_addOffsetMultiple4 = function(cls, streamDst) -- static method
		-- Add dummy bytes to meet the "4-byte multiple" lump start position specification
		-- Of course this does nothing if streamDst is a headerless file (cursor is 0).
		local dummyBytes = streamDst:Tell() % 4
		if dummyBytes ~= 0 then
			streamDst:Write(string.rep("\0", dummyBytes))
		end
	end,
	
	_writeAutoOffset4AndJumpEnd = function(self, streamDst, payloadRoom, noMoveToEnd, noFillWithZeroes, totalLength)
		-- 1- Seek to the end of the destination file if payloadRoom is insufficient
		-- 2- If moved, erase the previous payload (security & compression improvement)
		-- 3- If moved, skip bytes to set the offset to a multiple of 4
		-- payloadRoom: max length in bytes or nil (only applies for .bsp file outputs)
		-- noMoveToEnd: forbid moving to the end if room is insufficient
		-- noFillWithZeroes: avoid returning fillRoomWithZeroes = true when payload shorter than payloadRoom
		-- totalLength: number of bytes to write
		-- return 1: false if noMoveToEnd constraint failed
		-- return 2: true if filling with zeroes
		local okayConstraint = true
		local fillRoomWithZeroes = false
		-- local isGameLump = (self.lumpInfoType == dgamelump_t)
		if payloadRoom == nil then
			-- unconstrained room (writing in an LUMP_GAME_LUMP at the end of the file or in a separate lump file)
			-- This applies in the following cases:
			-- - Writing a game lump at the end of a .bsp file (lack of space)
			-- - Writing a lump at the end of a .bsp file (lack of space or replacement of last lump payload or newly added)
			-- - Exporting to an external file
			-- This condition can be thought about again if necessary.
			do
				-- This should not apply when replacing last lump payload in .bsp file, but wasting up to 3 bytes does not matter.
				-- This does nothing when exporting to an external file (offset is always 0).
				-- TODO - inspecter lors de l'exportation d'un fichier .lmp
				self:_addOffsetMultiple4(streamDst)
			end
		elseif payloadRoom <= 0 or payloadRoom < totalLength then
			-- lump not present in source map OR lump too big OR no space left (game lump)
			-- Note: 0 is rare but possible when no space left for another game lump.
			if noMoveToEnd then
				okayConstraint = false
				print("\t\tNot enough room to proceed!")
			else
				print("\t\tNot enough room, erasing & moving to the end...")
				if noFillWithZeroes then
					print("\t\tSkipping erasing!") -- no reason to trigger this case
				else
					self:_fillWithZeroes(streamDst, payloadRoom) -- erasing old payload
				end
				streamDst:Seek(streamDst:Size()) -- to EOF
				self:_addOffsetMultiple4(streamDst)
			end
		elseif payloadRoom > 0 then
			-- lump present in source map with maybe some space left in payloadRoom
			if not noFillWithZeroes then
				fillRoomWithZeroes = true
			end
		end
		return okayConstraint, fillRoomWithZeroes
	end,
	
	_fillWithZeroes = function(cls, streamDst, length) -- static method
		local remainingBytes = length
		while remainingBytes > 0 do
			local toWrite_bytes = math.min(BUFFER_LENGTH, remainingBytes)
			local buffer = FULL_ZERO_BUFFER
			if toWrite_bytes ~= BUFFER_LENGTH then
				buffer = string.rep("\0", toWrite_bytes) -- expensive!
			end
			streamDst:Write(buffer)
			remainingBytes = remainingBytes - toWrite_bytes
		end
	end,
	
	copyTo = function(self, streamDst, withCompression, payloadRoom, noMoveToEnd, noFillWithZeroes, standardLzmaHeader)
		-- Copy the current lump from self.streamSrc to streamDst
		-- payloadRoom: room for the payload (filelen in the source map) otherwise moved to end, or nil
		-- noMoveToEnd: for game lumps, which should not be out of the LUMP_GAME_LUMP
		-- noFillWithZeroes: for game lumps & separate files, do not fill with 0's to fill payloadRoom
		-- standardLzmaHeader: write a standard LZMA header instead of a VBSP LZMA header
		-- return: a new lump_t or derived / false if noMoveToEnd constraint failed
		
		local okayConstraint, fillRoomWithZeroes
		if withCompression == nil then
			withCompression = self.compressed
		end
		-- If standardLzmaHeader and withCompression and self.compressed, the process cannot be a stream-to-stream copy, so the call is passed to writeTo().
		if withCompression == self.compressed and not (standardLzmaHeader and self.compressed) then
			-- Just copy:
			local filelen = self.lumpInfoSrc.filelen
			local remainingBytes = filelen
			okayConstraint, fillRoomWithZeroes = self:_writeAutoOffset4AndJumpEnd(streamDst, payloadRoom, noMoveToEnd, noFillWithZeroes, remainingBytes)
			if not okayConstraint then
				return false
			end
			local fileofs = streamDst:Tell()
			self:seekToPayload()
			while remainingBytes > 0 do
				local toRead_bytes = math.min(BUFFER_LENGTH, remainingBytes)
				streamDst:Write(self.streamSrc:Read(toRead_bytes))
				remainingBytes = remainingBytes - toRead_bytes
			end
			if fillRoomWithZeroes then
				self:_fillWithZeroes(streamDst, payloadRoom - filelen)
			end
			self.lumpInfoDst = self.lumpInfoType:new(self.context, nil, self, nil, fileofs, filelen)
		else
			-- Compress or decompress then copy:
			if not self:writeTo(streamDst, withCompression, payloadRoom, noMoveToEnd, noFillWithZeroes, standardLzmaHeader) then
				return false
			end
		end
		return self.lumpInfoDst
	end,
	
	writeTo = function(self, streamDst, withCompression, payloadRoom, noMoveToEnd, noFillWithZeroes, standardLzmaHeader)
		-- Write the given lump payload (which must be for self) into streamDst
		-- payload: uncompressed lump content
		-- payloadRoom: room for the payload (filelen in the source map) otherwise moved to end, or nil
		-- standardLzmaHeader: write a standard LZMA header instead of a VBSP LZMA header
		-- return: a new lump_t or derived / false if noMoveToEnd constraint failed
		
		local payload
		local fileofs = streamDst:Tell()
		local uncompressedBytes
		local cursorBytes = 1
		local remainingBytes
		local finalPayload
		local filelen
		local okayConstraint, fillRoomWithZeroes
		if withCompression then
			local payloadCompressed
			local compressedBytes
			if self.compressed then
				payload = nil
				if standardLzmaHeader then
					payloadCompressed = lzmaVbspToStandard(self:readAll(true))
				else
					payloadCompressed = self:readAll(true)
				end
				uncompressedBytes = data_to_le(string.sub(payloadCompressed, 5, 8)) -- actualSize
			else
				payload = self:readAll()
				if standardLzmaHeader then
					payloadCompressed = util.Compress(payload)
				else
					payloadCompressed = lzmaStandardToVbsp(self.context, util.Compress(payload))
				end
				uncompressedBytes = #payload
			end
			compressedBytes = #payloadCompressed
			filelen = compressedBytes
			okayConstraint, fillRoomWithZeroes = self:_writeAutoOffset4AndJumpEnd(streamDst, payloadRoom, noMoveToEnd, noFillWithZeroes, filelen)
			if not okayConstraint then
				return false
			end
			remainingBytes = compressedBytes
			finalPayload = payloadCompressed
		else
			payload = self:readAll()
			uncompressedBytes = #payload
			filelen = uncompressedBytes
			okayConstraint, fillRoomWithZeroes = self:_writeAutoOffset4AndJumpEnd(streamDst, payloadRoom, noMoveToEnd, noFillWithZeroes, filelen)
			if not okayConstraint then
				return false
			end
			remainingBytes = uncompressedBytes
			finalPayload = payload
		end
		payload = nil
		while remainingBytes > 0 do
			local bytesToWrite = math.min(BUFFER_LENGTH, remainingBytes)
			streamDst:Write(string.sub(finalPayload, cursorBytes, cursorBytes + bytesToWrite - 1))
			remainingBytes = remainingBytes - bytesToWrite
			cursorBytes = cursorBytes + bytesToWrite
		end
		if fillRoomWithZeroes then
			self:_fillWithZeroes(streamDst, payloadRoom - filelen)
		end
		self.lumpInfoDst = self.lumpInfoType:new(self.context, nil, self, nil, fileofs, filelen)
		if withCompression then
			 -- apparently the only location where fourCC needs to be explicitly set
			if self.compressed then
				-- decompressing
				self.lumpInfoDst.fourCC = 0
			else
				-- compressing
				self.lumpInfoDst.fourCC = uncompressedBytes
			end
		end
		return self.lumpInfoDst
	end,
	
	erasePrevious = function(cls, context, streamDst, lumpInfo) -- static method
		-- Erase a lump payload with null-bytes to save space
		-- Note: this method is not used in code where lumpInfo is unavailable
		-- Warning: you must check that the payload is not used elsewhere!
		-- TODO - mark this space as available for added lumps + where lumpInfo is unavailable
		
		local remainingBytes = lumpInfo.filelen
		if remainingBytes > 0 and lumpInfo.fileofs > 0 then
			streamDst:Seek(lumpInfo.fileofs)
			writeZeroesInFile(streamDst, remainingBytes)
		end
	end,
})
LumpPayload.__index = LumpPayload

local GameLumpPayload = LumpPayload:newClass({
	-- Wrapper around a game lump payload
	-- No content is held in here.
	-- Unsupported: console version of Portal 2 (fileofs is not absolute)
	
	lumpInfoType = dgamelump_t, -- static; nil for now (filled after dgamelump_t definition)
	
	new = function(cls, context, streamSrc, lumpInfo)
		-- This constructor must have the same arguments as LumpPayload:new() because it is called in LumpPayload & lump_t with class resolution.
		local instance = LumpPayload:new(context, streamSrc, lumpInfo)
		setmetatable(instance, cls)
		return instance
	end,
})
GameLumpPayload.__index = GameLumpPayload

lump_t = BaseDataStructure:newClass({
	-- Note: the default attributes must be those of a null lump_t.
	-- This class & its children are referred to in this file as: (lump_t|dgamelump_t|lumpInfoType)
	
	payloadType = LumpPayload, -- static
	
	fileofs = 0,
	filelen = 0,
	version = 0, -- valid value
	fourCC = 0, -- valid value
	payload = nil,
	
	new = function(cls, context, streamSrc, payload, other, fileofs, filelen, _noReadInherit)
		-- Usage 1: lump_t:new(context, streamSrc)
		--  Load a lump_t from the current position in streamSrc
		-- Usage 2: lump_t:new(context, nil, payload, nil, fileofs=0, filelen=payload.lumpInfoSrc.filelen)
		--  Make a lump_t for a written LumpPayload (in a destination stream), implying another lump_t
		-- Usage 3: lump_t:new(context, nil, false)
		--  Make a lump_t for a written null LumpPayload (in a destination stream)
		-- Usage 4: lump_t:new(context, nil, nil, other, fileofs=0)
		--  Make a lump_t from another lump_t, for writing into a destination stream
		--  This is not needed to "copy" a lump located in the map file (its payload will be protected).
		-- The file cursor must be at the end of the lump_t when returning.
		local instance = BaseDataStructure:new(context, streamSrc, nil)
		setmetatable(instance, cls)
		
		if streamSrc ~= nil then
			if not _noReadInherit then
				if context.specific_lump_t == LUMP_T_L4D2 then
					instance.version = context.data_to_integer(streamSrc:Read(4))
					instance.fileofs = context.data_to_integer(streamSrc:Read(4))
					instance.filelen = context.data_to_integer(streamSrc:Read(4))
					instance.fourCC = context.data_to_integer(streamSrc:Read(4))
				else
					instance.fileofs = context.data_to_integer(streamSrc:Read(4))
					instance.filelen = context.data_to_integer(streamSrc:Read(4))
					instance.version = context.data_to_integer(streamSrc:Read(4))
					instance.fourCC = context.data_to_integer(streamSrc:Read(4))
				end
				local lumpIsUsed = (
					instance.fileofs ~= 0 and
					instance.filelen ~= 0
				)
				if lumpIsUsed then
					local streamPos = streamSrc:Tell()
					instance.payload = LumpPayload:new(context, streamSrc, instance)
					streamSrc:Seek(streamPos)
				end
			end
		elseif payload ~= nil then
			if payload ~= false then -- condition allowing null-lumps creation
				if fileofs == nil then
					fileofs = 0 -- unknown (& easily debugged)
				end
				if filelen == nil then
					filelen = payload.lumpInfoSrc.filelen
				end
				
				instance.fileofs = fileofs
				instance.filelen = filelen
				instance.version = payload.lumpInfoSrc.version
				instance.fourCC = payload.lumpInfoSrc.fourCC
				instance.payload = payload
			end
		elseif other ~= nil then
			instance.fileofs = fileofs or 0
			instance.filelen = other.filelen
			instance.version = other.version
			instance.fourCC = other.fourCC
			instance.payload = other.payload
		else
			error("Missing arguments")
		end
		
		return instance
	end,
	
	newFromPayloadStream = function(cls, context, streamSrc, fileofs, filelen, lumpInfoSrc) -- static method
		-- Usage: lump_t:newFromPayloadStream(context, streamSrc, fileofs, filelen, lumpInfoSrc=nil)
		--  Make a lump_t from its characteristics only
		--  This is especially useful when there is no lump_t in the file that contains it.
		local instance = BaseDataStructure:new(context, streamSrc, nil)
		setmetatable(instance, cls)
		
		instance.fileofs = fileofs
		instance.filelen = filelen
		if lumpInfoSrc then
			instance.version = lumpInfoSrc.version
			instance.fourCC = lumpInfoSrc.fourCC
		end
		local payloadType = cls.payloadType
		if lumpInfoSrc then
			-- Polymorphism support:
			payloadType = lumpInfoSrc.payloadType
		end
		instance.payload = payloadType:new(context, streamSrc, instance)
		
		return instance
	end,
	
	skipThem = function(cls, context, streamDst, numberOfItems) -- static method
		-- Skip numberOfItems lump_t items in streamDst
		streamDst:Skip(16 * numberOfItems)
	end,
	
	writeTo = function(self, streamDst)
		if self.context.specific_lump_t == LUMP_T_L4D2 then
			streamDst:Write(self.context.int32_to_data(self.version))
			streamDst:Write(self.context.int32_to_data(self.fileofs))
			streamDst:Write(self.context.int32_to_data(self.filelen))
			streamDst:Write(self.context.int32_to_data(self.fourCC))
		else
			streamDst:Write(self.context.int32_to_data(self.fileofs))
			streamDst:Write(self.context.int32_to_data(self.filelen))
			streamDst:Write(self.context.int32_to_data(self.version))
			streamDst:Write(self.context.int32_to_data(self.fourCC))
		end
	end,
})
lump_t.__index = lump_t

dgamelump_t = lump_t:newClass({
	-- Note: the default attributes must be those of a null dgamelump_t.
	
	payloadType = GameLumpPayload, -- static
	
	id = 0,
	flags = 0,
	
	new = function(cls, context, streamSrc, payload, other, fileofs, filelen)
		-- Usage 1: dgamelump_t:new(context, streamSrc)
		--  Load a dgamelump_t from the current position in streamSrc
		-- Usage 2: dgamelump_t:new(context, nil, payload, nil, fileofs=0, filelen=payload.lumpInfoSrc.filelen)
		--  Make a dgamelump_t for a written GameLumpPayload (in destination stream), implying another dgamelump_t
		-- Usage 3: dgamelump_t:new(context, nil, false)
		--  Make a dgamelump_t for a written null GameLumpPayload (in a destination stream)
		-- Usage 4: dgamelump_t:new(context, nil, nil, other, fileofs=0)
		--  Make a dgamelump_t from another dgamelump_t, for writing into a destination stream
		-- The file cursor must be at the end of the dgamelump_t when returning.
		local instance = lump_t:new(context, streamSrc, payload, other, fileofs, filelen, true)
		setmetatable(instance, cls)
		
		if streamSrc ~= nil then
			instance.id = context.data_to_integer(streamSrc:Read(4))
			instance.flags = context.data_to_integer(streamSrc:Read(2))
			instance.version = context.data_to_integer(streamSrc:Read(2))
			instance.fileofs = context.data_to_integer(streamSrc:Read(4))
			instance.filelen = context.data_to_integer(streamSrc:Read(4))
			local lumpIsUsed = (
				instance.fileofs ~= 0 and
				instance.filelen ~= 0
			)
			if lumpIsUsed then
				local streamPos = streamSrc:Tell()
				instance.payload = GameLumpPayload:new(context, streamSrc, instance)
				streamSrc:Seek(streamPos)
			end
		elseif payload ~= nil then
			if payload ~= false then -- to allow null-lumps creation
				instance.id = payload.lumpInfoSrc.id
				instance.flags = payload.lumpInfoSrc.flags
			end
		elseif other ~= nil then
			instance.id = other.id
			instance.flags = other.flags
		end
		
		return instance
	end,
	
	newFromPayloadStream = function(cls, context, streamSrc, fileofs, filelen, lumpInfoSrc, id)
		-- Usage: dgamelump_t:newFromPayloadStream(context, streamSrc, fileofs, filelen, lumpInfoSrc=nil, id=nil)
		--  Make a dgamelump_t from its characteristics only
		--  This is especially useful when there is no dgamelump_t in the file that contains it.
		local instance = lump_t:newFromPayloadStream(context, streamSrc, fileofs, filelen, lumpInfoSrc)
		setmetatable(instance, cls)
		
		if lumpInfoSrc then
			instance.id = lumpInfoSrc.id
			instance.flags = lumpInfoSrc.flags
		else
			-- Recreate the payload because of polymorphism failure:
			instance.payload = cls.payloadType:new(context, streamSrc, instance)
		end
		if id ~= nil then
			instance.id = id
		end
		
		return instance
	end,
	
	skipThem = function(cls, context, streamDst, numberOfItems) -- static method
		-- Skip numberOfItems dgamelump_t items in streamDst (for later write)
		-- TODO - ajuster pour jeux avec dgamelump_t différent
		streamDst:Skip(16 * numberOfItems)
	end,
	
	writeTo = function(self, streamDst)
		-- TODO - ajuster pour jeux avec dgamelump_t différent
		streamDst:Write(self.context.int32_to_data(self.id))
		streamDst:Write(self.context.int16_to_data(self.flags))
		streamDst:Write(self.context.int16_to_data(self.version))
		streamDst:Write(self.context.int32_to_data(self.fileofs))
		streamDst:Write(self.context.int32_to_data(self.filelen))
	end,
})
dgamelump_t.__index = dgamelump_t

LumpPayload.lumpInfoType = lump_t
GameLumpPayload.lumpInfoType = dgamelump_t

local HEADER_LUMPS = 64

local dheader_t = BaseDataStructure:newClass({
	-- Structure that represents the header of a .bsp file
	
	context = nil,
	ident = nil,
	version = nil,
	lumps = nil,
	mapRevision = nil,
	
	new = function(cls, context, streamSrc, other, lumps)
		-- Usage 1: dheader_t:new(context, streamSrc)
		--  Load a dheader_t from the position 0 in streamSrc
		-- Usage 2: dheader_t:new(context, nil, other, lumps)
		--  Make a dheader_t from another dheader_t with the optional specified array of lump_t, for writing into a destination stream
		local instance = BaseDataStructure:new(context, streamSrc, 0)
		setmetatable(instance, cls)
		
		if streamSrc ~= nil then
			local ident = streamSrc:Read(4)
			if ident == "VBSP" or ident == "rBSP" then
				context.data_to_integer = data_to_le
				context.data_to_float32 = data_to_float32_le
				context.int32_to_data = int32_to_le_data
				context.int16_to_data = int16_to_le_data
				context.float32_to_data = float32_to_le_data
			elseif ident == "PSBV" or ident == "PSBr" then
				context.data_to_integer = data_to_be
				context.data_to_float32 = data_to_float32_be
				context.int32_to_data = int32_to_be_data
				context.int16_to_data = int16_to_be_data
				context.float32_to_data = float32_to_be_data
			else
				context.data_to_integer = nil
				context.data_to_float32 = nil
				context.int32_to_data = nil
				context.int16_to_data = nil
				context.float32_to_data = nil
				error([[The "VBSP" magic header was not found. This map does not seem to be a valid Source Engine map.]])
			end
			
			instance.ident = ident
			instance.version = context.data_to_integer(streamSrc:Read(4))
			local lumps = {}
			do
				-- Parsing lump_t's as usual ones:
				context.specific_lump_t = LUMP_T_USUAL
				local startOfLumpsArray = streamSrc:Tell()
				for i = 1, HEADER_LUMPS do
					lumps[i] = lump_t:new(context, streamSrc)
				end
				-- Detecting if lump_t's seem to be L4D2's ones:
				local probabilityL4D2 = 0
				for i = 1, #lumps do
					local lumpInfo = lumps[i]
					if lumpInfo.filelen == 0 then
						-- nothing
					elseif lumpInfo.fileofs > lumpInfo.filelen then
						probabilityL4D2 = probabilityL4D2 - 1
					else
						probabilityL4D2 = probabilityL4D2 + 1
					end
				end
				-- Parsing lump_t's as L4D2 ones if needed:
				if probabilityL4D2 > 0 then
					print("This map seems to use Left 4 Dead 2's lump_t.")
					context.specific_lump_t = LUMP_T_L4D2
					streamSrc:Seek(startOfLumpsArray)
					for i = 1, HEADER_LUMPS do
						lumps[i] = lump_t:new(context, streamSrc)
					end
				end
			end
			instance.lumps = lumps
			instance.mapRevision = context.data_to_integer(streamSrc:Read(4))
		elseif other ~= nil and lumps then
			if lumps == nil then
				lumps = other.lumps
			end
			instance.ident = other.ident
			instance.version = other.version
			instance.lumps = lumps
			instance.mapRevision = other.mapRevision
		else
			error("Missing arguments")
		end
		
		return instance
	end,
	
	writeTo = function(self, streamDst)
		-- Write then given BSP header into position 0 in streamDst
		-- This is supposed to happen after writing every lump payload, so lump_t's are ready.
		streamDst:Seek(0)
		streamDst:Write(self.ident)
		streamDst:Write(self.context.int32_to_data(self.version))
		for i = 1, HEADER_LUMPS do
			self.lumps[i]:writeTo(streamDst)
		end
		streamDst:Write(self.context.int32_to_data(self.mapRevision))
	end,
})
dheader_t.__index = dheader_t

local function lumpIndexesOrderedDescFromOffset(lumps)
	-- Make a table of lump indexes ordered (descending) by their fileofs
	-- Missing lumps are ordered (ascending) by their id, after present lumps.
	-- It is intended to keep the order of lump payloads from the source.
	-- It puts the last lump first in order to give it unlimited storage space when possible.
	-- It does not alter lumps array.
	-- lumps: BspContext.lumpsSrc or BspContext.gameLumpsSrc
	local indexes = {}
	for i = 1, #lumps do
		table.insert(indexes, i)
	end
	table.sort(indexes, function(indexA, indexB)
		local fileofsA = lumps[indexA].fileofs
		local fileofsB = lumps[indexB].fileofs
		local filelenA = lumps[indexA].filelen
		local filelenB = lumps[indexB].filelen
		if fileofsA > 0 and filelenA > 0 then
			if fileofsB > 0 and filelenB > 0 then
				-- highest offset comes first
				return fileofsA > fileofsB
			else
				-- missing lump at indexB comes after if replaced
				return true
			end
		else
			if fileofsB > 0 and filelenB > 0 then
				-- missing lump at indexA comes after if replaced
				return false
			else
				-- put missing lump payloads in the order of the lumps array
				return indexA < indexB
			end
		end
	end)
	return indexes
end

local OVERLAY_BSP_FACE_COUNT = 64

BspContext = {
	-- Context that holds a source .bsp file and its information, as well as a destination .bsp file.
	-- TODO - éliminer lumpIndexesToCompress si inutile, remplacer par un booléen commun
	
	_instances = BspContext and BspContext._instances or setmetatable({}, WEAK_KEYS),
	filenameSrc = nil, -- source file path
	streamSrc = nil, -- source file stream
	bspHeader = nil, -- dheader_t object
	lumpsSrc = nil, -- list of lump_t objects from the source map file
	gameLumpsSrc = nil, -- list of dgamelump_t objects from the source map file
	lumpsDst = nil, -- list of lump_t objects selected for the destination map file
	gameLumpsDst = nil, -- list of dgamelump_t objects selected for the destination map file
	lumpIndexesToCompress = nil, -- nil / false / true; setting for LUMP_GAME_LUMP is common for all game lumps
	entitiesTextLua = nil, -- exported entities to Lua script
	
	specific_lump_t = LUMP_T_USUAL,
	
	-- to be set upon .bsp load
	data_to_integer = nil, -- instance's function
	int32_to_data = nil, -- instance's function
	int16_to_data = nil, -- instance's function
	
	new = function(cls, filenameSrc)
		local instance = {}
		setmetatable(instance, cls)
		
		if FULL_ZERO_BUFFER == nil then
			FULL_ZERO_BUFFER = string.rep("\0", BUFFER_LENGTH)
		end
		
		instance.filenameSrc = filenameSrc
		instance.streamSrc = file.Open(filenameSrc, "rb", "GAME")
		if instance.streamSrc == nil then
			error('Unable to open "' .. filenameSrc .. '"')
		end
		
		instance.bspHeader = dheader_t:new(instance, instance.streamSrc)
		
		instance.lumpsSrc = instance.bspHeader.lumps
		
		instance.gameLumpsSrc = {}
		local gameLumpPayload = instance.lumpsSrc[lumpNameToLuaIndex["LUMP_GAME_LUMP"]].payload
		if gameLumpPayload ~= nil then
			-- No worry about compression because the whole game lump fortunately cannot be compressed.
			gameLumpPayload:seekToPayload()
			for i = 1, instance.data_to_integer(instance.streamSrc:Read(4)) do
				table.insert(instance.gameLumpsSrc, dgamelump_t:new(instance, instance.streamSrc))
			end
		end
		
		instance:resetOutputListing()
		
		instance.lumpIndexesToCompress = {}
		
		cls._instances[instance] = true
		return instance
	end,
	
	addExternalLump = nil, -- TODO
	
	resetOutputListing = function(self)
		-- Set every lump / game lump as the one in self.streamSrc
		-- Every lump must be replaced with a lump in the destination stream.
		
		self:_closeAllLumpStreams()
		
		self.lumpsDst = {}
		for i = 1, #self.lumpsSrc do
			-- table.insert(self.lumpsDst, lump_t:new(self, nil, nil, self.lumpsSrc[i]))
			table.insert(self.lumpsDst, self.lumpsSrc[i])
		end
		
		self.gameLumpsDst = {}
		for i = 1, #self.gameLumpsSrc do
			-- table.insert(self.gameLumpsDst, dgamelump_t:new(self, nil, nil, self.gameLumpsSrc[i]))
			table.insert(self.gameLumpsDst, self.gameLumpsSrc[i])
		end
	end,
	
	anyCompressedInGameLumps = function(cls, gameLumps) -- static method
		-- gameLumps: gameLumpsSrc or gameLumpsDst
		local hasCompressedLumps = false
		for i = 1, #gameLumps do
			local payload = gameLumps[i].payload
			if payload and payload.compressed then
				hasCompressedLumps = true
				break
			end
		end
		return hasCompressedLumps
	end,
	
	writeNewBsp_ = function(self, streamDst)
		-- Internal
		
		-- Do local copies of lump arrays to allow future calls to writeNewBsp():
		local lumpsDst = {}
		for i = 1, #self.lumpsDst do
			lumpsDst[i] = self.lumpsDst[i]
		end
		local gameLumpsDst = {}
		for i = 1, #self.gameLumpsDst do
			gameLumpsDst[i] = self.gameLumpsDst[i]
		end
		
		-- Constants:
		local LUMP_GAME_LUMP = lumpNameToLuaIndex.LUMP_GAME_LUMP
		local LUMP_PAKFILE = lumpNameToLuaIndex.LUMP_PAKFILE
		local LUMP_XZIPPAKFILE = lumpNameToLuaIndex.LUMP_XZIPPAKFILE
		
		-- Determine if LUMP_GAME_LUMP modified:
		local lumpGameLumpModified = false
		for i = 1, math.max(#gameLumpsDst, #self.gameLumpsSrc) do
			if gameLumpsDst[i] ~= self.gameLumpsSrc[i] then
				lumpGameLumpModified = true
				break
			end
		end
		
		-- Copy the whole source file map into the destination map
		self.streamSrc:Seek(0)
		do
			local remainingBytes = self.streamSrc:Size() -- okay but may waste space due to last editing
			do
				local remainingBytes_ = remainingBytes
				--[[
				-- Truncate the destination map to the latest present lump (to save space from last time):
				local allLumpsSrc = {}
				for i = 1, #self.lumpsSrc do
					allLumpsSrc[i] = self.lumpsSrc[i]
				end
				for i = 1, #self.gameLumpsSrc do
					allLumpsSrc[#allLumpsSrc + 1] = self.gameLumpsSrc[i]
				end
				local lastLumpInfo = allLumpsSrc[lumpIndexesOrderedDescFromOffset(allLumpsSrc)[1] ]
				remainingBytes_ = lastLumpInfo.fileofs + lastLumpInfo.filelen
				]]
				-- Better: truncate the destination map to the latest non-removed / modified lump:
				-- Note: this could even be the latest non-modified lump, but it would induce extra changes.
				local lumpsSrc = self.lumpsSrc
				for _, i in ipairs(lumpIndexesOrderedDescFromOffset(lumpsSrc)) do
					-- Reminder: null lumps in self.lumpsSrc are listed at the end of the loop, always past a break statement.
					-- -> payloadSrc cannot be nil except for the LUMP_GAME_LUMP
					local lumpInfoSrc = lumpsSrc[i]
					local payloadSrc = lumpInfoSrc.payload
					local payloadDst = lumpsDst[i].payload
					if i == LUMP_GAME_LUMP then
						-- In this tool the LUMP_GAME_LUMP cannot be removed, even when there are 0 game lumps.
						-- Even if the LUMP_GAME_LUMP is missing, it would be listed after the loop exit.
						-- Reminder: there is no payload field for the LUMP_GAME_LUMP.
						if lumpGameLumpModified then
							-- Modified LUMP_GAME_LUMP, truncate (final) to allow it to be actually shorter:
							remainingBytes_ = lumpInfoSrc.fileofs
						else
							-- The file is now truncated enough.
						end
						break -- TODO - why exactly?
					elseif self:_payloadUsedWriteProtected(payloadSrc) then
						-- The file is now truncated enough.
						break
					elseif payloadDst == nil then
						-- Removed lump, truncate more:
						remainingBytes_ = lumpInfoSrc.fileofs
					elseif payloadDst ~= payloadSrc then
						-- Modified lump, truncate (final) to allow it to be actually shorter:
						remainingBytes_ = lumpInfoSrc.fileofs
						break
					else
						-- The file is now truncated enough.
						break
					end
				end
				if remainingBytes_ <= remainingBytes then
					if remainingBytes_ < remainingBytes then
						print("Saved " .. (remainingBytes - remainingBytes_) .. " bytes maximum by truncating the initial map copy!")
					end
					remainingBytes = remainingBytes_
				else
					print("The map is corrupted: reached end-of-file before end of last lump!")
				end
				-- Note: it can be good to save again the .bsp to really truncate it after modifications.
				-- You can use the old commented out remainingBytes value if you feel like a corruption happened.
			end
			while remainingBytes > 0 do
				local toRead_bytes = math.min(BUFFER_LENGTH, remainingBytes)
				streamDst:Write(self.streamSrc:Read(toRead_bytes))
				remainingBytes = remainingBytes - toRead_bytes
			end
		end
		
		-- At this point, lumpsDst & gameLumpsDst contain lumps from self.streamSrc or external sources, with a possibly wrong fileofs.
		for _, i in ipairs(lumpIndexesOrderedDescFromOffset(self.lumpsSrc)) do
			-- Works fine because same number of elements in lumpsSrc & lumpsDst
			print("\tProcessing " .. lumpLuaIndexToName[i])
			
			local bypassIdentical = true -- ignores self.lumpIndexesToCompress[i] on purpose
			if i == LUMP_GAME_LUMP then
				if lumpGameLumpModified then
					bypassIdentical = false
				end
			else
				if lumpsDst[i] ~= self.lumpsSrc[i] then
					bypassIdentical = false
				end
			end
			
			if not bypassIdentical then
				print("\t\tModified!")
				
				local isFinalLump = false -- end-of-file unlimited storage?
				local lumpInfoSrc = self.lumpsSrc[i]
				local payloadSrc = lumpInfoSrc.payload
				local payloadSrcWriteProtected = self:_payloadUsedWriteProtected(payloadSrc)
				if lumpInfoSrc.fileofs ~= 0 and lumpInfoSrc.filelen ~= 0 -- lump exists
				and (lumpInfoSrc.fileofs + lumpInfoSrc.filelen >= streamDst:Size() -- enough space
				or payloadSrcWriteProtected) then -- original payload is write-protected
					-- The payload will be written at the end of the file.
					-- Warning: if the lump is planned to be erased then the handling must not truncate the file.
					isFinalLump = true
				end
				
				local withCompression = self.lumpIndexesToCompress[i] -- true / false / nil
				if i == LUMP_GAME_LUMP then
					-- There is no LumpPayload object involved to write the LUMP_GAME_LUMP itself.
					-- Note: the trailing null game lump must naturally always be at the end.
					--  But there is no need to ensure it: game lumps may be removed or replaced, but never added.
					-- Note: if all game lumps are removed, there simply will be 0 game lumps in the LUMP_GAME_LUMP.
					
					-- Handle the need of a null game lump if compressed game lumps:
					if #gameLumpsDst ~= 0 then
						-- withCompression is common because I decided it is common to all game lumps.
						if withCompression == nil then
							-- I have decided that if one game lump is compressed then they will all be.
							withCompression = self:anyCompressedInGameLumps(gameLumpsDst)
						end
						local lastGLump = gameLumpsDst[#gameLumpsDst]
						if withCompression then
							-- Add a trailing null gamelump if not present:
							if lastGLump.filelen ~= 0 then
								table.insert(gameLumpsDst, dgamelump_t:new(self, nil, false))
							end
						else
							-- Remove the trailing null gamelump if present:
							if lastGLump.filelen == 0 then
								gameLumpsDst[#gameLumpsDst] = nil
							end
						end
					end
					
					local fitsInRoom
					local lump
					local startOfLumpsArray
					for fitsInRoom_ = 1, 0, -1 do
						fitsInRoom = tobool(fitsInRoom_)
						local jumpNoFit = false -- jump to next iteration
						if fitsInRoom then
							-- try to stick to the initial payload room (or unlimited if last lump payload)
							streamDst:Seek(self.lumpsSrc[i].fileofs)
						else
							-- move to the end
							streamDst:Seek(streamDst:Size())
							GameLumpPayload:_addOffsetMultiple4(streamDst)
						end
						
						-- Write the number of game lumps:
						lump = lump_t:new(self, nil, nil, self.lumpsSrc[i], streamDst:Tell())
						lumpsDst[i] = lump
						streamDst:Write(self.int32_to_data(#gameLumpsDst))
						
						-- Skip the array of dgamelump_t's because not ready yet:
						startOfLumpsArray = streamDst:Tell()
						dgamelump_t:skipThem(self, streamDst, #gameLumpsDst)
						
						-- Write the game lump payloads:
						local lastGamelumpMaxOffset
						if fitsInRoom and not isFinalLump then
							lastGamelumpMaxOffset = self.lumpsSrc[i].fileofs + self.lumpsSrc[i].filelen
						end
						for j = 1, #gameLumpsDst do
							collectgarbage()
							print("\t\tProcessing game lump " .. int32_to_be_data(gameLumpsDst[j].id))
							local payload = gameLumpsDst[j].payload
							if payload ~= nil then
								if fitsInRoom and not isFinalLump then
									local payloadRoom = lastGamelumpMaxOffset - streamDst:Tell()
									if not payload:copyTo(streamDst, withCompression, payloadRoom, true, true) then
										jumpNoFit = true
										-- Warning: compressing or decompressing game lumps will be done again.
										print("\t\tNot enough room in the original LUMP_GAME_LUMP, retrying at the end!")
										break
									end
								else
									payload:copyTo(streamDst, withCompression, nil)
								end
								if not jumpNoFit then
									gameLumpsDst[j] = payload.lumpInfoDst
								end
							else
								-- null game lump
								print("\t\tThe game lump #" .. j .. " has no payload!")
								gameLumpsDst[j] = dgamelump_t:new(self, nil, false)
							end
						end
						if not jumpNoFit then
							break -- okay good!
						else
							-- Erase the old LUMP_GAME_LUMP:
							LumpPayload:erasePrevious(self, streamDst, self.lumpsSrc[i])
						end
					end
					
					local endOfLump = streamDst:Tell()
					lump.filelen = endOfLump - lump.fileofs
					if fitsInRoom and not isFinalLump then
						LumpPayload:_fillWithZeroes(streamDst, self.lumpsSrc[i].filelen - lump.filelen)
					end
					
					-- Write the array of dgamelump_t's:
					streamDst:Seek(startOfLumpsArray)
					for j = 1, #gameLumpsDst do
						gameLumpsDst[j]:writeTo(streamDst)
					end
					
					-- Seek to the end of the whole LUMP_GAME_LUMP:
					streamDst:Seek(endOfLump)
				else
					collectgarbage()
					local payload = lumpsDst[i].payload
					local payloadRoom = lumpInfoSrc.filelen
					if isFinalLump then
						-- Any lump payload located at the current end has unlimited storage!
						-- Warning: this applies too if lump removed but payload preserved for another lump id (proper handling required).
						payloadRoom = nil
					end
					local shouldErasePrevious = false
					if payload ~= nil then
						-- The lump to copy from has a payload.
						if self:_payloadUsedWriteProtected(payload) then
							-- This means that the payload already is in the map file (referenced for another lump id).
							-- No copy is required so far.
							print("\t\tThe payload is already in the map file, no copy required!")
							shouldErasePrevious = true
						else
							streamDst:Seek(lumpInfoSrc.fileofs) -- 0 if initially absent: written ok at the end
							lumpsDst[i] = payload:copyTo(streamDst, withCompression, payloadRoom)
							if payloadRoom == nil then -- unlimited end-of-file storage
								-- Redefine the end of the file.
								print("\t\tTruncating after final lump payload...")
								streamDst:truncate()
							end
						end
					else
						-- The lump to copy is a null payload.
						if payloadSrc ~= nil then
							if payloadRoom == nil and not payloadSrcWriteProtected then
								-- Unlimited end-of-file storage
								-- Redefining the end of the file to remove the payload:
								if streamDst:Size() > lumpInfoSrc.fileofs then
									-- This should not happen with a properly truncated initial copy.
									print("\t\tTruncating before removed final lump payload [should not happen]...")
									streamDst:Seek(lumpInfoSrc.fileofs)
									streamDst:truncate()
								end
							else
								shouldErasePrevious = true
							end
						end
						lumpsDst[i] = lump_t:new(self, nil, false)
					end
					if shouldErasePrevious then
						if payloadSrcWriteProtected then
							print("\t\tNot erasing the previous payload because used elsewhere!")
						else
							-- The payload that used to be used for this lump id is not used anymore.
							LumpPayload:erasePrevious(self, streamDst, lumpInfoSrc)
						end
					end
				end
			end
		end
		-- Now lumpsDst & gameLumpsDst contain lumps in streamDst, with the effective fileofs.
		
		-- Write the file header (including lump_t's)
		local bspHeaderDst = dheader_t:new(self, nil, self.bspHeader, lumpsDst)
		bspHeaderDst:writeTo(streamDst)
	end,
	
	_writeEntitiesTextLua = function(self, mapFilenameDst)
		if self.entitiesTextLua then
			collectgarbage()
			local entitiesTextLua = self.entitiesTextLua
			local _, _, mapName = string.find(mapFilenameDst, "([^\\/]+)%.bsp%.dat$")
			if mapName then
				entitiesTextLua = string.gsub(entitiesTextLua, "%%mapName%%", stringToLuaString(mapName), 1)
			end
			local filenameDst = string.gsub(mapFilenameDst, "%.bsp%.dat$", "", 1) .. ".lua.txt"
			local streamDst = FileForWrite:new(filenameDst, "w", "DATA")
			if streamDst == nil then
				error('Unable to open "data/' .. filenameDst .. '" for write')
			end
			callSafe(streamDst.Write, streamDst, entitiesTextLua)
			streamDst:Close()
		end
	end,
	
	writeNewBsp = function(self, filenameDst)
		-- Note: compression / decompression is not applied if a lump is unchanged.
		
		local streamDst = FileForWrite:new(filenameDst, "wb", "DATA")
		if streamDst == nil then
			error('Unable to open "data/' .. filenameDst .. '" for write')
		end
		
		local success, message = callSafe(self.writeNewBsp_, self, streamDst)
		local possibleSavedSpace = streamDst:sizeUntruncated() - streamDst:Size()
		if possibleSavedSpace ~= 0 then
			print("You can save " .. possibleSavedSpace .. " bytes by loading & saving the modified map! Lua does not let us truncate it for you.")
		end
		streamDst:Close()
		if not success then
			error(message)
		end
		
		self:_writeEntitiesTextLua(filenameDst)
	end,
	
	_getLump = function(self, isGameLump, id, fromDst)
		-- This method can return nil.
		
		local lumpInfo
		local lumps
		if isGameLump then
			lumps = fromDst and self.gameLumpsDst or self.gameLumpsSrc
			for i, lumpInfoCurrent in ipairs(lumps) do
				if lumpInfoCurrent.id == id then
					lumpInfo = lumpInfoCurrent
					break
				end
			end
		else
			lumps = fromDst and self.lumpsDst or self.lumpsSrc
			lumpInfo = lumps[id]
		end
		return lumpInfo
	end,
	
	_copyLumpFieldsFromSrc = function(self, isGameLump, id, lumpInfo)
		-- Alter lumpInfo with information from self.lumpsSrc & self.gameLumpsSrc
		
		local lumpInfoSrc = self:_getLump(isGameLump, id, false)
		if lumpInfoSrc ~= nil then
			-- The replacement can always occur because the lump format is maintained in all cases.
			lumpInfo.version = lumpInfoSrc.version
			-- lumpInfo.fourCC is let as-is to keep the code simple.
			lumpInfo.id = lumpInfoSrc.id
			lumpInfo.flags = lumpInfoSrc.flags
		end
	end,
	
	mapSeemsCompressed = function(self)
		-- Estimates if the map is compressed
		
		if self._mapSeemsCompressed == nil then
			local compressedProbability = 0
			for location, lumps in ipairs({self.lumpsSrc, self.gameLumpsSrc}) do
				local neverCompressed
				if location == 1 then
					neverCompressed = lumpsNeverCompressed
				end
				for i = 1, #lumps do
					local ignore = (neverCompressed and neverCompressed[i])
					if not ignore then
						local payload = lumps[i].payload
						if payload then
							compressedProbability = compressedProbability + (payload.compressed and 1 or -1)
						end
					end
				end
			end
			self._mapSeemsCompressed = (compressedProbability > 0)
		end
		return self._mapSeemsCompressed
	end,
	
	_setDstLump = function(self, isGameLump, id, lumpInfo)
		-- Replace a lump in self.lumpsDst or self.gameLumpsDst
		-- Must be called to apply the lumpInfo into the destination lumps
		-- lumpInfo: can be nil if isGameLump, for game lump removal
		
		local lumpInfoOld
		if isGameLump then
			local gameLumpIndex = #self.gameLumpsDst + 1 -- append if existing not found
			for i, lumpInfoCurrent in ipairs(self.gameLumpsDst) do
				if lumpInfoCurrent.id == id then
					gameLumpIndex = i
					lumpInfoOld = lumpInfoCurrent
					break
				end
			end
			if lumpInfo then
				self.gameLumpsDst[gameLumpIndex] = lumpInfo
			else
				table.remove(self.gameLumpsDst, gameLumpIndex)
			end
		else
			lumpInfoOld = self.lumpsDst[id]
			self.lumpsDst[id] = lumpInfo
			-- Automatic compression:
			local toCompress
			local payloadInitial = self.lumpsSrc[id].payload
			if payloadInitial then
				toCompress = payloadInitial.compressed
			elseif lumpsNeverCompressed[id] then
				toCompress = false
			else
				toCompress = self:mapSeemsCompressed()
			end
			self:setLumpCompressed(id, toCompress)
		end
		self:_closeOldLumpStream(lumpInfoOld)
	end,
	
	revertLumpChanges = function(self, isGameLump, id)
		-- Revert modifications done to a lump
		local lumpInfoOld
		if isGameLump then
			local lumpInfoSrc
			for i = 1, #self.gameLumpsSrc do
				local lumpInfo = self.gameLumpsSrc[i]
				if lumpInfo.id == id then
					lumpInfoSrc = lumpInfo
					break
				end
			end
			local foundInDst = false
			for i = 1, #self.gameLumpsDst do
				local lumpInfo = self.gameLumpsDst[i]
				if lumpInfo.id == id then
					foundInDst = true
					lumpInfoOld = lumpInfo
					if lumpInfoSrc then
						self.gameLumpsDst[i] = lumpInfoSrc
					else
						table.remove(self.gameLumpsDst, i)
					end
					break
				end
			end
			if not foundInDst and lumpInfoSrc then
				self.gameLumpsDst[#self.gameLumpsDst + 1] = lumpInfoSrc
			end
		else
			lumpInfoOld = self.lumpsDst[id]
			self.lumpsDst[id] = self.lumpsSrc[id]
			self.lumpIndexesToCompress[id] = nil
		end
		self:_closeOldLumpStream(lumpInfoOld)
	end,
	
	_payloadUsedWriteProtected = function(self, payloadSrc)
		-- Checks if the payloadSrc is used in the output map, to protected it
		-- The whole design is not compatible with game lumps.
		
		if payloadSrc then
			local streamSrc = payloadSrc.streamSrc
			if streamSrc == self.streamSrc then -- just to be sure that payloadSrc is from the map
				local fileofs = payloadSrc.lumpInfoSrc.fileofs
				local lumpsDst = self.lumpsDst
				for i = 1, #lumpsDst do
					local payloadDst = lumpsDst[i].payload
					if payloadDst and payloadDst.streamSrc == streamSrc then
						-- payloadDst comes from the same stream as payloadSrc.
						if payloadDst.lumpInfoSrc.fileofs == fileofs then
							-- payloadSrc in use: it is write-protected.
							return true
						end
					end
				end
			end
		end
		return false
	end,
	
	clearLump = function(self, isGameLump, id)
		local lumpInfo
		if isGameLump then
			-- Game lumps must be removed instead of being replaced with a null lump.
			lumpInfo = nil
		else
			lumpInfo = lump_t:new(self, nil, false)
		end
		if lumpInfo then
			self:_copyLumpFieldsFromSrc(isGameLump, id, lumpInfo)
		end
		self:_setDstLump(isGameLump, id, lumpInfo)
		return lumpInfo
	end,
	
	setLumpCompressed = function(self, id, toCompress)
		-- Set the desired state of compression for the given lump
		-- This does not work on individual game lumps because game lump compression is common to all game lumps.
		-- Note: if at least 1 game lump is seen compressed (even in the original map) then all game lumps will be compressed.
		self.lumpIndexesToCompress[id] = toCompress
	end,
	
	_setupLumpFromHeaderlessStream = function(self, isGameLump, id, streamSrc)
		-- Make a lump_t or a dgamelump_t for the specified headerless stream
		-- The stream responsibility is given to the context, so it must be open for that occasion.
		
		local lumpInfo
		local lumpInfoSrc = self:_getLump(isGameLump, id, false)
		if isGameLump then
			lumpInfo = dgamelump_t:newFromPayloadStream(self, streamSrc, 0, streamSrc:Size(), lumpInfoSrc, id)
		else
			lumpInfo = lump_t:newFromPayloadStream(self, streamSrc, 0, streamSrc:Size(), lumpInfoSrc)
		end
		self:_copyLumpFieldsFromSrc(isGameLump, id, lumpInfo)
		self:_setDstLump(isGameLump, id, lumpInfo)
		return lumpInfo
	end,
	
	setupLumpFromHeaderlessFile = function(self, isGameLump, id, filePath)
		print("setupLumpFromHeaderlessFile",self, isGameLump, id, filePath)
		local streamSrc = file.Open(filePath, "rb", "GAME")
		return self:_setupLumpFromHeaderlessStream(isGameLump, id, streamSrc)
	end,
	
	setupLumpFromHeaderlessString = function(self, isGameLump, id, payloadString)
		local streamSrc = BytesIO:new(payloadString, "rb")
		return self:_setupLumpFromHeaderlessStream(isGameLump, id, streamSrc)
	end,
	
	setupLumpFromLumpFile = function(self, isGameLump, id, filePath)
		-- TODO
		-- TODO - détection du boutisme et erreur si différent
		error("Not implemented yet")
	end,
	
	setupLumpFromText = function(self, isGameLump, id, text)
		local payloadString
		local idText = getLumpNameFromLumpId(isGameLump, id)
		local lumpFieldsToSet = {}
		if isGameLump then
			if idText == "sprp" then
				-- Warning: keyvalue keys are all lower-case here!
				-- TODO - comprendre les physiques BBox
				local string_rep = string.rep
				local tonumber = tonumber
				local util_KeyValuesToTable = util.KeyValuesToTable
				local bit_band = bit.band
				local string_char = string.char
				local int16_to_data = self.int16_to_data
				local int32_to_data = self.int32_to_data
				local float32_to_data = self.float32_to_data
				
				local entitiesText = self:_explodeEntitiesText(text)
				for k, v in pairs(util_KeyValuesToTable('"Lump attributes"\x0A' .. entitiesText[1], false, true)) do
					if k == "version" or k == "flags" then -- security
						lumpFieldsToSet[k] = tonumber(v)
					end
				end
				lumpFieldsToSet.version = lumpFieldsToSet.version or 4
				local lumpVersion = lumpFieldsToSet.version
				
				local staticPropLeafLump = util.KeyValuesToTablePreserveOrder('"StaticPropLeafLump_t"\x0A' .. entitiesText[2], false, true)
				for i, leafPair in ipairs(staticPropLeafLump) do
					-- This ignores the key of the keyvalue (safer).
					staticPropLeafLump[i] = tonumber(leafPair.Value)
				end
				local leafEntries = #staticPropLeafLump
				
				local staticPropDictLump = {} -- index -> model
				local modelIndexes = {} -- model -> {index - 1} in staticPropDictLump
				local staticPropsKeyValues = {}
				for i = 3, #entitiesText do
					local entityText = entitiesText[i]
					entityText = keyValuesTextKeepNumberPrecision(entityText)
					local propKeyValues = util_KeyValuesToTable('"prop_static #' .. (i - 2) .. '"\x0A' .. entityText, false, false)
					if propKeyValues then
						staticPropsKeyValues[#staticPropsKeyValues + 1] = propKeyValues
						local model = propKeyValues["model"]
						if not model or #model > 127 then
							print('Invalid model "' .. tostring(model) .. '": value is missing or longer than 127 bytes!')
							model = "models/error.mdl"
							-- It does not help if it is simply removed.
						end
						if not modelIndexes[model] then
							local index = #staticPropDictLump + 1
							staticPropDictLump[index] = model
							modelIndexes[model] = index - 1
						end
					else
						staticPropsKeyValues[#staticPropsKeyValues + 1] = false -- to preserve indexes
						print("Could not decode the following prop_static description:")
						print(entityText)
					end
				end
				-- print("staticPropsKeyValues[1] =")PrintTable(staticPropsKeyValues[1]) -- debug
				
				local staticPropLumps = {}
				for i = 1, #staticPropsKeyValues do
					local propKeyValues = staticPropsKeyValues[i]
					if propKeyValues then
						local FirstLeaf = tonumber(propKeyValues["firstleaf"] or 0)
						local staticPropLump = {
							-- Default value included for every StaticPropLump_t field
							Origin = Vector(propKeyValues["origin"]), -- Vector
							Angles = Angle(propKeyValues["angles"]), -- QAngle
							PropType = modelIndexes[propKeyValues["model"]], -- unsigned short
							-- Deal with leaves the best we can:
							FirstLeaf = FirstLeaf, -- unsigned short
							LeafCount = tonumber(propKeyValues["leafcount"] or (leafEntries - FirstLeaf)), -- unsigned short
							Solid = tonumber(propKeyValues["solid"] or 6), -- unsigned char
							Flags = bit_band(tonumber(propKeyValues["flags"] or 0), 0xFF), -- unsigned char
							Skin = tonumber(propKeyValues["skin"] or 0), -- int
							FadeMinDist = tonumber(propKeyValues["fademindist"] or 0.), -- float
							FadeMaxDist = tonumber(propKeyValues["fademaxdist"] or 0.), -- float
							LightingOrigin = Vector(propKeyValues["lightingorigin~"]), -- Vector
							ForcedFadeScale = tonumber(propKeyValues["fadescale"] or 1.), -- float
							MinDXLevel = tonumber(propKeyValues["mindxlevel"] or 0), -- unsigned short
							MaxDXLevel = tonumber(propKeyValues["maxdxlevel"] or 0), -- unsigned short
							MinCPULevel = tonumber(propKeyValues["mincpulevel"] or 0), -- unsigned char
							MaxCPULevel = tonumber(propKeyValues["maxcpulevel"] or 0), -- unsigned char
							MinGPULevel = tonumber(propKeyValues["mingpulevel"] or 0), -- unsigned char
							MaxGPULevel = tonumber(propKeyValues["maxgpulevel"] or 0), -- unsigned char
							DiffuseModulation = ColorFromText(propKeyValues["rendercolor"], propKeyValues["renderamt"]), -- color32
							DisableX360 = tonumber(propKeyValues["disablex360"] or 0), -- bool
							FlagsEx = tonumber(propKeyValues["flagsex"] or 0), -- unsigned int
							UniformScale = tonumber(propKeyValues["modelscale"] or 1.), -- float
						}
						if staticPropLump.FirstLeaf >= leafEntries then
							error("Wrong value: FirstLeaf = " .. staticPropLump.FirstLeaf .. " out-of-range in prop_static #" .. i)
						end
						if staticPropLump.FirstLeaf + staticPropLump.LeafCount - 1 >= leafEntries then
							error("Wrong value: {FirstLeaf = " .. staticPropLump.FirstLeaf .. ", LeafCount = " .. staticPropLump.LeafCount .. "} out-of-range in prop_static #" .. i)
						end
						staticPropLumps[#staticPropLumps + 1] = staticPropLump
					else
						staticPropLumps[#staticPropLumps + 1] = false -- to preserve indexes
					end
				end
				
				local payloadPieces = {}
				
				-- Making StaticPropDictLump_t:
				payloadPieces[#payloadPieces + 1] = int32_to_data(#staticPropDictLump)
				for i = 1, #staticPropDictLump do
					local model = staticPropDictLump[i]
					payloadPieces[#payloadPieces + 1] = model
					payloadPieces[#payloadPieces + 1] = string_rep("\0", 128 - #model)
				end
				
				-- Making StaticPropLeafLump_t:
				payloadPieces[#payloadPieces + 1] = int32_to_data(leafEntries)
				for i = 1, leafEntries do
					payloadPieces[#payloadPieces + 1] = int16_to_data(staticPropLeafLump[i])
				end
				
				-- Making StaticPropLump_t's:
				payloadPieces[#payloadPieces + 1] = int32_to_data(#staticPropLumps)
				for i = 1, #staticPropLumps do
					local staticPropLump = staticPropLumps[i]
					if staticPropLump then
						-- Data here must absolutely be the same as in getStaticPropsList().
						payloadPieces[#payloadPieces + 1] = Vector_to_data(self, staticPropLump.Origin) -- Vector
						payloadPieces[#payloadPieces + 1] = QAngle_to_data(self, staticPropLump.Angles) -- QAngle
						payloadPieces[#payloadPieces + 1] = int16_to_data(staticPropLump.PropType) -- unsigned short
						payloadPieces[#payloadPieces + 1] = int16_to_data(staticPropLump.FirstLeaf) -- unsigned short
						payloadPieces[#payloadPieces + 1] = int16_to_data(staticPropLump.LeafCount) -- unsigned short
						payloadPieces[#payloadPieces + 1] = string_char(staticPropLump.Solid) -- unsigned char
						payloadPieces[#payloadPieces + 1] = string_char(staticPropLump.Flags) -- unsigned char
						payloadPieces[#payloadPieces + 1] = int32_to_data(staticPropLump.Skin) -- int
						payloadPieces[#payloadPieces + 1] = float32_to_data(staticPropLump.FadeMinDist) -- float
						payloadPieces[#payloadPieces + 1] = float32_to_data(staticPropLump.FadeMaxDist) -- float
						payloadPieces[#payloadPieces + 1] = Vector_to_data(self, staticPropLump.LightingOrigin) -- Vector
						if lumpVersion >= 5 then
							payloadPieces[#payloadPieces + 1] = float32_to_data(staticPropLump.ForcedFadeScale) -- float
						end
						if lumpVersion >= 6 and lumpVersion <= 7 then
							payloadPieces[#payloadPieces + 1] = int16_to_data(staticPropLump.MinDXLevel) -- unsigned short
							payloadPieces[#payloadPieces + 1] = int16_to_data(staticPropLump.MaxDXLevel) -- unsigned short
						end
						if lumpVersion >= 8 then
							payloadPieces[#payloadPieces + 1] = string_char(staticPropLump.MinCPULevel) -- unsigned char
							payloadPieces[#payloadPieces + 1] = string_char(staticPropLump.MaxCPULevel) -- unsigned char
							payloadPieces[#payloadPieces + 1] = string_char(staticPropLump.MinGPULevel) -- unsigned char
							payloadPieces[#payloadPieces + 1] = string_char(staticPropLump.MaxGPULevel) -- unsigned char
						end
						if lumpVersion == 10 and self.bspHeader.version == 20 then -- TF2 compatibility
							-- nothing here
						elseif (lumpVersion == 9  and self.bspHeader.version == 21) -- L4D2 compatibility
						or     (lumpVersion == 10 and self.bspHeader.version == 21) then -- CS:GO compatibility
							payloadPieces[#payloadPieces + 1] = color32_to_data(staticPropLump.DiffuseModulation) -- color32
						else
							if lumpVersion >= 7 then
								payloadPieces[#payloadPieces + 1] = color32_to_data(staticPropLump.DiffuseModulation) -- color32
							end
							if lumpVersion >= 9 and lumpVersion <= 10 then
								payloadPieces[#payloadPieces + 1] = int32_to_data(staticPropLump.DisableX360) -- bool
							end
						end
						if lumpVersion >= 10
						or (lumpVersion == 9 and self.bspHeader.version == 21) then -- L4D2 compatibility
							payloadPieces[#payloadPieces + 1] = int32_to_data(staticPropLump.FlagsEx) -- unsigned int
						end
						if (lumpVersion == 10 and self.bspHeader.version == 21) -- CS:GO compatibility
						or (lumpVersion == 11 and self.bspHeader.version == 21) -- CS:GO compatibility
						or (lumpVersion == 10 and self.bspHeader.version == 20) then -- TF2 compatibility
							payloadPieces[#payloadPieces + 1] = int32_to_data(staticPropLump.DisableX360) -- bool
						end
						if lumpVersion >= 11 then
							payloadPieces[#payloadPieces + 1] = float32_to_data(staticPropLump.UniformScale) -- float
						end
					end
				end
				
				payloadString = table.concat(payloadPieces)
			else
				error('Unsupported conversion from text to Game Lump "' .. tostring(idText or id) .. '"')
			end
		else
			if idText == "LUMP_ENTITIES" then
				payloadString = string.gsub(text, "\r\n", "\n") .. "\0" -- may take some time
			elseif idText == "LUMP_TEXDATA_STRING_DATA" then
				local materials = {} -- no duplicated values
				local materialsOffsets = {} -- 4-byte binary strings
				do
					local materialOffsetsCache = {}
					local nextMaterialOffset = 0
					-- The following pattern:
					-- - Allows different end-of-line kinds
					-- - Tolerates that the terminating empty line is missing
					-- - Tolerates empty lines
					for material, eol in string.gmatch(text, "([^\x0D\x0A]*)([\x0D]?[\x0A]?)") do
						if #material ~= 0 or #eol ~= 0 then
							local materialOffset = materialOffsetsCache[material]
							if materialOffset == nil then
								materialOffset = self.int32_to_data(nextMaterialOffset)
								nextMaterialOffset = nextMaterialOffset + #material + 1
								materialOffsetsCache[material] = materialOffset
								materials[#materials + 1] = material
							else
								print('Duplicated material "' .. material .. '", merging!')
							end
							materialsOffsets[#materialsOffsets + 1] = materialOffset
						else
							-- This is the trailing empty line!
						end
					end
				end
				materials[#materials + 1] = "" -- no final null-byte otherwise
				payloadString = table.concat(materials, "\0")
				self:setupLumpFromHeaderlessString(
					false,
					lumpNameToLuaIndex["LUMP_TEXDATA_STRING_TABLE"],
					table.concat(materialsOffsets)
				)
			elseif idText == "LUMP_OVERLAYS" then
				-- Warning: keyvalue keys are all lower-case here!
				local tonumber = tonumber
				local util_KeyValuesToTable = util.KeyValuesToTable
				local bit_bor = bit.bor
				local bit_lshift = bit.lshift
				local int16_to_data = self.int16_to_data
				local int32_to_data = self.int32_to_data
				local float32_to_data = self.float32_to_data
				
				local entitiesText = self:_explodeEntitiesText(text)
				for k, v in pairs(util_KeyValuesToTable('"Lump attributes"\x0A' .. entitiesText[1], false, true)) do
					if k == "version" or k == "fourcc" then -- security
						lumpFieldsToSet[k] = tonumber(v)
					end
				end
				lumpFieldsToSet.version = lumpFieldsToSet.version or 0
				
				local payloadPieces = {}
				for i = 2, #entitiesText do
					local entityText = entitiesText[i]
					entityText = keyValuesTextKeepNumberPrecision(entityText)
					local overlayKeyValues = util_KeyValuesToTable('"info_overlay #' .. (i - 2) .. '"\x0A' .. entityText, false, false)
					if overlayKeyValues then
						-- Data here must absolutely be the same as in getInfoOverlaysList().
						payloadPieces[#payloadPieces + 1] = int32_to_data(tonumber(overlayKeyValues["id"])) -- int
						payloadPieces[#payloadPieces + 1] = int16_to_data(tonumber(overlayKeyValues["texinfo"])) -- short
						do
							local FaceCountAndRenderOrder = bit_bor(
								bit_lshift(tonumber(overlayKeyValues["renderorder"] or 0), 14),
								tonumber(overlayKeyValues["facecount"] or 0)
							)
							payloadPieces[#payloadPieces + 1] = int16_to_data(FaceCountAndRenderOrder) -- unsigned short
						end
						for face = 1, OVERLAY_BSP_FACE_COUNT do
							payloadPieces[#payloadPieces + 1] = int32_to_data(tonumber(overlayKeyValues["ofaces:" .. face] or 0)) -- int
						end
						payloadPieces[#payloadPieces + 1] = float32_to_data(tonumber(overlayKeyValues["startu"])) -- float
						payloadPieces[#payloadPieces + 1] = float32_to_data(tonumber(overlayKeyValues["endu"])) -- float
						payloadPieces[#payloadPieces + 1] = float32_to_data(tonumber(overlayKeyValues["startv"])) -- float
						payloadPieces[#payloadPieces + 1] = float32_to_data(tonumber(overlayKeyValues["endv"])) -- float
						payloadPieces[#payloadPieces + 1] = Vector_to_data(self, Vector(overlayKeyValues["uv0"])) -- Vector
						payloadPieces[#payloadPieces + 1] = Vector_to_data(self, Vector(overlayKeyValues["uv1"])) -- Vector
						payloadPieces[#payloadPieces + 1] = Vector_to_data(self, Vector(overlayKeyValues["uv2"])) -- Vector
						payloadPieces[#payloadPieces + 1] = Vector_to_data(self, Vector(overlayKeyValues["uv3"])) -- Vector
						payloadPieces[#payloadPieces + 1] = Vector_to_data(self, Vector(overlayKeyValues["basisorigin"])) -- Vector
						payloadPieces[#payloadPieces + 1] = Vector_to_data(self, Vector(overlayKeyValues["basisnormal"])) -- Vector
					else
						print("Could not decode the following info_overlay description:")
						print(entityText)
					end
				end
				
				payloadString = table.concat(payloadPieces)
			else
				error('Unsupported conversion from text to Lump "' .. tostring(idText or id) .. '"')
			end
		end
		local lumpInfo = self:setupLumpFromHeaderlessString(isGameLump, id, payloadString)
		for k, v in pairs(lumpFieldsToSet) do
			lumpInfo[k] = v
		end
		return lumpInfo
	end,
	
	setupLumpFromTextFile = function(self, isGameLump, id, filePath)
		local textFile = file.Open(filePath, "rb", "GAME")
		local text = textFile:Read(textFile:Size())
		textFile:Close()
		return self:setupLumpFromText(isGameLump, id, text)
	end,
	
	extractLumpAsHeaderlessFile = function(self, isGameLump, id, fromDst, filePath, withCompression)
		local idText = getLumpNameFromLumpId(isGameLump, id)
		local lumpInfo = self:_getLump(isGameLump, id, fromDst)
		local payload = lumpInfo.payload
		if payload ~= nil then
			local streamDst = FileForWrite:new(filePath, "wb", "DATA")
			if streamDst == nil then
				error('Unable to open "data/' .. filePath .. '" for write')
			end
			callSafe(payload.copyTo, payload, streamDst, withCompression, nil, nil, nil, true)
			streamDst:Close()
		else
			error("The specified lump is a null lump!")
		end
	end,
	
	extractLumpAsText = function(self, isGameLump, id, fromDst)
		local string_find = string.find
		local idText = getLumpNameFromLumpId(isGameLump, id)
		local lumpInfo = self:_getLump(isGameLump, id, fromDst)
		local payload = lumpInfo.payload
		if payload == nil then
			error("The specified lump is a null lump!")
		end
		local text
		if isGameLump then
			if idText == "sprp" then
				local string_format = string.format
				local textLines = {}
				
				-- Lump info:
				textLines[#textLines + 1] = [[{]]
				local lumpInfo = self:_getLump(true, getLumpIdFromLumpName("sprp"), fromDst)
				local lumpVersion = lumpInfo.version
				textLines[#textLines + 1] = string_format('"version" "%u"', lumpInfo.version)
				textLines[#textLines + 1] = string_format('"flags" "%u"', lumpInfo.flags)
				textLines[#textLines + 1] = [[}]]
				
				-- Leaves dictionary:
				local staticPropsKeyValues, staticPropLeafLump = self:getStaticPropsList(fromDst)
				textLines[#textLines + 1] = [[{]]
				for leafLocal, leafGlobal in ipairs(staticPropLeafLump) do
					textLines[#textLines + 1] = string_format('"%u" "%u"', (leafLocal - 1), leafGlobal)
				end
				textLines[#textLines + 1] = [[}]]
				
				-- Static props:
				for i, propKeyValues in ipairs(staticPropsKeyValues) do
					textLines[#textLines + 1] = [[{]]
					textLines[#textLines + 1] = [["classname" "prop_static"]]
					for _, key in ipairs(staticPropsKeyValuesOrder) do
						local value = propKeyValues[key]
						if value ~= nil then
							textLines[#textLines + 1] = string_format('%s %s', anyToKeyValueString(key), anyToKeyValueString(value))
						end
					end
					textLines[#textLines + 1] = [[}]]
				end
				
				-- Finish:
				textLines[#textLines + 1] = [[]] -- empty line
				text = table.concat(textLines, "\x0A")
			else
				error('Unsupported conversion to text from Game Lump "' .. tostring(idText or id) .. '"')
			end
		else
			if idText == "LUMP_ENTITIES" then
				local _
				_, _, text = string_find(payload:readAll(), "^([^%z]+)") -- closer to engine's behavior
				--[[
				if string.sub(payloadString, -1, -1) == "\0" then -- ends with a null byte
					text = string.sub(payloadString, 1, -2) -- remove the ending null byte
				end
				]]
			elseif idText == "LUMP_TEXDATA_STRING_DATA" then
				local materials = self:getMaterialsList(fromDst)
				materials[#materials + 1] = "" -- empty line
				text = table.concat(materials, "\x0A")
			elseif idText == "LUMP_OVERLAYS" then
				local string_format = string.format
				local textLines = {}
				local overlaysKeyValues = self:getInfoOverlaysList(fromDst)
				
				-- Lump info:
				textLines[#textLines + 1] = [[{]]
				local lumpInfo = self:_getLump(false, lumpNameToLuaIndex["LUMP_OVERLAYS"], fromDst)
				textLines[#textLines + 1] = string_format('"version" "%u"', lumpInfo.version)
				textLines[#textLines + 1] = string_format('"fourCC" "%u"', lumpInfo.fourCC)
				textLines[#textLines + 1] = [[}]]
				
				-- Overlays:
				for i, overlayKeyValues in ipairs(overlaysKeyValues) do
					textLines[#textLines + 1] = [[{]]
					textLines[#textLines + 1] = [["classname" "info_overlay"]]
					for _, key in ipairs(infoOverlaysKeyValuesOrder) do
						local value = overlayKeyValues[key]
						if value ~= nil then
							if infoOverlaysKeyValuesAsComment[key] then
								textLines[#textLines + 1] = string_format('//%s %s', anyToKeyValueString(key), anyToKeyValueString(value))
							else
								textLines[#textLines + 1] = string_format('%s %s', anyToKeyValueString(key), anyToKeyValueString(value))
							end
						end
					end
					for j, face in ipairs(overlayKeyValues["Ofaces"]) do
						textLines[#textLines + 1] = string_format('"Ofaces:%u" "%d"', j, face)
					end
					textLines[#textLines + 1] = [[}]]
				end
				
				-- Finish:
				textLines[#textLines + 1] = [[]] -- empty line
				text = table.concat(textLines, "\x0A")
			else
				error('Unsupported conversion to text from Lump "' .. tostring(idText or id) .. '"')
			end
		end
		return text
	end,
	
	extractLumpAsTextFile = function(self, isGameLump, id, fromDst, filePath)
		local text = self:extractLumpAsText(isGameLump, id, fromDst)
		local streamDst = FileForWrite:new(filePath, "wb", "DATA")
		if streamDst == nil then
			error('Unable to open "data/' .. filePath .. '" for write')
		end
		callSafe(streamDst.Write, streamDst, text)
		streamDst:Close()
	end,
	
	getStaticPropsList = function(self, fromDst)
		local string_find = string.find
		local data_to_integer = self.data_to_integer
		local data_to_float32 = self.data_to_float32
		local pairs = pairs
		local string_format = string.format
		
		local lumpInfo = self:_getLump(true, getLumpIdFromLumpName("sprp"), fromDst)
		local lumpVersion = lumpInfo.version
		local payload = lumpInfo and lumpInfo.payload or nil
		if payload == nil then
			print("No sprp game lump: no prop_static's in the map!")
			return {}, {}, {}, {}
		end
		-- local lumpStream = BytesIO:new(payload:readAll(), "rb")
		payload:seekToPayload()
		local lumpStream = payload.streamSrc
		
		-- Parsing StaticPropDictLump_t:
		-- Original keys kept because used as a dictionary.
		local staticPropDictLump = {}
		local dictEntries = data_to_integer(lumpStream:Read(4))
		for i = 0, dictEntries - 1 do
			local _, _, model = string_find(lumpStream:Read(128), "^([^%z]*)")
			staticPropDictLump[i] = model
		end
		
		-- Parsing StaticPropLeafLump_t:
		-- Original keys not kept because exported as-is.
		local staticPropLeafLump = {}
		local leafEntries = data_to_integer(lumpStream:Read(4))
		for i = 1, leafEntries do
			staticPropLeafLump[i] = data_to_integer(lumpStream:Read(2))
		end
		
		-- Parsing all StaticPropLump_t's:
		local staticPropLumps = {}
		for i = 1, data_to_integer(lumpStream:Read(4)) do
			-- The structure is based on information on the wiki as seen on 2020-01-15.
			-- IMPORTANT !! Additions to this must be updated in staticPropsKeyValuesOrder!
			local staticPropLump = {}
			staticPropLump.Origin = decode_Vector(self, lumpStream) -- Vector
			staticPropLump.Angles = decode_QAngle(self, lumpStream) -- QAngle
			staticPropLump.PropType = data_to_integer(lumpStream:Read(2)) -- unsigned short
			if not staticPropDictLump[staticPropLump.PropType] then
				error("Wrong sprp game lump format: StaticPropLump_t.PropType out-of-range in prop_static #" .. i)
			end
			staticPropLump.FirstLeaf = data_to_integer(lumpStream:Read(2)) -- unsigned short
			if staticPropLump.FirstLeaf >= leafEntries then
				error("Wrong sprp game lump format: StaticPropLump_t.FirstLeaf out-of-range in prop_static #" .. i)
			end
			staticPropLump.LeafCount = data_to_integer(lumpStream:Read(2)) -- unsigned short
			if staticPropLump.FirstLeaf + staticPropLump.LeafCount - 1 >= leafEntries then
				error("Wrong sprp game lump format: StaticPropLump_t.LeafCount out-of-range in prop_static #" .. i)
			end
			staticPropLump.Solid = data_to_integer(lumpStream:Read(1)) -- unsigned char
			staticPropLump.Flags = data_to_integer(lumpStream:Read(1)) -- unsigned char
			staticPropLump.Skin = data_to_integer(lumpStream:Read(4)) -- int
			staticPropLump.FadeMinDist = data_to_float32(lumpStream:Read(4)) -- float
			staticPropLump.FadeMaxDist = data_to_float32(lumpStream:Read(4)) -- float
			staticPropLump.LightingOrigin = decode_Vector(self, lumpStream) -- Vector
			if lumpVersion >= 5 then
				staticPropLump.ForcedFadeScale = data_to_float32(lumpStream:Read(4)) -- float
			end
			if lumpVersion >= 6 and lumpVersion <= 7 then
				staticPropLump.MinDXLevel = data_to_integer(lumpStream:Read(2)) -- unsigned short
				staticPropLump.MaxDXLevel = data_to_integer(lumpStream:Read(2)) -- unsigned short
			end
			if lumpVersion >= 8 then
				staticPropLump.MinCPULevel = data_to_integer(lumpStream:Read(1)) -- unsigned char
				staticPropLump.MaxCPULevel = data_to_integer(lumpStream:Read(1)) -- unsigned char
				staticPropLump.MinGPULevel = data_to_integer(lumpStream:Read(1)) -- unsigned char
				staticPropLump.MaxGPULevel = data_to_integer(lumpStream:Read(1)) -- unsigned char
			end
			if lumpVersion == 10 and self.bspHeader.version == 20 then -- TF2 compatibility
				-- nothing here
			elseif (lumpVersion == 9  and self.bspHeader.version == 21) -- L4D2 compatibility
			or     (lumpVersion == 10 and self.bspHeader.version == 21) then -- CS:GO compatibility
				staticPropLump.DiffuseModulation = decode_color32(lumpStream) -- color32
			else
				if lumpVersion >= 7 then
					staticPropLump.DiffuseModulation = decode_color32(lumpStream) -- color32
				end
				if lumpVersion >= 9 and lumpVersion <= 10 then
					staticPropLump.DisableX360 = data_to_integer(lumpStream:Read(4)) -- bool
				end
			end
			if lumpVersion >= 10
			or (lumpVersion == 9 and self.bspHeader.version == 21) then -- L4D2 compatibility
				-- Example: CS:GO version 10 (map v21) (cs_agency, de_shortdust)
				-- Wrong documentation: invalid with TF2 version 10 (map v20) (ctf_hellfire, koth_lazarus) (excess of 4 bytes + wrong layout)
				staticPropLump.FlagsEx = data_to_integer(lumpStream:Read(4)) -- unsigned int
			end
			if (lumpVersion == 10 and self.bspHeader.version == 21) -- CS:GO compatibility
			or (lumpVersion == 11 and self.bspHeader.version == 21) -- CS:GO compatibility
			or (lumpVersion == 10 and self.bspHeader.version == 20) then -- TF2 compatibility
				-- Wrong documentation: seems to be still there with CS:GO version 11 (map v21) (de_shortnuke)
				-- Wrong documentation: seems to be moved here with TF2 version 10 (map v20) (ctf_hellfire, koth_lazarus)
				-- In both cases, the actual usage is probably not bool nor "DisableX360".
				staticPropLump.DisableX360 = data_to_integer(lumpStream:Read(4)) -- bool
			end
			if lumpVersion >= 11 then
				-- Example: CS:GO version 11 (map v21) (de_shortnuke)
				staticPropLump.UniformScale = data_to_float32(lumpStream:Read(4)) -- float
			end
			staticPropLumps[#staticPropLumps + 1] = staticPropLump
		end
		
		-- Transform staticPropLumps into the same, but with translated fields (identical to prop_dynamic keyvalues):
		local staticPropsKeyValues = {}
		for i, propInfo in ipairs(staticPropLumps) do
			local propKeyValues = {}
			for key, value in pairs(propInfo) do
				-- The keys belong to both prop_static's and prop_dynamic's.
				-- The keys are listed in FGDs and the wiki.
				if key == "Origin" then
					propKeyValues["origin"] = value
				elseif key == "Angles" then
					propKeyValues["angles"] = value
				elseif key == "PropType" then
					propKeyValues["model"] = staticPropDictLump[value]
				elseif key == "Solid" then
					propKeyValues["solid"] = value
				elseif key == "Skin" then
					propKeyValues["skin"] = value
				elseif key == "FadeMinDist" then
					propKeyValues["fademindist"] = value
				elseif key == "FadeMaxDist" then
					propKeyValues["fademaxdist"] = value
				elseif key == "LightingOrigin" then
					-- Vector in StaticPropLump_t but targetname in the game: renamed
					propKeyValues["lightingorigin~"] = value
				elseif key == "ForcedFadeScale" then
					propKeyValues["fadescale"] = value
				elseif key == "MinDXLevel" then
					propKeyValues["mindxlevel"] = value
				elseif key == "MaxDXLevel" then
					propKeyValues["maxdxlevel"] = value
				elseif key == "MinCPULevel" then
					propKeyValues["mincpulevel"] = value
				elseif key == "MaxCPULevel" then
					propKeyValues["maxcpulevel"] = value
				elseif key == "MinGPULevel" then
					propKeyValues["mingpulevel"] = value
				elseif key == "MaxGPULevel" then
					propKeyValues["maxgpulevel"] = value
				elseif key == "DiffuseModulation" then
					propKeyValues["rendercolor"] = string_format("%u %u %u", value.r, value.g, value.b)
					propKeyValues["renderamt"] = value.a
				elseif key == "DisableX360" then
					propKeyValues["disableX360"] = value
				elseif key == "UniformScale" then
					propKeyValues["modelscale"] = value
				else
					propKeyValues[key] = value
				end
			end
			staticPropsKeyValues[#staticPropsKeyValues + 1] = propKeyValues
		end
		
		-- Check that fields do not contain illegal values, and display warnings:
		do
			local isvector = isvector
			local isangle = isangle
			local isnumber = isnumber
			local tostring = tostring
			local warnedFields = {}
			for i = 1, #staticPropsKeyValues do
				for key, value in pairs(staticPropsKeyValues[i]) do
					if not warnedFields[key] then
						local floatsToCheck
						if isvector(value) then
							floatsToCheck = {value.x, value.y, value.z}
						elseif isangle(value) then
							floatsToCheck = {value.p, value.y, value.r}
						elseif isnumber(value) then
							floatsToCheck = {value}
						end
						if floatsToCheck then
							for j = 1, #floatsToCheck do
								local textFloatToCheck = tostring(floatsToCheck[j])
								if textFloatToCheck == FLOAT_TEXT_NAN
								or textFloatToCheck == FLOAT_TEXT_INF_POSI
								or textFloatToCheck == FLOAT_TEXT_INF_NEGA then
									print(
										'Warning: sprp game lump as text not safe to import back due to weird numbers for keyvalue "'
										.. key
										.. '"'
									)
									warnedFields[key] = true
									break
								end
							end
						end
					end
				end
			end
		end
		
		return staticPropsKeyValues, staticPropLeafLump, staticPropLumps, staticPropDictLump
	end,
	
	getInfoOverlaysList = function(self, fromDst)
		-- Extract all information as a list of dictionaries with info_overlay keyvalues
		-- Note: the number of info_overlay's is determined from the payload length.
		
		local string_format = string.format
		local data_to_integer = self.data_to_integer
		local data_to_float32 = self.data_to_float32
		local bit_band = bit.band
		local bit_rshift = bit.rshift
		
		local lumpInfo = self:_getLump(false, lumpNameToLuaIndex["LUMP_OVERLAYS"], fromDst)
		local payload = lumpInfo and lumpInfo.payload or nil
		if payload == nil then
			print("No LUMP_OVERLAYS lump: no info_overlay's in the map!")
			return {}
		end
		local texinfosFields = self:_getTexinfoList(fromDst)
		local texdatasFields = self:_getTexdataList(fromDst)
		local materials = self:getMaterialsList(fromDst)
		payload:seekToPayload() -- after loading other lump payloads
		local lumpStream = payload.streamSrc
		local lumpLength = payload.lumpInfoSrc.filelen
		
		local overlaysKeyValues = {}
		do
			-- count cannot be 0 because it would be a null lump.
			local startPos = lumpStream:Tell()
			local i, count = 1, 1
			while i <= count do
				-- IMPORTANT !! Additions to this must be updated in infoOverlaysKeyValuesOrder!
				local info = {}
				info["Id"] = data_to_integer(lumpStream:Read(4)) -- int		[different from .vmf]
				do
					local material
					local TexInfo = data_to_integer(lumpStream:Read(2)) -- short
					info["TexInfo"] = TexInfo
					local texinfoFields = texinfosFields[TexInfo + 1]
					if texinfoFields ~= nil then
						local texdata = texinfoFields["texdata"]
						local texdataFields = texdatasFields[texdata + 1]
						if texdataFields ~= nil then
							local nameStringTableID = texdataFields["nameStringTableID"]
							material = materials[nameStringTableID + 1]
							if material == nil then
								print(string_format(
									"info_overlay #%u has an out-of-range material, dtexdata_t.nameStringTableID=%u, texinfo_t.texdata=%u, doverlay_t.TexInfo=%u",
									i,
									nameStringTableID,
									texdata,
									TexInfo
								))
							end
						else
							print(string_format(
								"info_overlay #%u has an out-of-range texdata, texinfo_t.texdata=%u, doverlay_t.TexInfo=%u",
								i,
								texdata,
								TexInfo
							))
						end
					else
						print(string_format(
							"info_overlay #%u has an out-of-range TexInfo, doverlay_t.TexInfo=%u",
							i,
							TexInfo
						))
					end
					if material == nil then
						material = "**OUT-OF-RANGE:" .. TexInfo
					end
					info["material"] = material
				end
				do
					local FaceCountAndRenderOrder = data_to_integer(lumpStream:Read(2)) -- unsigned short
					info["RenderOrder"] = bit_rshift(FaceCountAndRenderOrder, 14)
					info["FaceCount"] = bit_band(FaceCountAndRenderOrder, 0x3FFF)
				end
				do
					local Ofaces = {}
					for j = 1, OVERLAY_BSP_FACE_COUNT do
						Ofaces[j] = data_to_integer(lumpStream:Read(4)) -- int
					end
					info["Ofaces"] = Ofaces
				end
				info["StartU"] = data_to_float32(lumpStream:Read(4)) -- float
				info["EndU"] = data_to_float32(lumpStream:Read(4)) -- float
				info["StartV"] = data_to_float32(lumpStream:Read(4)) -- float
				info["EndV"] = data_to_float32(lumpStream:Read(4)) -- float
				info["uv0"] = decode_Vector(self, lumpStream) -- Vector
				info["uv1"] = decode_Vector(self, lumpStream) -- Vector
				info["uv2"] = decode_Vector(self, lumpStream) -- Vector
				info["uv3"] = decode_Vector(self, lumpStream) -- Vector
				do
					local Origin = decode_Vector(self, lumpStream) -- Vector
					info["BasisOrigin"] = Origin
					info["origin"] = Origin
				end
				info["BasisNormal"] = decode_Vector(self, lumpStream) -- Vector
				overlaysKeyValues[i] = info
				
				if count == 1 then
					-- Determine the actual count:
					local overlayLength = lumpStream:Tell() - startPos
					count = lumpLength / overlayLength
					if count % 1 ~= 0 then
						print("The LUMP_OVERLAYS does not end at the end of an info_overlay! Unsupported lump format?")
					end
					count = math.floor(count)
				end
				i = i + 1
			end
		end
		
		return overlaysKeyValues
	end,
	
	getMaterialsList = function(self, fromDst)
		local string_find = string.find
		
		local payloadStringData = self:_getLump(false, lumpNameToLuaIndex["LUMP_TEXDATA_STRING_DATA"], fromDst).payload
		if payloadStringData == nil then
			print("The LUMP_TEXDATA_STRING_DATA is a null lump, cannot proceed!")
			return {}
		end
		local binaryStringData = payloadStringData:readAll()
		
		local payloadStringTable = self:_getLump(false, lumpNameToLuaIndex["LUMP_TEXDATA_STRING_TABLE"], fromDst).payload
		if payloadStringTable == nil then
			print("The LUMP_TEXDATA_STRING_TABLE is a null lump, fallback activated!")
		end
		local binaryStringTable = payloadStringTable and payloadStringTable:readAll() or nil
		
		local materials = {}
		if binaryStringTable then
			-- Using offsets to find every material:
			for materialOffset in string.gmatch(binaryStringTable, "(....)") do
				materialOffset = self.data_to_integer(materialOffset)
				local _, _, material = string_find(binaryStringData, "^([^%z]*)%z", materialOffset + 1)
				materials[#materials + 1] = material
			end
		else -- missing LUMP_TEXDATA_STRING_TABLE
			-- Reading strings until the end:
			for material in string.gmatch(binaryStringData, "([^%z]*)%z") do
				materials[#materials + 1] = material
			end
		end
		
		return materials
	end,
	
	getMaterialsOverlayDecal = function(self, fromDst)
		-- Returns 3 items:
		-- - a sorted list of materials used in info_overlay and infodecal entities
		-- - a table: for each material, the number of uses in info_overlay entities
		-- - a table: for each material, the number of uses in infodecal entities
		-- The material path case is preserved, with a preference for the one mentioned in infodecal.
		-- In case of an error, the respective count table will be false.
		
		local allMaterials
		local countsOverlay = false
		local countsDecal = false
		
		local materialCaseLowerToOriginal = {}
		
		do
			local success, overlaysKeyValues = pcall(self.getInfoOverlaysList, self, fromDst)
			if success then
				countsOverlay = setmetatable({}, DICTIONARY_DEFAULT_0)
				for _, overlayKeyValues in ipairs(overlaysKeyValues) do
					local material = overlayKeyValues["material"]
					local materialLower = string.lower(material)
					materialCaseLowerToOriginal[materialLower] = material
					countsOverlay[materialLower] = countsOverlay[materialLower] + 1
				end
			else
				ErrorNoHalt(overlaysKeyValues .. "\n")
			end
		end
		
		do
			local util_KeyValuesToTable = util.KeyValuesToTable
			local success
			local lumpContent
			do
				success, lumpContent = pcall(self.extractLumpAsText, self, false, lumpNameToLuaIndex.LUMP_ENTITIES, fromDst)
				if not success then
					ErrorNoHalt(lumpContent .. "\n")
				end
			end
			local entitiesText
			if success and lumpContent then
				success, entitiesText = pcall(self._explodeEntitiesText, self, lumpContent)
				if success then
					countsDecal = setmetatable({}, DICTIONARY_DEFAULT_0)
				else
					ErrorNoHalt(entitiesText .. "\n")
				end
			end
			if entitiesText then
				for i = 1, #entitiesText do
					local decalKeyValues = util_KeyValuesToTable('"entities[' .. i .. ']"\x0A' .. entitiesText[i], false, false)
					if decalKeyValues then
						local classname = decalKeyValues["classname"]
						classname = classname and tostring(classname)
						classname = classname and string.lower(classname)
						if classname == "infodecal" then
							local material = decalKeyValues["texture"]
							local materialLower = string.lower(material)
							materialCaseLowerToOriginal[materialLower] = material
							countsDecal[materialLower] = countsDecal[materialLower] + 1
						end
					end
				end
			end
		end
		
		do
			-- Making & sorting the list:
			local allMaterials_ = {}
			for _, materialCounts in ipairs({countsOverlay, countsDecal}) do
				if materialCounts then
					for materialLower in pairs(materialCounts) do
						allMaterials_[materialLower] = true
					end
				end
			end
			allMaterials = {}
			for materialLower in pairs(allMaterials_) do
				allMaterials[#allMaterials + 1] = materialLower
			end
			table.sort(allMaterials)
			
			-- Restoring materials case:
			local countsOverlay_ = countsOverlay
			if countsOverlay_ then
				countsOverlay = setmetatable({}, DICTIONARY_DEFAULT_0)
			end
			local countsDecal_ = countsDecal
			if countsDecal_ then
				countsDecal = setmetatable({}, DICTIONARY_DEFAULT_0)
			end
			for i, materialLower in ipairs(allMaterials) do
				local material = materialCaseLowerToOriginal[materialLower]
				allMaterials[i] = material
				if countsOverlay_ then
					countsOverlay[material] = countsOverlay_[materialLower]
				end
				if countsDecal_ then
					countsDecal[material] = countsDecal_[materialLower]
				end
			end
		end
		
		return allMaterials, countsOverlay, countsDecal
	end,
	
	_getTexdataList = function(self, fromDst)
		-- Decode dtexdata_t's contained in the LUMP_TEXDATA
		-- The code is similar to that of getInfoOverlaysList().
		-- Warning: this function alters the cursor of the file descriptor.
		
		local data_to_integer = self.data_to_integer
		
		local lumpInfo = self:_getLump(false, lumpNameToLuaIndex["LUMP_TEXDATA"], fromDst)
		local payload = lumpInfo and lumpInfo.payload or nil
		if payload == nil then
			print("No LUMP_TEXDATA lump: no dtexdata_t's in the map!")
			return {}
		end
		payload:seekToPayload()
		local lumpStream = payload.streamSrc
		local lumpLength = payload.lumpInfoSrc.filelen
		
		local texdatasFields = {}
		do
			-- count cannot be 0 because it would be a null lump.
			local startPos = lumpStream:Tell()
			local i, count = 1, 1
			while i <= count do
				local fields = {}
				fields["reflectivity"] = decode_Vector(self, lumpStream) -- Vector
				fields["nameStringTableID"] = data_to_integer(lumpStream:Read(4)) -- int
				fields["width"] = data_to_integer(lumpStream:Read(4)) -- int
				fields["height"] = data_to_integer(lumpStream:Read(4)) -- int
				fields["view_width"] = data_to_integer(lumpStream:Read(4)) -- int
				fields["view_height"] = data_to_integer(lumpStream:Read(4)) -- int
				texdatasFields[i] = fields
				
				if count == 1 then
					-- Determine the actual count:
					local texdataLength = lumpStream:Tell() - startPos
					count = lumpLength / texdataLength
					if count % 1 ~= 0 then
						print("The LUMP_TEXDATA does not end at the end of a dtexdata_t! Unsupported lump format?")
					end
					count = math.floor(count)
				end
				i = i + 1
			end
		end
		
		return texdatasFields
	end,
	
	_getTexinfoList = function(self, fromDst)
		-- Decode texinfo_t's contained in the LUMP_TEXINFO
		-- The code is similar to that of _getTexdataList().
		-- Warning: this function alters the cursor of the file descriptor.
		
		local data_to_integer = self.data_to_integer
		local data_to_float32 = self.data_to_float32
		
		local lumpInfo = self:_getLump(false, lumpNameToLuaIndex["LUMP_TEXINFO"], fromDst)
		local payload = lumpInfo and lumpInfo.payload or nil
		if payload == nil then
			print("No LUMP_TEXINFO lump: no texinfo_t's in the map!")
			return {}
		end
		payload:seekToPayload()
		local lumpStream = payload.streamSrc
		local lumpLength = payload.lumpInfoSrc.filelen
		
		local texinfosFields = {}
		do
			-- count cannot be 0 because it would be a null lump.
			local startPos = lumpStream:Tell()
			local i, count = 1, 1
			while i <= count do
				local fields = {}
				do
					local textureVecs = {}
					for j = 1, 4 do
						local textureVecsJ = {}
						for k = 1, 2 do
							textureVecsJ[k] = data_to_float32(lumpStream:Read(4)) -- float
						end
						textureVecs[j] = textureVecsJ
					end
					fields["textureVecs"] = textureVecs
				end
				do
					local lightmapVecs = {}
					for j = 1, 4 do
						local lightmapVecsJ = {}
						for k = 1, 2 do
							lightmapVecsJ[k] = data_to_float32(lumpStream:Read(4)) -- float
						end
						lightmapVecs[j] = lightmapVecsJ
					end
					fields["lightmapVecs"] = lightmapVecs
				end
				fields["flags"] = data_to_integer(lumpStream:Read(4)) -- int
				fields["texdata"] = data_to_integer(lumpStream:Read(4)) -- int
				texinfosFields[i] = fields
				
				if count == 1 then
					-- Determine the actual count:
					local texinfoLength = lumpStream:Tell() - startPos
					count = lumpLength / texinfoLength
					if count % 1 ~= 0 then
						print("The LUMP_TEXINFO does not end at the end of a texinfo_t! Unsupported lump format?")
					end
					count = math.floor(count)
				end
				i = i + 1
			end
		end
		
		return texinfosFields
	end,
	
	getPresentEntityClasses = function(self, fromDst)
		-- Return a sorted table of present entity classes and a table with counts (nil for internal entities)
		-- Note: existing lumps with 0 elements will add the matching class as well.
		
		local string_lower = string.lower
		local tostring = tostring
		local util_KeyValuesToTable = util.KeyValuesToTable
		
		-- Inspecting the LUMP_ENTITIES:
		local entityClasses = {}
		local entityCountByClass = {}
		do
			local lumpContent = self:extractLumpAsText(false, lumpNameToLuaIndex.LUMP_ENTITIES, fromDst)
			local entitiesText = self:_explodeEntitiesText(lumpContent)
			for i = 1, #entitiesText do
				local entityKeyValues = util_KeyValuesToTable('"entities[' .. i .. ']"\x0A' .. entitiesText[i], false, false)
				if entityKeyValues then
					local classname = entityKeyValues["classname"]
					if classname ~= nil then
						classname = string_lower(tostring(classname))
						entityClasses[classname] = true
						entityCountByClass[classname] = (entityCountByClass[classname] or 0) + 1
					end
				else
					print("Could not decode the following entity description:")
					print(entityText)
				end
			end
		end
		
		-- Checking the presence of dedicated lumps (internal entities):
		do
			for classname, lumpLookup in pairs(entityClassesToLumpLookup) do
				local lumpInfo = self:_getLump(lumpLookup[1], lumpLookup[2], fromDst)
				if lumpInfo and lumpInfo.payload then
					entityClasses[classname] = true
				end
			end
		end
		
		-- Sorting the list & returning:
		do
			local entityClasses_ = {}
			for classname in pairs(entityClasses) do
				entityClasses_[#entityClasses_ + 1] = classname
			end
			table.sort(entityClasses_)
			entityClasses = entityClasses_
		end
		return entityClasses, entityCountByClass
	end,
	
	_explodeEntitiesText = function(cls, lumpContent, posStart) -- static method
		-- Explode a text following the LUMP_ENTITIES format
		
		local string_find = string.find
		local entitiesText = {}
		posStart = posStart or 1
		local posStart_, posEnd, entityText
		repeat
			posStart_, posEnd, entityText = string_find(lumpContent, "^({\x0A.-\x0A}\x0A)", posStart)
			if not posStart_ then
				-- retry with an empty entity keyvalues set:
				posStart_, posEnd, entityText = string_find(lumpContent, "^({\x0A}\x0A)", posStart)
			end
			entitiesText[#entitiesText + 1] = entityText
			posStart = (posEnd or -1) + 1
		until not posEnd
		return entitiesText
	end,
	
	moveEntitiesToLua = function(self)
		-- Move the content of the LUMP_ENTITIES into a lua/autorun/server/ script
		
		local ipairs = ipairs
		local string_sub = string.sub
		local util_KeyValuesToTablePreserveOrder = util.KeyValuesToTablePreserveOrder
		local hook_Run = hook.Run
		local table_remove = table.remove
		local string_lower = string.lower
		local lumpContent = self:extractLumpAsText(false, lumpNameToLuaIndex.LUMP_ENTITIES, true)
		local mapInfo = self:getInfoMap()
		local mapTitle = mapInfo.title
		local entitiesText = self:_explodeEntitiesText(lumpContent)
		
		-- local presentClassNames = {}
		-- local presentClassNamesNoModel = {}
		local classNamesInLua = {}
		local classNamesInLump = {}
		local entitiesTextKeptInLump = {}
		local targetnamesToEntityIndexes = {} -- indexes from entitiesText
		local entityIndexesToParentname = {} -- indexes from entitiesText
		local targetnamesWithChildren = {} -- useless because single loop design
		local entitiesTextLua = {
			[[-- Generated by Momo's Map Manipulation Tool]],
			[[]],
			[[local mapName = %mapName%]],
			[[if string.lower( game.GetMap() ) == string.lower( mapName ) then]],
			[[	local ents_Create = ents.Create]],
			[[	local IsValid = IsValid]],
			[[	local Entity = FindMetaTable( "Entity" )]],
			[[	local ent_SetKeyValue = Entity.SetKeyValue]],
			[[	local ent_Spawn = Entity.Spawn]],
			[[	local ent_Activate = Entity.Activate]],
			[[	]],
			[[	local entitiesByMap = {}]],
			[[	local inLumpCreatedByMap = Entity.CreatedByMap]],
			[[	do]],
			[[		function Entity:CreatedByMap( ... )]],
			[[			return entitiesByMap[self] or inLumpCreatedByMap( self, ... )]],
			[[		end]],
			[[	end]],
			[[	local entityToNewMapCreationId = {}]],
			[[	do]],
			[[		local old_MapCreationID = Entity.MapCreationID]],
			[[		function Entity:MapCreationID( ... )]],
			[[			return entityToNewMapCreationId[self] or old_MapCreationID( self, ... )]],
			[[		end]],
			[[	end]],
			[[	local newMapCreationIdToEntity = {}]],
			[[	local inLumpGetMapCreatedEntity = ents.GetMapCreatedEntity]],
			[[	function ents.GetMapCreatedEntity( id, ... )]],
			[[		local ent = newMapCreationIdToEntity[id] ]],
			[[		if IsValid( ent ) then]],
			[[			return ent]],
			[[		else]],
			[[			return inLumpGetMapCreatedEntity( id, ... )]],
			[[		end]],
			[[	end]],
			[[	local entityToHammerid = {}]],
			[[	local hammeridToEntity = {}]],
			[[	local noPhysgunEntities = {}]], -- entities that have "gmod_allowphysgun" = "0"
			[[	]],
			[[	local WEAK_KEYS = {__mode = "k"}]],
			[[	local WEAK_VALUES = {__mode = "v"}]],
			[[	]],
			[[	local function InitPostEntity()]],
			[[		local entities = {}]], -- because there's a limit of 200 local variables
			[[		local ent]],
			[[		entitiesByMap = setmetatable( {}, WEAK_KEYS )]],
			[[		entityToHammerid = setmetatable( {}, WEAK_KEYS )]],
			[[		hammeridToEntity = setmetatable( {}, WEAK_VALUES )]],
			[[		entityToNewMapCreationId = setmetatable( {}, WEAK_KEYS )]],
			[[		newMapCreationIdToEntity = setmetatable( {}, WEAK_VALUES )]],
			[[		noPhysgunEntities = setmetatable( {}, WEAK_KEYS )]],
			[[		]],
					-- List all in-lump entities:
			[[		do]],
			[[			local inLumpEntities = ents.GetAll()]], -- may contain Lua-created entities (hook order)!
			[[			for i = 1, #inLumpEntities do]],
			[[				ent = inLumpEntities[i] ]],
			[[				if inLumpCreatedByMap( ent ) then]],
			[[					local hammerid = tonumber( ent:GetKeyValues()["hammerid"] )]],
			[[					if hammerid and hammerid > 0 then]],
			[[						entitiesByMap[ent] = true]],
			[[						entityToHammerid[ent] = hammerid]],
			[[						hammeridToEntity[hammerid] = ent]],
			[[					end]],
			[[				end]],
			[[			end]],
			[[		end]],
		}
		local targetnamesAsTemplates = {}
		local entitiesInfo = {}
		for i = 1, #entitiesText do
			local entityText = entitiesText[i]
			
			-- Determine basic entity information:
			local classname
			local hammerid
			local targetname
			local model = nil
			-- There is a mandatory non-empty structure name, using the same identifer as in the Lua file.
			local entityKeyValues = util_KeyValuesToTablePreserveOrder('"entities[' .. i .. ']"\x0A' .. entityText, false, true)
			entityKeyValues = keyValuesIntoStringValues(entityKeyValues)
			if entityKeyValues and #entityKeyValues ~= 0 then
				for j = #entityKeyValues, 1, -1 do
					local keyValue = entityKeyValues[j]
					local key = string_lower(keyValue.Key)
					local value = keyValue.Value
					if key == "classname" then
						classname = value
					elseif key == "hammerid" then
						hammerid = tonumber(value) -- security
					elseif key == "model" then
						model = value
					elseif key == "targetname" then
						targetname = value
						local entityIndexes = targetnamesToEntityIndexes[targetname]
						if not entityIndexes then
							entityIndexes = {}
							targetnamesToEntityIndexes[targetname] = entityIndexes
						end
						entityIndexes[#entityIndexes + 1] = i
					elseif key == "parentname" then
						entityIndexesToParentname[i] = value
						targetnamesWithChildren[value] = true
					else
						if classname == "point_template" then
							-- point_template's must exclude from Lua the entities they refer to.
							if string_sub(key, 1, 8) == "template" then
								targetnamesAsTemplates[value] = true
							end
						end
					end
				end
			else
				print("Could not decode the following entity description:")
				print(entityText)
			end
			entitiesInfo[#entitiesInfo + 1] = { -- same indexes as entitiesText
				entityText = entityText,
				classname = classname,
				hammerid = hammerid,
				targetname = targetname,
				model = model,
				entityKeyValues = entityKeyValues,
			}
		end
		local entitiesTextLuaSpawn = {} -- after creating everything (all entities ready)
		local newMapCreationId = 32768 -- safest choice: 1 + max of signed 16-bit
		for i = 1, #entitiesInfo do
			local entityInfo = entitiesInfo[i]
			local entityText = entityInfo.entityText
			local classname = entityInfo.classname
			local hammerid = entityInfo.hammerid
			local targetname = entityInfo.targetname
			local model = entityInfo.model
			local entityKeyValues = entityInfo.entityKeyValues
			
			--[[
			if classname then
				presentClassNames[classname] = true
				if model == nil then
					presentClassNamesNoModel[classname] = true
				end
			end
			]]
			
			-- Select the appropriate target:
			local moveToLua
			if classname == nil then
				moveToLua = false
			elseif entityClassesAvoidLua[classname] then
				moveToLua = false
			elseif targetnamesAsTemplates[targetname] then
				moveToLua = false
			elseif entityClassesForceLua[classname] then
				moveToLua = true
			elseif string_sub(classname, 1, 5) == "item_" then
				moveToLua = true
			elseif string_sub(classname, 1, 4) == "npc_" then
				moveToLua = true
			elseif string_sub(classname, 1, 7) == "weapon_" then
				moveToLua = true
			elseif not model or #model == 0 or string_sub(model, 1, 1) == "*" then
				moveToLua = false
			else
				moveToLua = true
			end
			do
				local moveToLua_ = hook_Run(
					"map_manipulation_tool:moveEntitiesToLua:moveToLua",
					mapTitle,
					classname,
					model,
					moveToLua,
					entityKeyValues,
					targetname
				)
				if moveToLua_ ~= nil then
					moveToLua = moveToLua_
				end
			end
			
			if moveToLua then
				classNamesInLua[classname] = true
			else
				classNamesInLump[classname] = true
			end
			
			-- Insert the entity into the appropriate target:
			local respawned = false
			if moveToLua then
				newMapCreationId = newMapCreationId - 1
				entitiesTextLua[#entitiesTextLua + 1] = [[		]]
				entitiesTextLua[#entitiesTextLua + 1] = [[		ent = ents_Create( ]] .. stringToLuaString(classname) .. [[ )]]
				entitiesTextLua[#entitiesTextLua + 1] = [[		if IsValid( ent ) then]]
				entitiesTextLua[#entitiesTextLua + 1] = [[			entities[]] .. i .. [[] = ent]]
				entitiesTextLua[#entitiesTextLua + 1] = [[			entitiesByMap[ent] = true]]
				entitiesTextLua[#entitiesTextLua + 1] = [[			entityToNewMapCreationId[ent] = ]] .. newMapCreationId
				entitiesTextLua[#entitiesTextLua + 1] = [[			newMapCreationIdToEntity[]] .. newMapCreationId .. [[] = ent]]
				for j = 1, #entityKeyValues do
					local keyValue = entityKeyValues[j]
					local key = keyValue.Key
					local keyLower = string_lower(key)
					if not entityKeyValuesNotInLua[keyLower] then
						local value = keyValue.Value
						entitiesTextLua[#entitiesTextLua + 1] = [[			ent_SetKeyValue( ent, ]] .. stringToLuaString(key) .. [[, ]] .. stringToLuaString(value) .. [[ )]]
						if keyLower == "hammerid" then
							-- Using the hammerid variable because it is a number.
							entitiesTextLua[#entitiesTextLua + 1] = [[			entityToHammerid[ent] = ]] .. hammerid
							entitiesTextLua[#entitiesTextLua + 1] = [[			hammeridToEntity[]] .. hammerid .. [[] = ent]]
						elseif keyLower == "gmod_allowphysgun" then
							-- This keyvalue actually does not exist in entities, so it has no effect outside of the LUMP_ENTITIES.
							if value == "0" then
								entitiesTextLua[#entitiesTextLua + 1] = [[			noPhysgunEntities[ent] = true]]
							end
						end
					end
				end
				entitiesTextLua[#entitiesTextLua + 1] = [[		end]]
				respawned = true
			else
				entitiesTextKeptInLump[#entitiesTextKeptInLump + 1] = entityText
				if hammerid ~= nil then -- only way to uniquely identify a map-created entity
					entitiesTextLua[#entitiesTextLua + 1] = [[		]]
					entitiesTextLua[#entitiesTextLua + 1] = [[		ent = hammeridToEntity[]] .. hammerid .. [[] ]]
					entitiesTextLua[#entitiesTextLua + 1] = [[		if IsValid( ent ) then]]
					entitiesTextLua[#entitiesTextLua + 1] = [[			-- classname: ]] .. (classname and ('"' .. classname .. '"') or tostring(classname))
					entitiesTextLua[#entitiesTextLua + 1] = [[			-- targetname: ]] .. (targetname and ('"' .. targetname .. '"') or tostring(targetname))
					entitiesTextLua[#entitiesTextLua + 1] = [[			entities[]] .. i .. [[] = ent]]
					entitiesTextLua[#entitiesTextLua + 1] = [[		end]]
					if classname == nil then
						respawned = false
					elseif targetnamesAsTemplates[targetname] then
						respawned = false
					elseif entityClassesAvoidRespawn[classname] then
						respawned = false
					elseif entityClassesForceRespawn[classname] then
						respawned = true
					elseif string_sub(classname, 1, 7) == "filter_" then
						respawned = true
					elseif string_sub(classname, 1, 5) == "func_" then
						respawned = true
					elseif string_sub(classname, 1, 6) == "logic_" then
						respawned = true
					else
						respawned = false
					end
					do
						local respawned_ = hook_Run(
							"map_manipulation_tool:moveEntitiesToLua:respawned",
							mapTitle,
							classname,
							targetname,
							respawned,
							entityKeyValues
						)
						if respawned_ ~= nil then
							respawned = respawned_
						end
					end
				end
			end
			
			-- Insert entities to Spawn():
			if respawned then
				entitiesTextLuaSpawn[#entitiesTextLuaSpawn + 1] = [[		]]
				entitiesTextLuaSpawn[#entitiesTextLuaSpawn + 1] = [[		if entities[]] .. i .. [[] then]]
				entitiesTextLuaSpawn[#entitiesTextLuaSpawn + 1] = [[			ent_Spawn( entities[]] .. i .. [[] )]]
				entitiesTextLuaSpawn[#entitiesTextLuaSpawn + 1] = [[			ent_Activate( entities[]] .. i .. [[] )]]
				entitiesTextLuaSpawn[#entitiesTextLuaSpawn + 1] = [[		end]]
			end
		end
		
		-- Show present entity classes:
		do
			--[[
			local presentClassNamesWithoutModel = {}
			local presentClassNamesWithModel = {}
			for classname in pairs(presentClassNames) do
				if presentClassNamesNoModel[classname] then
					presentClassNamesWithoutModel[#presentClassNamesWithoutModel + 1] = classname
				else
					presentClassNamesWithModel[#presentClassNamesWithModel + 1] = classname
				end
			end
			presentClassNames = nil
			table.sort(presentClassNamesWithoutModel)
			print("Present class names without model:")
			for i = 1, #presentClassNamesWithoutModel do
				print("-", presentClassNamesWithoutModel[i])
			end
			table.sort(presentClassNamesWithModel)
			print("Present class names with model:")
			for i = 1, #presentClassNamesWithModel do
				print("-", presentClassNamesWithModel[i])
			end
			]]
			local classNamesInLua_ = {}
			for classname in pairs(classNamesInLua) do
				classNamesInLua_[#classNamesInLua_ + 1] = classname
			end
			table.sort(classNamesInLua_)
			print("Present class names in Lua:")
			for i = 1, #classNamesInLua_ do
				print("-", classNamesInLua_[i])
			end
			
			local classNamesInLump_ = {}
			for classname in pairs(classNamesInLump) do
				classNamesInLump_[#classNamesInLump_ + 1] = classname
			end
			table.sort(classNamesInLump_)
			print("Present class names in LUMP_ENTITIES:")
			for i = 1, #classNamesInLump_ do
				print("-", classNamesInLump_[i])
			end
		end
		
		-- Append entity hierarchy to entitiesTextLua:
		for i = 1, #entitiesText do
			-- This also includes in-lump entities that could have their parent already set, but it does not hurt to set it again.
			local parentname = entityIndexesToParentname[i]
			if parentname and #parentname ~= 0 then -- has declared parent
				local parentsIndexes = targetnamesToEntityIndexes[parentname]
				if parentsIndexes and #parentsIndexes ~= 0 then -- parents exist
					local parentIndex = parentsIndexes[1]
					if #parentsIndexes > 1 then
						print('entities[' .. i .. '] has several parent candidates (duplicate targetname = "' .. parentname .. '"), 1st candidate has been used!')
					end
					entitiesTextLua[#entitiesTextLua + 1] = [[		]]
					entitiesTextLua[#entitiesTextLua + 1] = [[		if entities[]] .. i .. [[] and entities[]] .. parentIndex .. [[] then]]
					entitiesTextLua[#entitiesTextLua + 1] = [[			entities[]] .. i .. [[]:SetParent( entities[]] .. parentIndex .. [[] )]]
					entitiesTextLua[#entitiesTextLua + 1] = [[		end]]
				end
			end
		end
		
		-- Append entitiesTextLuaSpawn to entitiesTextLua:
		entitiesTextLua[#entitiesTextLua + 1] = [[		]]
		entitiesTextLua[#entitiesTextLua + 1] = [[		-- No loop so .mdmp shows Lua stack trace for specific problematic call!]]
		for j = 1, #entitiesTextLuaSpawn do
			entitiesTextLua[#entitiesTextLua + 1] = entitiesTextLuaSpawn[j]
		end
		
		-- Finish the Lua file:
		entitiesTextLua[#entitiesTextLua + 1] = [[	end]]
		entitiesTextLua[#entitiesTextLua + 1] = [[	local hookName = "map_manipulation_tool:" .. mapName]]
		entitiesTextLua[#entitiesTextLua + 1] = [[	hook.Add( "InitPostEntity", hookName, InitPostEntity )]]
		entitiesTextLua[#entitiesTextLua + 1] = [[	hook.Add( "PostCleanupMap", hookName, InitPostEntity )]]
		entitiesTextLua[#entitiesTextLua + 1] = [[	hook.Add( "PhysgunPickup", hookName, function( _, ent )]]
		entitiesTextLua[#entitiesTextLua + 1] = [[		if noPhysgunEntities[ent] then]]
		entitiesTextLua[#entitiesTextLua + 1] = [[			return false]]
		entitiesTextLua[#entitiesTextLua + 1] = [[		end]]
		entitiesTextLua[#entitiesTextLua + 1] = [[	end )]]
		entitiesTextLua[#entitiesTextLua + 1] = [[end]]
		entitiesTextLua[#entitiesTextLua + 1] = [[]]
		
		self.entitiesTextLua = table.concat(entitiesTextLua, "\n")
		self:setupLumpFromText(false, lumpNameToLuaIndex.LUMP_ENTITIES, table.concat(entitiesTextKeptInLump))
	end,
	
	removeEntitiesByClass = function(self, classname, fromDst)
		-- Remove entities by classname
		-- classname: case-insensitive classname whose entities are to remove
		
		local string_lower = string.lower
		local tostring = tostring
		local util_KeyValuesToTable = util.KeyValuesToTable
		
		classname = string_lower(classname)
		do
			-- In case there is a dedicated lump for this entity class:
			local lumpLookup = entityClassesToLumpLookup[classname]
			if lumpLookup then
				local lumpInfoDst = self:_getLump(lumpLookup[1], lumpLookup[2], true)
				if lumpInfoDst and lumpInfoDst.payload then
					-- Removing the lump, only if it still exists in the destination:
					self:clearLump(lumpLookup[1], lumpLookup[2])
				end
			end
		end
		
		do
			-- Removing occurrences from the LUMP_ENTITIES:
			local anyRemoved = false
			local entitiesTextKeptInLump = {}
			local lumpContent = self:extractLumpAsText(false, lumpNameToLuaIndex.LUMP_ENTITIES, fromDst)
			local entitiesText = self:_explodeEntitiesText(lumpContent)
			for i = 1, #entitiesText do
				local toKeep = true
				local entityText = entitiesText[i]
				local entityKeyValues = util_KeyValuesToTable('"entities[' .. i .. ']"\x0A' .. entitiesText[i], false, false)
				if entityKeyValues then
					local classname_ = entityKeyValues["classname"]
					if classname_ ~= nil then
						classname_ = string_lower(tostring(classname_))
						if classname_ == classname then
							toKeep = false
							anyRemoved = true
						end
					end
				else
					print("Could not decode the following entity description:")
					print(entityText)
				end
				if toKeep then
					entitiesTextKeptInLump[#entitiesTextKeptInLump + 1] = entityText
				end
			end
			if anyRemoved then
				self:setupLumpFromText(false, lumpNameToLuaIndex.LUMP_ENTITIES, table.concat(entitiesTextKeptInLump))
			end
		end
	end,
	
	getLastHammerid_ = function(cls, entitiesText) -- static method
		local lastHammerid = 0
		for hammerid in string.gmatch(entitiesText, '\x0A[%s]*"hammerid"[%s]+"([0-9]+)"[%s]*\x0A') do
			hammerid = tonumber(hammerid)
			lastHammerid = (hammerid > lastHammerid) and hammerid or lastHammerid
		end
		return lastHammerid
	end,
	
	getLastHammerid = function(self, fromDst)
		local entitiesText = self:extractLumpAsText(false, lumpNameToLuaIndex.LUMP_ENTITIES, fromDst)
		return self:getLastHammerid_(entitiesText)
	end,
	
	convertStaticPropsToDynamic = function(self, fromDst)
		-- Convert all prop_static's to prop_dynamic's
		local string_format = string.format
		
		local entitiesText = self:extractLumpAsText(false, lumpNameToLuaIndex.LUMP_ENTITIES, fromDst)
		local staticPropsKeyValues = self:getStaticPropsList(fromDst)
		local extraTextLines = {}
		local hammerid = self:getLastHammerid_(entitiesText)
		for i, propKeyValues in ipairs(staticPropsKeyValues) do
			extraTextLines[#extraTextLines + 1] = [[{]]
			extraTextLines[#extraTextLines + 1] = [["classname" "prop_dynamic"]]
			extraTextLines[#extraTextLines + 1] = [["gmod_allowphysgun" "0"]]
			hammerid = hammerid + 1
			extraTextLines[#extraTextLines + 1] = string_format('"hammerid" "%u"', hammerid)
			for _, key in ipairs(staticPropsKeyValuesOrder) do
				if staticPropsToDynamicKeyValues[key] then
					local value = propKeyValues[key]
					if value ~= nil then
						extraTextLines[#extraTextLines + 1] = string_format('%s %s', anyToKeyValueString(key), anyToKeyValueString(value))
					end
				end
			end
			extraTextLines[#extraTextLines + 1] = [[}]]
		end
		extraTextLines[#extraTextLines + 1] = [[]] -- empty line
		entitiesText = table.concat({entitiesText, table.concat(extraTextLines, "\x0A")})
		self:setupLumpFromText(false, lumpNameToLuaIndex.LUMP_ENTITIES, entitiesText)
		self:clearLump(true, getLumpIdFromLumpName("sprp"))
	end,
	
	removeHdr = function(self, fromDst)
		-- Remove the High Dynamic Range lighting from the map
		
		local lumpInfoLightingClassic = self:_getLump(false, lumpNameToLuaIndex.LUMP_LIGHTING, fromDst)
		local lumpInfoLightingHdr = self:_getLump(false, lumpNameToLuaIndex.LUMP_LIGHTING_HDR, fromDst)
		local lumpInfoWorldLightsClassic = self:_getLump(false, lumpNameToLuaIndex.LUMP_WORLDLIGHTS, fromDst)
		local lumpInfoWorldLightsHdr = self:_getLump(false, lumpNameToLuaIndex.LUMP_WORLDLIGHTS_HDR, fromDst)
		if lumpInfoLightingClassic.payload then
			-- The map comes with non-HDR lighting:
			self:clearLump(false, lumpNameToLuaIndex.LUMP_LIGHTING_HDR)
		elseif lumpInfoLightingHdr.payload then
			-- The map comes only with HDR lighting:
			print("Removing HDR: the map comes only with HDR lighting, expect weird look and possibly client crashes!")
			self:_setDstLump(false, lumpNameToLuaIndex.LUMP_LIGHTING, lumpInfoLightingHdr)
			self:clearLump(false, lumpNameToLuaIndex.LUMP_LIGHTING_HDR)
			if not lumpInfoWorldLightsClassic.payload then
				-- Copy HDR world lights into classic world lights if missing:
				self:_setDstLump(false, lumpNameToLuaIndex.LUMP_WORLDLIGHTS, lumpInfoWorldLightsHdr)
			end
		end
	end,
	
	_closeOldLumpStream = function(self, lumpInfoOld)
		-- Close the input stream of the given lumpInfoOld
		-- Must be called if a lump payload is going to be discarded
		local streamSrc
		if lumpInfoOld and lumpInfoOld.payload then
			streamSrc = lumpInfoOld.payload.streamSrc
			if streamSrc == self.streamSrc then
				-- If the stream is the loaded map file, it is not to be closed.
				streamSrc = nil
			end
		end
		if streamSrc then
			streamSrc:Close()
		end
	end,
	
	_closeAllLumpStreams = function(self)
		-- Close the input stream of every lump payload
		-- Must be called if every modified lump is going to be discarded
		if self.lumpsDst ~= nil then
			for i, lumpInfoOld in ipairs(self.lumpsDst) do
				self:_closeOldLumpStream(lumpInfoOld)
			end
		end
		if self.gameLumpsDst ~= nil then
			for i, lumpInfoOld in ipairs(self.gameLumpsDst) do
				self:_closeOldLumpStream(lumpInfoOld)
			end
		end
	end,
	
	close = function(self)
		-- This function must be called to properly close files.
		
		self:_closeAllLumpStreams()
		self.streamSrc:Close()
		
		-- Full memory cleanup:
		local keys = {}
		for k in pairs(self) do
			keys[#keys + 1] = k
		end
		for i = 1, #keys do
			self[keys[i]] = nil
		end
		collectgarbage()
	end,
	
	getInfoMap = function(self)
		local _, _, title = string.find(self.filenameSrc, "([^\\/]+)$")
		if title then
			if string.lower(string.sub(title, -4, -1)) == ".dat" then
				title = string.lower(string.sub(title, 1, -5))
			end
		end
		if title then
			if string.lower(string.sub(title, -4, -1)) == ".bsp" then
				title = string.lower(string.sub(title, 1, -5))
			end
		end
		return {
			size = self.streamSrc:Size(),
			version = self.bspHeader.version,
			mapRevision = self.bspHeader.mapRevision,
			bigEndian = (self.data_to_integer == data_to_be),
			title = title,
		}
	end,
	
	_addLumpInfoToList = function(self, lumpInfoSrc, lumpInfoDst, isGameLump, id, toCompress, allLumps)
		-- id: index in lumpsSrc & lumpsDst, unused for game lumps
		
		local sizeBefore = (lumpInfoSrc and lumpInfoSrc.filelen or -1)
		local modified = false
		if not isGameLump and id == lumpNameToLuaIndex.LUMP_GAME_LUMP then
			for i = 1, math.max(#self.gameLumpsSrc, #self.gameLumpsDst) do
				if self.gameLumpsSrc[i] ~= self.gameLumpsDst[i] then
					modified = true
					break
				end
			end
		else
			modified = (lumpInfoDst ~= lumpInfoSrc)
		end
		local sizeAfter = (lumpInfoDst and lumpInfoDst.filelen or -1) -- probably wrong if compression is to do
		local gameLumpId
		if isGameLump then
			gameLumpId = (lumpInfoSrc and lumpInfoSrc.id or lumpInfoDst and lumpInfoDst.id or -1)
		end
		local compressedAfter = false -- unsafe: determined by code copied from self:writeNewBsp_()
		if isGameLump or id == lumpNameToLuaIndex.LUMP_GAME_LUMP then
			-- Because I decided it is common to all game lumps:
			local lumpGameLumpToCompress = self.lumpIndexesToCompress[lumpNameToLuaIndex.LUMP_GAME_LUMP]
			if lumpGameLumpToCompress == nil then
				compressedAfter = self:anyCompressedInGameLumps(self.gameLumpsDst)
			else
				compressedAfter = lumpGameLumpToCompress
			end
		else
			if toCompress == nil then
				if lumpInfoDst and lumpInfoDst.payload then
					compressedAfter = lumpInfoDst.payload.compressed or false
				end
			else
				compressedAfter = toCompress
			end
		end
		
		local info = {
			isGameLump = isGameLump,
			luaId = isGameLump and gameLumpId or id,
			id = isGameLump and (-1) or (id - 1),
			name = isGameLump and int32_to_be_data(gameLumpId) or lumpLuaIndexToName[id],
			version = lumpInfoSrc and lumpInfoSrc.version or lumpInfoDst and lumpInfoDst.version or -1,
			sizeBefore = sizeBefore,
			compressedBefore = lumpInfoSrc and lumpInfoSrc.payload and lumpInfoSrc.payload.compressed or false,
			absent = ((sizeBefore == -1 or sizeBefore == 0) and (sizeAfter == -1 or sizeAfter == 0)),
			modified = modified,
			deleted = (modified and sizeAfter <= 0),
			sizeAfter = sizeAfter,
			compressedAfter = compressedAfter,
		}
		if allLumps ~= nil then
			allLumps[#allLumps + 1] = info
		end
		
		return info
	end,
	
	getInfoLumps = function(self, includeAbsent, only1, only1IsGameLump, only1Id)
		-- Returns readable information about all lumps (for UI)
		-- includeAbsent: also include lumps that are not present in the map
		-- only1: only return allLumps with 1 value, matching only1IsGameLump, only1Id
		
		local allLumps = {}
		
		local LUMP_ID_GAME_LUMP = lumpNameToLuaIndex["LUMP_GAME_LUMP"]
		if only1 then
			includeAbsent = true
		end
		for i = 1, #self.lumpsSrc do
			local toCompress = self.lumpIndexesToCompress[i] -- true / false / nil
			
			-- Add lumps:
			if not only1 or (not only1IsGameLump and i == only1Id) then
				local lumpSrc = self.lumpsSrc[i]
				local lumpDst = self.lumpsDst[i]
				if includeAbsent or (lumpSrc and lumpSrc.payload) or (lumpDst and lumpDst.payload) then
					self:_addLumpInfoToList(self.lumpsSrc[i], self.lumpsDst[i], false, i, toCompress, allLumps)
				end
			end
			
			-- Add game lumps:
			if i == LUMP_ID_GAME_LUMP then
				local gameLumpIdsInSrc = {}
				for j = 1, #self.gameLumpsSrc do
					-- Locate the game lump with same id in self.gameLumpsDst:
					local gameLumpSrc = self.gameLumpsSrc[j]
					local gameLumpDst
					local id = gameLumpSrc.id
					if not only1 or (only1IsGameLump and id == only1Id) then
						for k = 1, #self.gameLumpsDst do
							if self.gameLumpsDst[k].id == id then
								gameLumpDst = self.gameLumpsDst[k]
								break
							end
						end
						-- Add a game lump when present in self.gameLumpsSrc:
						self:_addLumpInfoToList(gameLumpSrc, gameLumpDst, true, j, toCompress, allLumps)
					end
					gameLumpIdsInSrc[id] = true
				end
				for j = 1, #self.gameLumpsDst do
					local gameLumpDst = self.gameLumpsDst[j]
					local id = gameLumpDst.id
					if not gameLumpIdsInSrc[id] then
						if not only1 or (only1IsGameLump and id == only1Id) then
							-- Add a game lump if no lump with same id in self.gameLumpsSrc:
							self:_addLumpInfoToList(nil, gameLumpDst, true, j, toCompress, allLumps)
						end
					end
				end
			end
		end
		
		return allLumps
	end,
	
	getUpdatedInfoLump = function(self, oldInfo)
		-- Returns a new info object for the given obsolete lump info object
		-- This is useful to update just a given lump after a modification on the GUI.
		return self:getInfoLumps(true, true, oldInfo.isGameLump, oldInfo.luaId)[1]
	end,
}
BspContext.__index = BspContext

-- Late instanciations:
entityClassesToLumpLookup = {
	["info_overlay"] = {false, lumpNameToLuaIndex["LUMP_OVERLAYS"]},
	["prop_detail"] = {true, getLumpIdFromLumpName("dprp")},
	["prop_static"] = {true, getLumpIdFromLumpName("sprp")},
}

-- Lua refresh hack:
for context in pairs(BspContext._instances) do
	setmetatable(context, BspContext)
	print("Refreshed BspContext", context)
end
