natives["java.io.PrintStream"] = natives["java.io.PrintStream"] or {}

local function lprint(s, p)
	if s ~= nil then
		p(s)
	else
		p("(null)")
	end
end

natives["java.io.PrintStream"]["println(Ljava/lang/String;)V"] = function(this, str)
	lprint(str, this.fields.err.value ~= 0 and printError or print)
end

natives["java.io.PrintStream"]["println(Z)V"] = function(this, str)
	lprint(str == 0, this.fields.err.value ~= 0 and printError or print)
end

natives["java.io.PrintStream"]["println(I)V"] = function(this, str)
	lprint(str, this.fields.err.value ~= 0 and printError or print)
end