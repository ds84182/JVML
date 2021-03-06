--This will load class files and will register them--
natives = {["java.lang.Object"]={
	["registerNatives()V"] = function()
		local path = resolvePath("java/lang/native")
		for i,v in ipairs(fs.list(path)) do
			if v:sub(1,1) ~= "." then
				dofile(fs.combine(path, v))
			end
		end
	end
}}
os.loadAPI(fs.combine(jcd, "jvml_data/vm/bigInt"))

function asInt(d)
	return {type="I",data=d}
end
function asFloat(d)
	return {type="F",data=d}
end
function asDouble(d)
	return {type="D",data=d}
end
function asLong(d)
	return {type="J",data=d}
end
function asBoolean(d)
	if d == true or d == 0 then
		d = 0
	else
		d = 1
	end
	return {type="Z",data=d}
end
function asChar(d)
	return {type="C",data=d}
end
function asByte(d)
	return {type="B",data=d}
end
function asShort(d)
	return {type="S",data=d}
end
function asObjRef(d, type)
	return {type=type,data=d}
end

local function u2ToSignedShort(i)
	if i > 2^15 - 1 then
		return -(2^16 - i)
	end
	return i
end
local function u1ToSignedByte(i)
	if i > 2^7 - 1 then
		return -(2^8 - i)
	end
	return i
end

ARRAY_TYPES = {
	Z=4,
	C=5,
	F=6,
	D=7,
	B=8,
	S=9,
	I=10,
	J=11
}

do
	local t = {}
	for k,v in pairs(ARRAY_TYPES) do
		t[v] = k
	end
	ARRAY_TYPES = t
end

TYPELOOKUP = {
	Integer=10,
	Float=6,
	Long=11,
	Double=7
}

CONSTANT = {
	Class=7,
	Fieldref=9,
	Methodref=10,
	InterfaceMethodref=11,
	String=8,
	Integer=3,
	Float=4,
	Long=5,
	Double=6,
	NameAndType=12,
	Utf8=1,
	MethodHandle=15,
	MethodType=16,
	InvokeDynamic=18
}

local CONSTANTLOOKUP = {}
for i, v in pairs(CONSTANT) do CONSTANTLOOKUP[v] = i end

local nan = -(0/0)

METHOD_ACC = {
	PUBLIC=0x0001,
	PRIVATE=0x0002,
	PROTECTED=0x0004,
	STATIC=0x0008,
	FINAL=0x0010,
	SYNCHRONIZED=0x0020,
	BRIDGE=0x0040,
	VARARGS=0x0080,
	NATIVE=0x0100,
	ABSTRACT=0x0400,
	STRICT=0x0800,
	SYNTHETIC=0x1000,
}

CLASS_ACC = {
	PUBLIC=0x0001,
	FINAL=0x0010,
	SUPER=0x0020,
	INTERFACE=0x0200,
	ABSTRACT=0x0400,
	SYNTHETIC=0x1000,
	ANNOTATION=0x2000,
	ENUM=0x4000,
}

