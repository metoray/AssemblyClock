import java.net.*;
import java.io.*;
import gnu.io.*;
import java.util.*;

public class MultisegmentPort extends MultisegmentListener {
    private static CommPortIdentifier portId = null;
    private static Enumeration portList;
    private SerialPort serialPort;
    private InputStream inputStream;
    private static OutputStream outputStream;
	
    public MultisegmentPort(Multisegment ms, String sPort) {
	super(ms);
	boolean portFound = false;
	portList = CommPortIdentifier.getPortIdentifiers();

	while (portList.hasMoreElements() && !portFound) {
	    portId = (CommPortIdentifier) portList.nextElement();
	    if (portId.getPortType() == CommPortIdentifier.PORT_SERIAL) {
		if (portId.getName().equals(sPort)) {
		    portFound = true;
		}
	    }
	}

	// tijdelijk uit-gecomment om exit te vermijden als STK500 niet is aangesloten ...
	if (!portFound) {
	    System.out.println("Error : port '" + sPort + "' not found or in use");
	    System.exit(1);
	}
    }
	
    public void prepare() {
	// must handle declared exceptions
	try {
	    serialPort = (SerialPort) portId.open("Multisegment", 1000); // timeout = 1000 ms
	} catch (PortInUseException e) {
	    e.printStackTrace();
	    System.exit(-1);
	}

	// must handle declared exceptions
	try {
	    inputStream = serialPort.getInputStream();
	} catch (IOException e) {
	    e.printStackTrace();
	}

	try {
	    outputStream = serialPort.getOutputStream();
	} catch (IOException e) {
	    e.printStackTrace();
	}

	try {
	    serialPort.setSerialPortParams(19200, SerialPort.DATABITS_8,
					   SerialPort.STOPBITS_1, SerialPort.PARITY_NONE);
	} catch (UnsupportedCommOperationException e) { 
	    e.printStackTrace();
	}
    }
	
    public byte read() throws Exception {
	return (byte) inputStream.read();
    }

    public void write(byte b) throws Exception {
	outputStream.write(new byte[] {b});
    }
}
