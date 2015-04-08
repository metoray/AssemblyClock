public abstract class MultisegmentListener {
    private int state;
    private byte[] buffer=new byte[7];
    private Multisegment ms;
		
    public MultisegmentListener(Multisegment ms) {
	this.ms=ms;
	state=0;
    }

    public void handle() throws Exception {
	System.out.println("\nWaiting for input on serial port ...");
	while(true) {
	    byte b = read();			
	    System.out.println("Read byte = 0x" + String.format("%02x", b));

	    // on Windows : skip 0xff
	    if(b==(byte)0xff) {
		continue;
	    }

	    if (b==(byte)0x80) {
		for(int i=0;i<7;i++)
		    buffer[i]=0;
		state=0;
		write((byte)0x03);
		System.out.println("** Write byte = 0x03");
		continue;
	    }

	    if (b==(byte)0x81) {
		for(int i=0;i<7;i++)
		    buffer[i]=0;
		state=0;
		write((byte)0x03);
		System.out.println("** Write byte = 0x03");
		ms.getPanel().clearAll();
		continue;
	    }			
			
	    buffer[state]=b;
	    state=(state+1)%7;
	    if (state==0) {
		ms.getPanel().setAll(buffer);
		write((byte)0x01);
		System.out.println("** Write byte = 0x01");
	    } else 
		write((byte)0x02); 
	    System.out.println("** Write byte = 0x02");
	}
    }
	
    public abstract void prepare();
    public abstract void write(byte b) throws Exception;
    public abstract byte read() throws Exception;
}
