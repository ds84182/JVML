local class = {}
local stack_trace = {}

function findMethod(c,name)
	if not c then error("class expected, got nil",2) end
	for i=1, #c.methods do
		if c.methods[i].name == name then
			return c.methods[i]
		end
	end
end

function newInstance(class)
	local obj = {fields={},methods={},name=class.name,class=class}
	for i, v in pairs(class.fields) do
		obj.fields[i] = {descriptor=v.descriptor,attrib=v.attrib,value=nil}
	end
	for i, v in pairs(class.methods) do
		obj.methods[i] = v
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
		error("Cannot find class ".. cn, 0)
	end
	if not loadJavaClass(fullPath) then
		error("Cannot load class " .. cn, 0)
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
	if class1 == class2 or classof(class1.super, class2) then
		return true
	else
		local cp = class1.constantPool
		for i,v in ipairs(class1.interfaces) do
			if classof(classByName(cp[cp[v].name_index].bytes:gsub("/",".")), class2) then
				return true
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

function pushStackTrace(s)
	table.insert(stack_trace, s)
end

function popStackTrace()
	table.remove(stack_trace)
end

function printStackTrace(isError, tabLevel)
	local reversedtable = {}
	for i,v in ipairs(stack_trace) do
		reversedtable[#stack_trace - i + 1] = v
	end
	local p = ((isError and printError) or print)
	local tabs = ("\t"):rep(tabLevel or 0)
	p(tabs..table.concat(reversedtable,"\n"..tabs))
end