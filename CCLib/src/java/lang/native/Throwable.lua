natives["java.lang.Throwable"] = natives["java.lang.Throwable"] or {}

natives["java.lang.Throwable"]["printStackTrace(Ljava/io/PrintStream;)V"] = function(this, p)
	findMethod(p, "println(Ljava/lang/String;)V")[1](asObjRef(p, "Ljava/io/PrintStream;"), asObjRef(this.name .. ": " .. (this.fields.message.value or ""), "Ljava/lang/String;"))
	findMethod(p, "println(Ljava/lang/String;)V")[1](asObjRef(p, "Ljava/io/PrintStream;"), asObjRef(this.stackTrace or "", "Ljava/lang/String;"))
end