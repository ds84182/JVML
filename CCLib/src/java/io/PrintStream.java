package java.io;

public class PrintStream {
	private boolean err;

	public native void println(String in);
	public native void println(int in);
	public native void println(boolean in);

	public PrintStream() {
		this(false);
	}

	public PrintStream(boolean err) {
		this.err = err;
	}
}