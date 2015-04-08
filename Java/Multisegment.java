public class Multisegment {
    private MultisegmentPanel msp;
    private MultisegmentListener msl;
	
    public Multisegment(String s) {
	msp=new MultisegmentPanel(this);
	msl=new MultisegmentPort(this, s);
    }
	
    protected void exit() {
	System.exit(0);
    }

    public MultisegmentPanel getPanel() {
	return msp;
    }
	
    public static void main(String[] args) throws Exception {
	if (args==null || args.length!=1) { 
	    System.out.println("Usage: java -cp .:RXTXcomm.jar Multisegment <<serial port>> e.g. COM3 or /dev/ttyUSB0");
	    System.exit(1);
	}

	Multisegment ms=new Multisegment(args[0]);
	ms.msl.prepare();
	ms.msl.handle();
    }
}