function loadJavaClass(file)
	if not file then error('test', 2) end
	if not fs.exists(file) then return false end
	local fh = fs.open(file,"rb")
	local cn
	local cp = {}
	local i = 0
	
	local u1 = fh.read--function() i=i+1 print("at ",i-1) return fh.read() end
	local function u2()
		return bit.blshift(u1(),8) + u1()
	end
	
	local function u4()
		return bit.blshift(u1(),24) + bit.blshift(u1(),16) + bit.blshift(u1(),8) + u1()
	end

	local function parse_descriptor(desc,descriptor)
		--parse descriptor
		local i = 1
		local cur = {}
		cur.array_depth = 0 -- not an array
		while i <= #descriptor do
			local c = descriptor:sub(i,i)
			if c == "(" or c == ")" then
				--arglst start
			else
				if c == "[" then
					cur.array_depth = cur.array_depth + 1 -- one deeper for each dimension
				elseif c == "L" then
					--im guessing ref or something
					cur.type = "L"
					i = i+1
					c = descriptor:sub(i,i)
					while c ~= ";" and c do
						cur.type = cur.type..c
						i = i+1
						c = descriptor:sub(i,i)
					end
					table.insert(desc,cur)
					cur = {}
				else
					cur.type = c
					table.insert(desc,cur)
					cur = {}
				end
			end
			i = i+1
		end
	end
	
	local function cp_class_info(c)
		c.name_index = u2() --name index
	end
	
	local function cp_ref_info(c)
		c.class_index = u2()
		c.name_and_type_index = u2()
	end
	
	local function cp_string_info(c)
		c.string_index= u2()
	end
	
	local function cp_intfloat_info(c)
		c.bytes = u4()
	end
	
	local function cp_longdouble_info(c)
		c.high_bytes = u4()
		c.low_bytes = u4()
	end
	
	local function cp_nameandtype_info(c)
		c.name_index = u2()
		c.descriptor_index = u2()
	end
	
	local function cp_utf8_info(c)
		c.length = u2()
		c.bytes = ""
		for i=1, c.length do
			c.bytes = c.bytes..string.char(u1()) --UTF8? Fuck that!
		end
	end
	
	local function cp_methodhandle_info(c)
		c.reference_kind = u1()
		c.reference_index = u2()
	end
	
	local function cp_methodtype_info(c)
		c.descriptor_index = u2()
	end
	
	local function cp_invokedynamic_info(c)
		c.bootstrap_method_attr_index = u2()
		c.name_and_type_index = u2()
	end
	
	local function parse_float(bits)
		if bits == 0x7f800000 then
			return math.huge
		elseif bits == 0xff800000 then
			return -math.huge
		elseif bits >= 0x7f800001 and bits <= 0x7fffffff and bits >= 0xff800001 and bits <= 0xffffffff then
			return nan
		else
			local s = (bit.brshift(bits, 31) == 0) and 1 or -1;
			local e = bit.band(bit.brshift(bits, 23), 0xff);
			local m = (e == 0) and
					  bit.blshift(bit.band(bits, 0x7fffff), 1) or
					  bit.band(bits, 0x7fffff) + 0x800000
			return s*m*(2^(e-150))
		end
	end
	
	local function parse_long(high_bytes,low_bytes)
		return bigInt.add(bigInt.brshift(high_bytes,32),low_bytes)
	end
	
	local function parse_double(high_bytes,low_bytes)
		local x = ""
		x = x..string.char(bit.band(low_bytes,0xFF))
		x = x..string.char(bit.band(bit.brshift(low_bytes,8),0xFF))
		x = x..string.char(bit.band(bit.brshift(low_bytes,16),0xFF))
		x = x..string.char(bit.band(bit.brshift(low_bytes,24),0xFF))
		
		x = x..string.char(bit.band(high_bytes,0xFF))
		x = x..string.char(bit.band(bit.brshift(high_bytes,8),0xFF))
		x = x..string.char(bit.band(bit.brshift(high_bytes,16),0xFF))
		x = x..string.char(bit.band(bit.brshift(high_bytes,24),0xFF))
		--x = string.reverse(x)
		local sign = 1
		local mantissa = string.byte(x, 7) % 16
		for i = 6, 1, -1 do mantissa = mantissa * 256 + string.byte(x, i) end
		if string.byte(x, 8) > 127 then sign = -1 end
		local exponent = (string.byte(x, 8) % 128) * 16 +math.floor(string.byte(x, 7) / 16)
		if exponent == 0 then return 0 end
		mantissa = (math.ldexp(mantissa, -52) + 1) * sign
		return math.ldexp(mantissa, exponent - 1023)
	end
	
	local function cp_entry(ei)
		local c = {}
		c.tag = u1()
		c.cl = ARRAY_TYPES[TYPELOOKUP[CONSTANTLOOKUP[c.tag]]] or CONSTANTLOOKUP[c.tag]
		local ct = c.tag
		if ct == CONSTANT.Class then
			cp_class_info(c)
		elseif ct == CONSTANT.Fieldref or ct == CONSTANT.Methodref or ct == CONSTANT.InterfaceMethodref then
			cp_ref_info(c)
		elseif ct == CONSTANT.String then
			cp_string_info(c)
		elseif ct == CONSTANT.Integer then
			cp_intfloat_info(c)
		elseif ct == CONSTANT.Float then
			cp_intfloat_info(c)
			c.bytes = parse_float(c.bytes)
		elseif ct == CONSTANT.Long then
			print("warning: longs are not supported")
			cp_longdouble_info(c)
			c.bytes = parse_long(c.high_bytes,c.low_bytes)
		elseif ct == CONSTANT.Double then
			cp_longdouble_info(c)
			c.bytes = parse_double(c.high_bytes,c.low_bytes)
		elseif ct == CONSTANT.NameAndType then
			cp_nameandtype_info(c)
		elseif ct == CONSTANT.Utf8 then
			cp_utf8_info(c)
		elseif ct == CONSTANT.MethodHandle then
			cp_methodhandle_info(c)
		elseif ct == CONSTANT.MethodType then
			cp_methodtype_info(c)
		elseif ct == CONSTANT.InvokeDynamic then
			cp_invokedynamic_info(c)
		else
			print("Mindfuck in ConstantPool: "..ct)
		end
		return c
	end
	
	local function attribute()
		local attrib = {}
		attrib.attribute_name_index = u2()
		attrib.attribute_length = u4()
		attrib.name = cp[attrib.attribute_name_index].bytes
		local an = attrib.name
		if an == "ConstantValue" then
			attrib.constantvalue_index = u2()
		elseif an == "Code" then
			attrib.max_stack = u2()
			attrib.max_locals = u2()
			attrib.code_length = u4()
			attrib.code = {}
			for i=0, attrib.code_length-1 do
				attrib.code[i] = u1()
			end
			attrib.exception_table_length = u2()
			attrib.exception_table = {}
			for i=0, attrib.exception_table_length-1 do
				attrib.exception_table[i] = {
					start_pc = u2(),
					end_pc = u2(),
					handler_pc = u2(),
					catch_type = u2()
				}
			end
			attrib.attributes_count = u2()
			attrib.attributes = {}
			for i=0, attrib.attributes_count-1 do
				attrib.attributes[i] = attribute()
			end
		elseif an == "Exceptions" then
			attrib.number_of_exceptions = u2()
			attrib.exception_index_table = {}
			for i=0, attrib.number_of_exceptions-1 do
				attrib.exception_index_table[i] = u2()
			end
		elseif an == "InnerClasses" then
			attrib.number_of_classes = u2()
			attrib.classes = {}
			for i=0, attrib.number_of_classes-1 do
				attrib.classes[i] = {
					inner_class_info_index = u2(),
					outer_class_info_index = u2(),
					inner_name_index = u2(),
					inner_class_access_flags = u2()
				}
			end
		elseif an == "EnclosingMethod" then
			attrib.class_index = u2()
			attrib.method_index = u2()
		elseif an == "Synthetic" then
			error("Fuck that, Synthetic attributes are not supported",0)
		elseif an == "Signature" then
			attrib.signature_index = u2()
		elseif an == "SourceDebugExtension" then
			error("SourceDebugExtension? LELHUEHUEHUELELELELELHUE",0)
		elseif an == "LineNumberTable" then
			attrib.line_number_table_length = u2()
			attrib.line_number_table = {}
			for i=0, attrib.line_number_table_length-1 do
				attrib.line_number_table[i] = {
					start_pc = u2(),
					line_number = u2()
				}
			end
		elseif an == "LocalVariableTable" then
			attrib.local_variable_table_length = u2()
			attrib.local_variable_table = {}
			for i=0, attrib.local_variable_table_length-1 do
				attrib.local_variable_table[i] = {
					start_pc = u2(),
					length = u2(),
					name_index = u2(),
					descriptor_index = u2(),
					index = u2()
				}
			end
		elseif an == "LocalVariableTypeTable" then
			error("LVTT is so mainstream",0)
		elseif an == "Deprecated" then
			--lel, this doesn't have content in it--
		elseif an == "SourceFile" then
			attrib.source_file_index = u2()
		else
			--print("Unhandled Attrib: "..an)
			attrib.bytes = {}
			for i=1, attrib.attribute_length do
				attrib.bytes[i] = u1()
			end
		end
		return attrib
	end
	
	local function field_info()
		local field = {
			access_flags = u2(),
			name = cp[u2()].bytes,
			descriptor = cp[u2()].bytes,
			attributes_count = u2(),
			attributes = {}
		}
		for i=0, field.attributes_count-1 do
			field.attributes[i] = attribute()
		end
		return field
	end
	
	local function resolveClass(c)
		local cn = cp[c.name_index].bytes:gsub("/",".")
		return classByName(cn)
	end

	local function createCodeFunction(codeAttribute, name)
		local code = codeAttribute.code
		return function(...)
			local thrown

			local stack = {}
			local lvars = {}
			for i,v in ipairs({...}) do
				lvars[i - 1] = v
			end
			local sp = 1
			local function push(i)
				--print(i)
				stack[sp] = i
				sp = sp+1
			end
			local function pop()
				sp = sp-1
				return stack[sp]
			end
			local _pc = 0
			local function pc(i)
				_pc = i or _pc
				return _pc - 1
			end
			local function u1()
				return code[pc(pc() + 2)]
			end
			local function u2()
				return bit.blshift(u1(),8) + u1()
			end

			local function catchException(exc)
				local pcStartDistance
				local pcEndDistance
				local classDistance
				local closestTarget
				local p = pc()
				for i=0, codeAttribute.exception_table_length-1 do
					local v = codeAttribute.exception_table[i]
					if p >= v.start_pc and p <= v.end_pc and (not pcStartDistance or (p - v.start_pc >= pcStartDistance and v.end_pc - p >= pcEndDistance))then
						local dist = classof("L"..cp[cp[v.catch_type].name_index].bytes..";", exc.type)
						if not classDistance or dist < classDistance then
							pcStartDistance = p - v.start_pc
							pcEndDistance = v.end_pc - p
							classDistance = dist
							closestTarget = v.handler_pc
						end
					end
				end
				if closestTarget then
					pc(closestTarget)
					return true
				else
					return false
				end
			end
			local function throw(exc)
				push(exc)
				exc.data.stackTrace = getStackTrace()
				if not catchException(exc) then
					thrown = exc
					error('',0)
				end
			end
			pushStackTrace(name, throw)
			
			while true do 
				local ok, jOk, ret = pcall(function()
					if thrown then
						return false, thrown
					end
					local inst = u1()
					if inst == 0x0 then
					elseif inst == 0x1 then
						--null
						push(nil)
					elseif inst == 0x2 then
						push(asInt(-1))
					elseif inst == 0x3 then
						push(asInt(0))
					elseif inst == 0x4 then
						push(asInt(1))
					elseif inst == 0x5 then
						push(asInt(2))
					elseif inst == 0x6 then
						push(asInt(3))
					elseif inst == 0x7 then
						push(asInt(4))
					elseif inst == 0x8 then
						push(asInt(5))
					elseif inst == 0x9 then
						push(asLong(bigInt.toBigInt(0)))
					elseif inst == 0xA then
						push(asLong(bigInt.toBigInt(1)))
					elseif inst == 0xB then
						push(asFloat(0))
					elseif inst == 0xC then
						push(asFloat(1))
					elseif inst == 0xD then
						push(asFloat(2))
					elseif inst == 0xE then
						push(asDouble(0))
					elseif inst == 0xF then
						push(asDouble(1))
					elseif inst == 0x10 then
						--push imm byte
						push(asInt(u1()))
					elseif inst == 0x11 then
						--push imm short
						push(asInt(u2()))
					elseif inst == 0x12 then
						--ldc
						--push constant
						local s = cp[u1()]
						if s.bytes then
							push({type=s.cl,data=s.bytes})
						else
							push(asObjRef(cp[s.string_index].bytes, "Ljava/lang/String;"))
						end
					elseif inst == 0x13 then
						--ldc_w
						--push constant
						local s = cp[u2()]
						if s.bytes then
							push({type=s.cl:lower(),data=s.bytes})
						else
							push(asObjRef(cp[s.string_index].bytes, "Ljava/java/lang/String;"))
						end
					elseif inst == 0x14 then
						--ldc2_w
						--push constant
						local s = cp[u2()]
						push({type=s.cl:lower(),data=s.bytes})
					elseif inst >= 0x15 and inst <= 0x19 then
						--loads
						push(lvars[u1()])
					elseif inst == 0x1A or inst == 0x1E or inst == 0x22 or inst == 0x26 or inst == 0x2A then
						--load_0
						push(lvars[0])
					elseif inst == 0x1B or inst == 0x1F or inst == 0x23 or inst == 0x27 or inst == 0x2B then
						--load_1
						push(lvars[1])
					elseif inst == 0x1C or inst == 0x20 or inst == 0x24 or inst == 0x28 or inst == 0x2C then
						--load_2
						push(lvars[2])
					elseif inst == 0x1D or inst == 0x21 or inst == 0x25 or inst == 0x29 or inst == 0x2D then
						--load_3
						push(lvars[3])
					elseif inst >= 0x2E and inst <= 0x35 then
						--aaload
						local i, arr = pop(), pop()
						if i.data >= arr.data.length then
							local exc = newInstance(classByName("java.lang.ArrayIndexOutOfBoundsException"))
							local obj = asObjRef(exc, "Ljava/lang/ArrayIndexOutOfBoundsException;")
							throw(obj)
						end
						local value = arr.data[i.data]
						push(asObjRef(value, arr.type:sub(2))) -- arr.type == "[typestuff", so remove the bracket
					elseif inst >= 0x36 and inst <= 0x3A then
						--stores
						lvars[u1()] = pop()
					elseif inst == 0x3B or inst == 0x3F or inst == 0x43 or inst == 0x47 or inst == 0x4B then
						lvars[0] = pop()
					elseif inst == 0x3C or inst == 0x40 or inst == 0x44 or inst == 0x48 or inst == 0x4C then
						lvars[1] = pop()
					elseif inst == 0x3D or inst == 0x41 or inst == 0x45 or inst == 0x49 or inst == 0x4D then
						lvars[2] = pop()
					elseif inst == 0x3E or inst == 0x42 or inst == 0x46 or inst == 0x4A or inst == 0x4E then
						lvars[3] = pop()
					elseif inst >= 0x4f and inst <= 0x56 then
						--aastore
						local v,i,t = pop(),pop(),pop()
						if i.data >= t.data.length then
							local exc = newInstance(classByName("java.lang.ArrayIndexOutOfBoundsException"))
							local obj = asObjRef(exc, "Ljava/lang/ArrayIndexOutOfBoundsException;")
							throw(obj)
						end
						t.data[i.data] = v.data
					elseif inst == 0x57 then
						pop()
					elseif inst == 0x58 then
						local pv = pop()
						if pv.type ~= "D" and pv.type ~= "J" then
							pop()
						end
					elseif inst == 0x59 then
						local v = pop()
						push(v)
						push({type=v.type,data=v.data})
					elseif inst == 0x5a then
						local v = pop()
						push(v)
						table.insert(stack,sp-2,{type=v.type,data=v.data})
						sp = sp+1
					elseif inst == 0x5b then
						local v = pop()
						push(v)
						table.insert(stack,sp-(pv.type == "D" or pv.type == "J" and 2 or 3),{type=v.type,data=v.data})
						sp = sp+1
					elseif inst == 0x5c then
						local a = pop()
						if a.type ~= "D" and a.type ~= "J" then
							local b = pop()
							push(b)
							push(a)
							push({type=b.type,data=b.data})
							push({type=a.type,data=a.data})
						else
							push(a)
							push({type=a.type,data=a.data})
						end
					elseif inst == 0x5d then
						error("swap2_x1 is bullshit and you know it")
					elseif inst == 0x5e then
						error("swap2_x2 is bullshit and you know it")
					elseif inst == 0x5f then
						local a = pop()
						local b = pop()
						push(a)
						push(b)
					elseif inst >= 0x60 and inst <= 0x63 then
						--add
						local b, a = pop(), pop()
						push({type=a.type,data=a.data+b.data})
					elseif inst >= 0x64 and inst <= 0x67 then
						--sub
						local b, a = pop(), pop()
						push({type=a.type,data=a.data-b.data})
					elseif inst >= 0x68 and inst <= 0x6b then
						--mul
						local b, a = pop(), pop()
						push({type=a.type,data=a.data*b.data})
					elseif inst >= 0x6c and inst <= 0x6f then
						--div
						local b, a = pop(), pop()
						push({type=a.type,data=a.data/b.data})
					elseif inst >= 0x70 and inst <= 0x73 then
						--rem
						local b, a = pop(), pop()
						push({type=a.type,data=a.data%b.data})
					elseif inst >= 0x74 and inst <= 0x77 then
						--neg
						local a = pop(), pop()
						push({type=a.type,data=-a.data})
					elseif inst >= 0x78 and inst <= 0x79 then
						--shl
						local b, a = pop(), pop()
						push({type=b.type,data=bit.blshift(b.data,a.data)})
					elseif inst >= 0x7a and inst <= 0x7b then
						--shr
						local b, a = pop(), pop()
						push({type=b.type,data=bit.brshift(b.data,a.data)})
					elseif inst >= 0x7c and inst <= 0x7d then
						--shlr
						local b, a = pop(), pop()
						push({type=b.type,data=bit.blogic_rshift(b.data,a.data)})
					elseif inst >= 0x7e and inst <= 0x7f then
						--and
						local b, a = pop(), pop()
						push({type=a.type,data=bit.band(a.data,b.data)})
					elseif inst >= 0x80 and inst <= 0x81 then
						--or
						local b, a = pop(), pop()
						push({type=a.type,data=bit.bor(a.data,b.data)})
					elseif inst >= 0x82 and inst <= 0x83 then
						--xor
						local b, a = pop(), pop()
						push({type=a.type,data=bit.bxor(a.data,b.data)})
					elseif inst == 0x84 then
						--iinc
						local idx = u1()
						local c = u1ToSignedByte(u1())
						lvars[idx].data = lvars[idx].data+c
					elseif inst == 0x85 then
						--i2l
						push(asLong(bigInt.toBigInt(pop().data)))
					elseif inst == 0x86 then
						--i2f
						push(asFloat(pop().data))
					elseif inst == 0x87 then
						--i2d
						push(asDouble(pop().data))
					elseif inst == 0x88 then
						--l2i
						push(asInt(bigInt.fromBigInt(pop().data)))
					elseif inst == 0x89 then
						--l2f
						push(asFloat(bigInt.fromBigInt(pop().data)))
					elseif inst == 0x8A then
						--l2d
						push(asDouble(bigInt.fromBigInt(pop().data)))
					elseif inst == 0x8B then
						--f2i
						push(asInt(math.floor(pop().data)))
					elseif inst == 0x8C then
						--f2l
						push(asLong(bigInt.toBigInt(math.floor(pop().data))))
					elseif inst == 0x8D then
						--f2d
						push(asDouble(pop().data))
					elseif inst == 0x8E then
						--d2i
						push(asInt(math.floor(pop().data)))
					elseif inst == 0x8F then
						--d2l
						push(asLong(bigInt.toBigInt(math.floor(pop().data))))
					elseif inst == 0x90 then
						--d2f
						push(asFloat(pop().data))
					elseif inst == 0x91 then
						--i2b
						push(asByte(pop().data))
					elseif inst == 0x92 then
						--i2c
						push(asChar(string.char(pop().data)))
					elseif inst == 0x93 then
						--i2s
						push(asShort(pop().data))
					elseif inst == 0x94 then
						--lcmp
						local a, b = pop().data, pop().data
						if bigInt.cmp_eq(a, b) then
							push(asInt(0))
						elseif bigInt.cmp_lt(a, b) then
							push(asInt(1))
						else
							push(asInt(-1))
						end
					elseif inst >= 0x95 and inst <= 0x98 then -- Not worrying about NaN just yet...
						--fcmpl/g
						local a, b = pop().data, pop().data
						if a == b then
							push(asInt(0))
						elseif a < b then
							push(asInt(1))
						else
							push(asInt(-1))
						end
					elseif inst == 0x99 then
						--ifeq
						local offset = u2ToSignedShort(u2())
						if pop().data == 0 then
							pc(pc() + offset - 2) -- minus 2 becuase u2()
						end
					elseif inst == 0x9A then
						--ifne
						local offset = u2ToSignedShort(u2())
						if pop().data ~= 0 then
							pc(pc() + offset - 2)
						end
					elseif inst == 0x9B then
						--iflt
						local offset = u2ToSignedShort(u2())
						if pop().data < 0 then
							pc(pc() + offset - 2)
						end
					elseif inst == 0x9C then
						--ifge
						local offset = u2ToSignedShort(u2())
						if pop().data >= 0 then
							pc(pc() + offset - 2)
						end
					elseif inst == 0x9D then
						--ifgt
						local offset = u2ToSignedShort(u2())
						if pop().data > 0 then
							pc(pc() + offset - 2)
						end
					elseif inst == 0x9E or inst == 0xA5 then -- same code for both...
						--ifle
						local offset = u2ToSignedShort(u2())
						if pop().data <= 0 then
							pc(pc() + offset - 2)
						end
					elseif inst == 0x9F or inst == 0xA6 then
						--if_icmpeq
						local offset = u2ToSignedShort(u2())
						if pop().data == pop().data then
							pc(pc() + offset - 2)
						end
					elseif inst == 0xA0 then
						--if_icmpne
						local offset = u2ToSignedShort(u2())
						if pop().data ~= pop().data then
							pc(pc() + offset - 2)
						end
					elseif inst == 0xA1 then
						--if_icmplt
						local offset = u2ToSignedShort(u2())
						if pop().data > pop().data then
							pc(pc() + offset - 2)
						end
					elseif inst == 0xA2 then
						--if_icmpge
						local offset = u2ToSignedShort(u2())
						if pop().data <= pop().data then
							pc(pc() + offset - 2)
						end
					elseif inst == 0xA3 then
						--if_icmpgt
						local offset = u2ToSignedShort(u2())
						if pop().data < pop().data then
							pc(pc() + offset - 2)
						end
					elseif inst == 0xA4 then
						--if_icmple
						local offset = u2ToSignedShort(u2())
						if pop().data >= pop().data then
							pc(pc() + offset - 2)
						end
					elseif inst == 0xA7 then
						--goto
						local offset = u2ToSignedShort(u2())
						pc(pc() + offset - 2)
					elseif inst == 0xA8 then
						--jsr
						local addr = pc() + 3
						local offset = u2ToSignedShort(u2())
						push({type="address", data=addr})
						pc(pc() + offset - 2)
					elseif inst == 0xA9 then
						--ret
						local index = u1()
						local addr = lvars[index]
						if addr.type ~= "address" then
							error("Not an address", 0)
						end
						pc(addr.data)
					elseif inst >= 0xAC and inst <= 0xB0 then
						popStackTrace()
						return true, pop()
					elseif inst == 0xB1 then
						popStackTrace()
						return true
					elseif inst == 0xB2 then
						--getstatic
						local fr = cp[u2()]
						local cl = resolveClass(cp[fr.class_index])
						local name = cp[cp[fr.name_and_type_index].name_index].bytes
						local descriptor = cp[cp[fr.name_and_type_index].descriptor_index].bytes
						--print(descriptor)
						push(asObjRef(cl.fields[name].value), descriptor)
					elseif inst == 0xB3 then
						--putstatic
						local fr = cp[u2()]
						local cl = resolveClass(cp[fr.class_index])
						local name = cp[cp[fr.name_and_type_index].name_index].bytes
						cl.fields[name].value = pop().data
					elseif inst == 0xB4 then
						local fr = cp[u2()]
						local name = cp[cp[fr.name_and_type_index].name_index].bytes
						local obj = pop().data
						push(asObjRef(obj.fields[name].value, obj.fields[name].descriptor))
					elseif inst == 0xB5 then
						--putfield
						local fr = cp[u2()]
						local name = cp[cp[fr.name_and_type_index].name_index].bytes
						local value = pop().data
						local obj = pop().data
						obj.fields[name].value = value
					elseif inst == 0xB6 or inst == 0xB9 then
						--invokevirtual/interface
						local mr = cp[u2()]
						if inst == 0xB9 then u2() end -- invokeinterface has two dead bytes in the instruction
						local cl = resolveClass(cp[mr.class_index])
						local name = cp[cp[mr.name_and_type_index].name_index].bytes..cp[cp[mr.name_and_type_index].descriptor_index].bytes
						local mt = findMethod(cl,name)
						local args = {}
						for i=#mt.desc-1,1,-1 do
							args[i+1] = pop()
						end
						args[1] = pop()
						local obj = args[1].data
						if type(obj) == "table" and obj.class then -- if the object holds its own methods, use those so A a = new B(); a.c() calls B.c(), not A.c()
							mt = findMethod(obj.class, name)
						end
						local status, ret = mt[1](unpack(args))
						if mt.desc[#mt.desc].type ~= "V" and status then
							push(ret)
						end
						if not status then throw(ret) end
					elseif inst == 0xB7 then
						--invokespecial
						local mr = cp[u2()]
						local cl = resolveClass(cp[mr.class_index])
						local name = cp[cp[mr.name_and_type_index].name_index].bytes..cp[cp[mr.name_and_type_index].descriptor_index].bytes
						local mt = findMethod(cl,name)
						local args = {}
						for i=#mt.desc-1,1,-1 do
							args[i+1] = pop()
						end
						args[1] = pop()
						local obj = args[1].data
						local status, ret = mt[1](unpack(args))
						if mt.desc[#mt.desc].type ~= "V" and status then
							push(ret)
						end
						if not status then throw(ret) end
					elseif inst == 0xB8 then
						--invokestatic
						local mr = cp[u2()]
						local cl = resolveClass(cp[mr.class_index])
						local name = cp[cp[mr.name_and_type_index].name_index].bytes..cp[cp[mr.name_and_type_index].descriptor_index].bytes
						local mt = findMethod(cl,name)
						local args = {}
						for i=#mt.desc-1,1,-1 do
							args[i] = pop()
						end
						local status, ret = mt[1](unpack(args))
						if mt.desc[#mt.desc].type ~= "V" and status then
							push(ret)
						end
						if not status then throw(ret) end
					elseif inst == 0xBB then
						--new
						local cr = cp[u2()]
						local c = resolveClass(cr)
						local obj = newInstance(c)
						local type = "L"..c.name:gsub("%.", "/")..";"
						push(asObjRef(obj, type))
					elseif inst == 0xBC then
						--newarray
						local type = "[" .. ARRAY_TYPES[u1()]
						local length = pop().data
						push(asObjRef({length=length}, type))
					elseif inst == 0xBD then
						--anewarray
						local cr = cp[u2()]
						local c = resolveClass(cr)
						local type = "[L" .. c.name:gsub("%.", "/")..";"
						local length = pop().data
						push(asObjRef({length=length}, type))
					elseif inst == 0xBE then
						--arraylength
						local arr = pop()
						push(asInt(arr.data.length))
					elseif inst == 0xBF then
						--throw
						local exc = pop()
						throw(exc)
					elseif inst == 0xC0 then
						--checkcast
						local obj = pop()
						local cl = "L"..cp[cp[u2()].name_index].bytes..";"
						if not classof(obj.type, cl) then
							error("Failed cast")
						end
						push(obj)
					elseif inst == 0xC1 then
						--instanceof
						local obj = pop()
						if not obj then
							push(asBoolean(false))
						else
							local cl = "L"..cp[cp[u2()].name_index].bytes..";"
							push(asBoolean(classof(obj.type, cl)))
						end
					else
						error("Unknown Opcode: "..string.format("%x",inst))
					end
				end)
				if jOk == false or jOk == true then
					return jOk, ret
				end
			end
			popStackTrace()
			return true
		end
	end
	
	local function method_info()
		local a,n = u2(),u2()
		local method = {
			acc = a,
			name = cp[n].bytes,
			descriptor = cp[u2()].bytes,
			attributes_count = u2(),
			attributes = {}
		}
		for i=0, method.attributes_count-1 do
			method.attributes[i] = attribute()
		end
		method.desc = {}
		parse_descriptor(method.desc,method.descriptor)
		method.name = method.name..method.descriptor
		return method
	end
	
	local s, e = pcall(function()
		assert(u1() == 0xCA and u1() == 0xFE and u1() == 0xBA and u1() == 0xBE,"invalid magic header")
		u2()u2()
		local cplen = u2()
		local prev
		for i=1, cplen-1 do
			if prev and (prev.cl == "D" or prev.cl == "J") then
				prev = nil
			else
				cp[i] = cp_entry()
				prev = cp[i]
			end
		end
		local access_flags = u2()
		local this_class = u2()
		local super_class = u2()

		cn = cp[cp[this_class].name_index].bytes:gsub("/",".")
		local super
		if cp[super_class] then -- Object.class won't
			super = cp[cp[super_class].name_index].bytes:gsub("/",".")
		end
		local Class = createClass(super, cn)
		if not Class then
			return false
		end
		Class.constantPool = cp
		
		--start processing the data
		Class.name = cn
		Class.acc = access_flags

		local interfaces_count = u2()
		Class.interfaces = {}
		for i=0, interfaces_count-1 do
			Class.interfaces[i] = u2()
		end
		local fields_count = u2()
		for i=0, fields_count-1 do
			Class.fields[i] = field_info()
			Class.fields[Class.fields[i].name] = Class.fields[i]
		end
		local methods_count = u2()
		local initialCount = #Class.methods
		local subtractor = 0
		for index=1, methods_count do
			local i = index + initialCount - subtractor

			local m = method_info()
			for i2,v in ipairs(Class.methods) do
				--print(v.name)
				if v.name == m.name then
					i = i2
					subtractor = subtractor + 1
				end
			end

			Class.methods[i] = m
			--find code attrib
			local ca
			for _, v in pairs(m.attributes) do
				--print(v.name)
				if v.code then ca = v end
			end

			local mt_name = Class.name.."."..m.name

			if ca then
				m[1] = createCodeFunction(ca, mt_name)
			elseif bit.band(m.acc,METHOD_ACC.NATIVE) == METHOD_ACC.NATIVE then
				if not natives[cn] then natives[cn] = {} end
				m[1] = function(...)
					pushStackTrace(mt_name, function() error('',0) end)
					if not natives[cn][m.name] then
						error("Native not implemented: " .. Class.name .. "." .. m.name, 0)
					end
					local args = {}
					for i,v in ipairs({...}) do
						args[i] = v.data
					end
					local ret = natives[cn][m.name](unpack(args))
					popStackTrace()
					return true, ret
				end
			else
				--print(m.name," doesn't have code")
			end
		end
		local attrib_count = u2()
		Class.attributes = {}
		for i=0, attrib_count-1 do
			Class.attributes[i] = attribute()
		end

		-- invoke static{}
		local staticmr = findMethod(Class, "<clinit>()V")
		if staticmr then
			staticmr[1]()
		end
	end)

	fh.close()
	if not s then error(e,0) end
	return cn
end
