package java.lang;

import java.io.PrintStream;

public class Throwable {
	private String message;

	public Throwable() {
	}

	public Throwable(String message) {
		this.message = message;
	}

	public void printStackTrace() {
		printStackTrace(System.err);
	}

	public native void printStackTrace(PrintStream p);
}