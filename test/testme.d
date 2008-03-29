module main;

import xmlpull;
import mxparser;
import tango.io.Stdout;
import tango.io.FileConduit;
import tango.text.Util;

void require(XmlPullParser p, int expectedEvent, char[] expectedTag = null) {
    static char[] eventTagMsg(int event, char[] tag = null) {
        char[] ret = "event:" ~ XmlPullParser.TYPES[event];
        if(tag !is null) {
            ret ~= ",tag:" ~ tag;
        }
        return ret;
    }
    auto event = p.getEventType();
    auto tag = p.getName();
    if(event != expectedEvent || (expectedTag !is null && expectedTag != tag)) {
        auto msg = "Expected " ~ eventTagMsg(expectedEvent, expectedTag)
            ~ ", but got " ~ eventTagMsg(event, tag);
        throw new XmlPullParserException(msg);
    }
}

void skipWhitespace(XmlPullParser p) {
    if(p.getEventType() == XmlPullParser.TEXT) {
        if(trim(p.getText()).length == 0) {
            p.next();
        } else {
            throw new XmlPullParserException("Expected whitespace, got " ~ p.getText());
        }
    }
}

class Root {
    static Root unmarshal(XmlPullParser p) {
        auto ret = new Root();
        if(p.getEventType() == XmlPullParser.START_DOCUMENT) {
            p.next();
        }
        require(p, XmlPullParser.START_TAG, "root");
        p.next();
        skipWhitespace(p);
        ret._child = Child.unmarshal(p);
        p.next();
        require(p, XmlPullParser.TEXT);
        ret._text = p.getText();
        p.next();
        require(p, XmlPullParser.END_TAG, "root");
        p.next();
        require(p, XmlPullParser.END_DOCUMENT);
        return ret;
    }
    char[] _text;
    Child _child;
}

template RootElement(T, char[] element) {
    T unmarshal(XmlPullParser p) {
        auto ret = new T();
        require(p, XmlPullParser.START_DOCUMENT);
        p.next();
        require(p, XmlPullParser.START_TAG, element);
    }
}

class Child {
    char[] _attr;
    static Child unmarshal(XmlPullParser p) {
        auto ret = new Child();
        if(p.getEventType() == XmlPullParser.START_DOCUMENT) {
            p.next();
        }
        require(p, XmlPullParser.START_TAG, "child");
        ret._attr = p.getAttributeValue(null, "attr");
        p.next();
        require(p, XmlPullParser.END_TAG, "child");
        return ret;
    }
}

/**
 * Sample program to show how to use the dxmlpull XML pull parser.
 */
void main(char[][] args) {
    auto p = new MXParser();
    scope fc = new FileConduit("testme.xml");
    scope(exit) fc.close();
    p.setInput(fc);
    assert(p.getEventType() is MXParser.START_DOCUMENT);
    /+
    while(p.next() != MXParser.END_DOCUMENT) {
        Stdout("eventType=")(p.getEventType()).newline;
        Stdout("text=")(p.getText()).newline;
    }
    +/
    auto root = Root.unmarshal(p);
    Stdout("root._text=")(root._text).newline;
    Stdout("root._child._attr=")(root._child._attr).newline;
}
