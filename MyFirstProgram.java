import java.io.*;
import cc.*;
import java.util.Iterator;

class Test {
	public void m() {
		System.out.println("Test.m");
	}
}

class Yo extends Test {
	int a = 4;

	public Yo() {
		System.out.println("Yo constructor");
	}

	@Override public void m() {
		super.m();
		System.out.println("Yo.m");
	}
	public void v() {
		int b = a;
		b++;
		a = b;
		System.out.println(b);
		m();

		int[] errTest = new int[3];
		int errTest2 = errTest[5];
	}
}

public class MyFirstProgram {
	static int a = 6;

	/** Print a hello message */ 
	public static void main(String[] args) {
		int a = getNumber();
		System.out.println("Hello, world!");
		System.out.println(Computer.isTurtle());
		System.out.println(a+a);
		Yo y = new Yo();
		try {
			y.v();
		} catch (ArrayIndexOutOfBoundsException e) {
			e.printStackTrace();
		}
		Test t = y;
		t.m();


		Iterable<String> i = new Iterable<String>() {
			public Iterator<String> iterator() {
				return new Iterator<String>() {
					String[] arr = {"Hey", "You", "Mr.", "Clue"};
					int i = 0;

					{
						arr[0] = "Hey";
						arr[1] = "You";
						arr[2] = "Mr.";
						arr[3] = "Clue";
					}

					public boolean hasNext() {
						if (i < arr.length)
							return true;
						return false;
					}
					public String next() {
						return arr[i++];
					}
					public void remove() {

					}
				};
			}
		};


		for (String s : i) {
			System.out.println(s);
		}

		System.out.println("" instanceof String);
	}
	
	public static int getNumber()
	{
		return a;
	}

	static {
		System.out.println("Test static");
	}
}
