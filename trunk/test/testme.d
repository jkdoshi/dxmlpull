module main;

import mxparser;
import tango.io.Stdout;
import tango.io.FileConduit;

/**
 * Sample program to show how to use the dxmlpull XML pull parser.
 */
void main(char[][] args) {
    auto p = new MXParser();
    scope fc = new FileConduit("testme.xml");
    scope(exit) fc.close();
    p.setInput(fc);
    assert(p.getEventType() is MXParser.START_DOCUMENT);
    while(p.next() != MXParser.END_DOCUMENT) {
        Stdout("eventType=")(p.getEventType()).newline;
        Stdout("text=")(p.getText()).newline;
    }
}
