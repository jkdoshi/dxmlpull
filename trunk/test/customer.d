module customer;

import tango.io.Stdout;
import tango.io.model.IConduit;
import tango.io.FileConduit;
import tango.text.Util;

import xmlpull;
import mxparser;

class Customer {
    public this() {
        _address = new Address();
    }

    private char[] _firstName;
    public char[] firstName() { return _firstName; }
    public char[] firstName(char[] val) { return _firstName = val; }

    private char[] _lastName;
    public char[] lastName() { return _lastName; }
    public char[] lastName(char[] val) { return _lastName = val; }

    private Address _address;
    public Address address() { return _address; }
    public Address address(Address val) { return _address = val; }
}

class Address {
    private char[] _address;
    public char[] address() { return _address; }
    public char[] address(char[] val) { return _address = val; }

    private char[] _line2;
    public char[] line2() { return _line2; }
    public char[] line2(char[] val) { return _line2 = val; }

    private char[] _city;
    public char[] city() { return _city; }
    public char[] city(char[] val) { return _city = val; }

    private char[] _state;
    public char[] state() { return _state; }
    public char[] state(char[] val) { return _state = val; }

    private char[] _zip;
    public char[] zip() { return _zip; }
    public char[] zip(char[] val) { return _zip = val; }
}

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

class Element(T, char[] tag, char[] content = "") {
    // unmarshal as root
    public static T unmarshal(XmlPullParser p) {
        p.next();
        require(p, p.START_TAG, tag);
        T ret = new T;
        with(ret) {
            mixin(content);
        }
        p.next();
        require(p, p.END_TAG, tag);
        return ret;
    }
    public void marshal(OutputStream outs) {
        // marshals "this" to outs
    }
}

char[] attributes(char[][] mapping) {
    char[] ret;
    foreach(i, value; mapping) {
        if(i % 2 == 0) { // even index
            char[] attr = value;
            char[] property = mapping[i+1];
            ret ~= property ~ "=p.getAttributeValue(null, \"" ~ attr ~ "\");\n";
        }
    }
    return ret;
}

class Element(T: Customer) : Element!(Customer, "customer",
        attributes(["fname", "firstName", "lname", "lastName"])) {}

void main() {
    auto p = new MXParser();
    scope fc = new FileConduit("customer.xml");
    scope(exit) fc.close();
    p.setInput(fc);
    assert(p.getEventType() is MXParser.START_DOCUMENT);

    auto c = Element!(Customer).unmarshal(p);
    Stdout(c.firstName).newline;
    Stdout(c.lastName).newline;
    //Stdout(attributes("a1", "p1", "a2", "p2"));
}
