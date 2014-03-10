local class = {}
local stack_trace = {}
local throw_trace = {} -- throw functions are traced so that code can throw from anywhere
						-- for example, class not found exception

function findMethod(c,name)
	if not c then error("class expected, got nil",2) end
	for i=1, #c.methods do
		if c.methods[i].name == name then
			return c.methods[i]
		end
	end
end

function newInstance(class)
	local obj = {fields={},name=class.name,class=class}
	for i, v in pairs(class.fields) do
		obj.fields[i] = {descriptor=v.descriptor,attrib=v.attrib,value=nil}
	end
	
	return obj
end

function resolvePath(name)
	for sPath in string.gmatch(jcp, "[^:]+") do
		local fullPath = fs.combine(shell.resolve(sPath), name)
		if fs.exists(fullPath) then
			return fullPath
		end
	end
end

function classByName(cn)
	local c = class[cn]
	if c then
		return c
	end
	local cd = cn:gsub("%.","/")

	local fullPath = resolvePath(cd..".class")
	if not fullPath then
		local exc = newInstance(classByName("java.lang.ClassNotFoundException"))
		local obj = asObjRef(exc, "Ljava/lang/ClassNotFoundException;")
		exc.fields.message.value = cn
		throw(obj)
		return false
	end
	if not loadJavaClass(fullPath) then
		return false
	else
		c = class[cn]
		return c
	end
end

function createClass(super_name, cn)
	local cls = {}
	class[cn] = cls
	cls.fields = {}
	cls.methods = {}
	if super_name then -- we have a custom Object class file which won't have a super
		local super = classByName(super_name)
		cls.super = super
		for i,v in pairs(super.fields) do
			cls.fields[i] = v
		end
		for i,v in pairs(super.methods) do
			cls.methods[i] = v
		end
	end
	return cls
end

local function _classof(class1, class2)
	if class1 == class2 then
		return 0
	end
	local dist = _classof(class1.super, class2)
	if dist then
		return dist
	else
		local cp = class1.constantPool
		for i,v in ipairs(class1.interfaces) do
			local dist = _classof(classByName(cp[cp[v].name_index].bytes:gsub("/",".")), class2)
			if dist then
				return dist
			end
		end
	end
	return false
end

local wrappers = {
	I="java.lang.Integer",
	F="java.lang.Float",
	D="java.lang.Double",
	J="java.lang.Long",
	Z="java.lang.Boolean",
	C="java.lang.Character",
	B="java.lang.Byte",
	S="java.lang.Short"
}

local function wrapperof(type)
	if type:len() == 1 then
		return wrappers[type]
	end
	return type
end

function classof(class1, class2)
	if class1 == class2 then
		return true
	end
	local root1,root2 = class1:gsub("^%[*", ""), class2:gsub("^%[*", "")
	class1 = gsub("[^%[]$", wrapperof(root1))
	class2 = gsub("[^%[]$", wrapperof(root2))
	return _classof(classByName(class1), classByName(class2))
end

function pushStackTrace(s, throw)
	table.insert(stack_trace, s)
	table.insert(throw_trace, throw)
end

function popStackTrace()
	table.remove(stack_trace)
	table.remove(throw_trace)
end

function getStackTrace()
	local reversedtable = {}
	for i,v in ipairs(stack_trace) do
		reversedtable[#stack_trace - i + 1] = v
	end
	return "\t"..table.concat(reversedtable,"\n\t")
end

function throw(exc)
	throw_trace[#throw_trace](exc)
end