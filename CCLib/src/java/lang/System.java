package java.lang;

import java.io.PrintStream;

public final class System {
	public static PrintStream out = new PrintStream();
	public static PrintStream err = new PrintStream(true);
}