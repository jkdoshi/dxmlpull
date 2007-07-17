/**
 * A D version of the XML-pull API and its implementation.
 * Derived from XPP3/MXP1.
 * See http://www.xmlpull.org/ for API.
 * See http://www.extreme.indiana.edu/xgws/xsoap/xpp/mxp1/ for implementation.
 * Authors: Jitesh Doshi, http://www.sysdelphia.com/
 */
module mxparser;

//TODO best handling of interning issues
//have isAllNewStringInterned ???

//TODO handling surrogate pairs: http://www.unicode.org/unicode/faq/utf_bom.html#6

//TODO review code for use of bufAbsoluteStart when keeping pos between next()/fillBuf()

/**
* Absolutely minimal implementation of XMLPULL V1 API
*
* @author <a href="http://www.extreme.indiana.edu/~aslom/">Aleksander Slominski</a>
*/

import tango.io.Stdout;
import tango.core.Exception;
import tango.text.convert.Sprint;
import tango.text.convert.Integer;

import xmlpull;

private alias bool boolean;
private static Sprint!(char) sprint;
static this() {
    sprint = new Sprint!(char);
}

class MXParser : XmlPullParser
{
    //NOTE: no interning of those strings --> by Java lang spec they MUST be already interned
    protected final static char[] XML_URI = "http://www.w3.org/XML/1998/namespace";
    protected final static char[] XMLNS_URI = "http://www.w3.org/2000/xmlns/";
    protected final static char[] FEATURE_XML_ROUNDTRIP=
       //"http://xmlpull.org/v1/doc/features.html#xml-roundtrip";
       "http://xmlpull.org/v1/doc/features.html#xml-roundtrip";
    protected final static char[] FEATURE_NAMES_INTERNED =
       "http://xmlpull.org/v1/doc/features.html#names-interned";
    protected final static char[] PROPERTY_XMLDECL_VERSION =
       "http://xmlpull.org/v1/doc/properties.html#xmldecl-version";
    protected final static char[] PROPERTY_XMLDECL_STANDALONE =
       "http://xmlpull.org/v1/doc/properties.html#xmldecl-standalone";
    protected final static char[] PROPERTY_XMLDECL_CONTENT =
       "http://xmlpull.org/v1/doc/properties.html#xmldecl-content";
    protected final static char[] PROPERTY_LOCATION =
       "http://xmlpull.org/v1/doc/properties.html#location";

    /**
    * Implementation notice:
    * the is instance variable that controls if newString() is interning.
    * <p><b>NOTE:</b> newStringIntern <b>always</b> returns interned strings
    * and newString MAY return interned char[] depending on this variable.
    * <p><b>NOTE:</b> by default in this minimal implementation it is false!
    */
    protected boolean allStringsInterned;

    protected void resetStringCache() {
       //Stdout("resetStringCache() minimum called");
    }

    protected char[] newString(char[] cbuf, int off, int len) {
       return cbuf[off .. off + len].dup;
    }

    protected char[] newStringIntern(char[] cbuf, int off, int len) {
        // TODO figure out how to do "intern"
       return cbuf[off .. off + len].dup;
       //return (new String(cbuf, off, len)).intern();
    }

    private static final boolean TRACE_SIZING = true;

    // NOTE: features are not resettable and typically defaults to false ...
    protected boolean processNamespaces;
    protected boolean roundtripSupported;

    // global parser state
    protected char[] location;
    protected int lineNumber;
    protected int columnNumber;
    protected boolean seenRoot;
    protected boolean reachedEnd;
    protected int eventType;
    protected boolean emptyElementTag;
    // element stack
    protected int depth;
    protected char[][] elRawName;
    protected int[] elRawNameEnd;
    protected int[] elRawNameLine;

    protected char[][] elName;
    protected char[][] elPrefix;
    protected char[][] elUri;
    //protected char[][] elValue;
    protected int[] elNamespaceCount;



    /**
    * Make sure that we have enough space to keep element stack if passed size.
    * It will always create one additional slot then current depth
    */
    protected void ensureElementsCapacity() {
       int elStackSize = elName.length;
       if( (depth + 1) >= elStackSize) {
           // we add at least one extra slot ...
           int newSize = (depth >= 7 ? 2 * depth : 8) + 2; // = lucky 7 + 1 //25
           if(TRACE_SIZING) {
               Stdout.formatln("TRACE_SIZING elStackSize {0} ==> {1}", elStackSize, newSize);
           }
           elName.length = elPrefix.length = elUri.length = elNamespaceCount.length = elRawNameEnd.length = elRawNameLine.length = elRawName.length = newSize;
           if(elStackSize == 0) {
               elNamespaceCount[0] = 0;
           }

           // elLocalName.length = elDefaultNs.length = elNsStackPos.length = newSize;
           // for (int i = elStackSize; i < newSize; i++)
           // {
           //    elNsStackPos[i] = (i > 0) ? -1 : 0;
           // }
           // elNsStackPos = iarr;
           assert(depth < elName.length);
       }
    }



    // attribute stack
    protected int attributeCount;
    protected char[] attributeName[];
    protected int attributeNameHash[];
    //protected int attributeNameStart[];
    //protected int attributeNameEnd[];
    protected char[] attributePrefix[];
    protected char[] attributeUri[];
    protected char[] attributeValue[];
    //protected int attributeValueStart[];
    //protected int attributeValueEnd[];


    /**
    * Make sure that in attributes temporary array is enough space.
    */
    protected  void ensureAttributesCapacity(int size) {
       int attrPosSize = attributeName.length;
       if(size >= attrPosSize) {
           int newSize = size > 7 ? 2 * size : 8; // = lucky 7 + 1 //25
           if(TRACE_SIZING) {
               Stdout.formatln("TRACE_SIZING attrPosSize {0} ==> {1}", attrPosSize, newSize);
           }
           attributeName.length = attributePrefix.length = attributeUri.length = attributeValue.length = newSize;
           if( ! allStringsInterned ) {
               attributeNameHash.length = newSize;
           }
           assert(attributeName.length > size);
       }
    }

    // namespace stack
    protected int namespaceEnd;
    protected char[] namespacePrefix[];
    protected int namespacePrefixHash[];
    protected char[] namespaceUri[];

    protected void ensureNamespacesCapacity(int size) {
       int namespaceSize = namespacePrefix.length;
       if(size >= namespaceSize) {
           int newSize = size > 7 ? 2 * size : 8; // = lucky 7 + 1 //25
           if(TRACE_SIZING) {
               Stdout.formatln("TRACE_SIZING namespaceSize {0} ==> {1}", namespaceSize, newSize);
           }
           namespacePrefix.length = namespaceUri.length = newSize;
           if( ! allStringsInterned ) {
               namespacePrefixHash.length = newSize;
           }
           //prefixesSize = newSize;
           // //assert nsPrefixes.length > size && nsPrefixes.length == newSize
       }
    }

    /**
    * simplistic implementation of hash function that has <b>constant</b>
    * time to compute - so it also means diminishing hash quality for long strings
    * but for XML parsing it should be good enough ...
    */
    protected static final int fastHash( char ch[], int off = 0, int len = -1) {
       if(len == 0) return 0;
       if(len == -1) len = ch.length;
       //assert len >0
       int hash = ch[off]; // hash at beginning
       //try {
       hash = (hash << 7) + ch[ off +  len - 1 ]; // hash at the end
       //} catch(ArrayIndexOutOfBoundsException aie) {
       //    aie.printStackTrace(); //should never happen ...
       //    throw new RuntimeException("this is violation of pre-condition");
       //}
       if(len > 16) hash = (hash << 7) + ch[ off + (len / 4)];  // 1/4 from beginning
       if(len > 8)  hash = (hash << 7) + ch[ off + (len / 2)];  // 1/2 of string size ...
       // notice that hash is at most done 3 times <<7 so shifted by 21 bits 8 bit value
       // so max result == 29 bits so it is quite just below 31 bits for long (2^32) ...
       //assert hash >= 0;
       return  hash;
    }

    // entity replacement stack
    protected int entityEnd;

    protected char[] entityName[];
    protected char[] entityNameBuf[];
    protected char[] entityReplacement[];
    protected char[] entityReplacementBuf[];

    protected int entityNameHash[];

    protected void ensureEntityCapacity() {
       int entitySize = entityReplacementBuf.length;
       if(entityEnd >= entitySize) {
           int newSize = entityEnd > 7 ? 2 * entityEnd : 8; // = lucky 7 + 1 //25
           if(TRACE_SIZING) {
               Stdout.formatln("TRACE_SIZING entitySize {0} ==> {1}", entitySize, newSize);
           }
           entityName.length = entityNameBuf.length = entityReplacement.length = entityReplacementBuf.length = newSize;

           if( ! allStringsInterned ) {
               entityNameHash.length = newSize;
           }
       }
    }

    // input buffer management
    protected static final int READ_CHUNK_SIZE = 8*1024; //max data chars in one read() call
    protected InputStream input;
    protected char[] inputEncoding;
    // protected InputStream inputStream;


    protected int bufLoadFactor = 95;  // 99%
    //protected int bufHardLimit;  // only matters when expanding

    protected char[] buf;
    protected int bufSoftLimit; // desirable size of buffer
    protected boolean preventBufferCompaction;

    protected int bufAbsoluteStart; // this is buf
    protected int bufStart;
    protected int bufEnd;
    protected int pos;
    protected int posStart;
    protected int posEnd;

    protected char[] pc;
    protected int pcStart;
    protected int pcEnd;


    // parsing state
    //protected boolean needsMore;
    //protected boolean seenMarkup;
    protected boolean usePC;


    protected boolean seenStartTag;
    protected boolean seenEndTag;
    protected boolean pastEndTag;
    protected boolean seenAmpersand;
    protected boolean seenMarkup;
    protected boolean seenDocdecl;

    // transient variable set during each call to next/Token()
    protected boolean tokenize;
    protected char[] text;
    protected char[] entityRefName;

    protected char[] xmlDeclVersion;
    protected boolean xmlDeclStandalone;
    protected char[] xmlDeclContent;

    protected void reset() {
       //Stdout("reset() called");
       location = null;
       lineNumber = 1;
       columnNumber = 0;
       seenRoot = false;
       reachedEnd = false;
       eventType = START_DOCUMENT;
       emptyElementTag = false;

       depth = 0;

       attributeCount = 0;

       namespaceEnd = 0;

       entityEnd = 0;

       input = null;
       inputEncoding = null;

       preventBufferCompaction = false;
       bufAbsoluteStart = 0;
       bufEnd = bufStart = 0;
       pos = posStart = posEnd = 0;

       pcEnd = pcStart = 0;

       usePC = false;

       seenStartTag = false;
       seenEndTag = false;
       pastEndTag = false;
       seenAmpersand = false;
       seenMarkup = false;
       seenDocdecl = false;

       xmlDeclVersion = null;
       xmlDeclStandalone = false;
       xmlDeclContent = null;

       resetStringCache();
    }

    public this() {
        buf = new char[/* Runtime.getRuntime().freeMemory() > 1000000L */ true ? READ_CHUNK_SIZE : 256 ];
        bufSoftLimit = ( bufLoadFactor * buf.length ) /100; // desirable size of buffer
        pc = new char[/* Runtime.getRuntime().freeMemory() > 1000000L */ true ? READ_CHUNK_SIZE : 64 ];
        charRefOneCharBuf = new char[1];
    }


    /**
    * Method setFeature
    *
    * @param    name                a  char[]
    * @param    state               a  boolean
    *
    * @throws   XmlPullParserException
    *
    */
    public void setFeature(char[] name,
                          boolean state) /* throws XmlPullParserException */
    {
       if(name == null) throw new IllegalArgumentException("feature name should not be null");
       if(FEATURE_PROCESS_NAMESPACES == name) {
           if(eventType != START_DOCUMENT) throw new XmlPullParserException(
                   "namespace processing feature can only be changed before parsing", this);
           processNamespaces = state;
           //        } else if(FEATURE_REPORT_NAMESPACE_ATTRIBUTES == name) {
           //      if(type != START_DOCUMENT) throw new XmlPullParserException(
           //              "namespace reporting feature can only be changed before parsing", this, null);
           //            reportNsAttribs = state;
       } else if(FEATURE_NAMES_INTERNED == name) {
           if(state != false) {
               throw new XmlPullParserException(
                   "interning names in this implementation is not supported");
           }
       } else if(FEATURE_PROCESS_DOCDECL == name) {
           if(state != false) {
               throw new XmlPullParserException(
                   "processing DOCDECL is not supported");
           }
           //} else if(REPORT_DOCDECL == name) {
           //    paramNotifyDoctype = state;
       } else if(FEATURE_XML_ROUNDTRIP == name) {
           //if(state == false) {
           //    throw new XmlPullParserException(
           //        "roundtrip feature can not be switched off");
           //}
           roundtripSupported = state;
       } else {
           throw new XmlPullParserException("unsupported feature " ~ name);
       }
    }

    /** Unknown properties are <strong>always</strong> returned as false */
    public boolean getFeature(char[] name)
    {
       if(name == null) throw new IllegalArgumentException("feature name should not be null");
       if(FEATURE_PROCESS_NAMESPACES == name) {
           return processNamespaces;
           //        } else if(FEATURE_REPORT_NAMESPACE_ATTRIBUTES == name) {
           //            return reportNsAttribs;
       } else if(FEATURE_NAMES_INTERNED == name) {
           return false;
       } else if(FEATURE_PROCESS_DOCDECL == name) {
           return false;
           //} else if(REPORT_DOCDECL == name) {
           //    return paramNotifyDoctype;
       } else if(FEATURE_XML_ROUNDTRIP == name) {
           //return true;
           return roundtripSupported;
       }
       return false;
    }

    public void setProperty(char[] name,
                           char[] value)
       /* throws XmlPullParserException */
    {
       if(PROPERTY_LOCATION == name) {
           location = value;
       } else {
           throw new XmlPullParserException("unsupported property: '" ~ name ~ "'");
       }
    }


    public char[] getProperty(char[] name)
    {
       if(name == null) throw new IllegalArgumentException("property name should not be null");
       if(PROPERTY_XMLDECL_VERSION == name) {
           return xmlDeclVersion;
       // } else if(PROPERTY_XMLDECL_STANDALONE == name) {
       //     return xmlDeclStandalone;
       } else if(PROPERTY_XMLDECL_CONTENT == name) {
           return xmlDeclContent;
       } else if(PROPERTY_LOCATION == name) {
           return location;
       }
       return null;
    }


    public void setInput(InputStream input) /* throws XmlPullParserException */
    {
       reset();
       this.input = input;
    }

    /+
    public void setInput(java.io.InputStream inputStream, char[] inputEncoding)
       /* throws XmlPullParserException */
    {
       if(inputStream == null) {
           throw new IllegalArgumentException("input stream can not be null");
       }
       this.inputStream = inputStream;
       Reader reader;
       //if(inputEncoding != null) {
       try {
           if(inputEncoding != null) {
               reader = new InputStreamReader(inputStream, inputEncoding);
           } else {
               //by default use UTF-8 (InputStreamReader(inputStream)) would use OS default ...
               reader = new InputStreamReader(inputStream, "UTF-8");
           }
       } catch (UnsupportedEncodingException une) {
           throw new XmlPullParserException(
               "could not create reader for encoding " ~ inputEncoding ~ " : " ~ une, this, une);
       }
       //} else {
       //    reader = new InputStreamReader(inputStream);
       //}
       setInput(reader);
       //must be here as reest() was called in setInput() and has set this.inputEncoding to null ...
       this.inputEncoding = inputEncoding;
    }
    +/

    public char[] getInputEncoding() {
       return inputEncoding;
    }

    public void defineEntityReplacementText(char[] entityName,
                                           char[] replacementText)
       /* throws XmlPullParserException */
    {
       //      throw new XmlPullParserException("not allowed");

       //protected char[] entityReplacement[];
       ensureEntityCapacity();

       // this is to make sure that if interning works we will take advantage of it ...
       this.entityName[entityEnd] = newString(entityName, 0, entityName.length);
       entityNameBuf[entityEnd] = entityName.dup;

       entityReplacement[entityEnd] = replacementText;
       entityReplacementBuf[entityEnd] = replacementText.dup;
       if(!allStringsInterned) {
           entityNameHash[ entityEnd ] =
               fastHash(entityNameBuf[entityEnd], 0, entityNameBuf[entityEnd].length);
       }
       ++entityEnd;
       //TODO disallow < or & in entity replacement text (or ]]>???)
       // TOOD keepEntityNormalizedForAttributeValue cached as well ...
    }

    public int getNamespaceCount(int depth)
       /* throws XmlPullParserException */
    {
       if(processNamespaces == false || depth == 0) {
           return 0;
       }
       //int maxDepth = eventType == END_TAG ? this.depth + 1 : this.depth;
       //if(depth < 0 || depth > maxDepth) throw new IllegalArgumentException(
       if(depth < 0 || depth > this.depth) throw new Exception(
               sprint.format("allowed namespace depth 0..{} not {}", this.depth, depth));
       return elNamespaceCount[ depth ];
    }

    public char[] getNamespacePrefix(int pos)
       /* throws XmlPullParserException */
    {

       //int end = eventType == END_TAG ? elNamespaceCount[ depth + 1 ] : namespaceEnd;
       //if(pos < end) {
       if(pos < namespaceEnd) {
           return namespacePrefix[ pos ];
       } else {
           throw new XmlPullParserException(
               sprint.format("position {} exceeded number of available namespaces {}", pos, namespaceEnd));
       }
    }

    public char[] getNamespaceUri(int pos) /* throws XmlPullParserException */
    {
       //int end = eventType == END_TAG ? elNamespaceCount[ depth + 1 ] : namespaceEnd;
       //if(pos < end) {
       if(pos < namespaceEnd) {
           return namespaceUri[ pos ];
       } else {
           throw new XmlPullParserException(
               sprint.format("position {} exceeded number of available namespaces {}", pos, namespaceEnd));
       }
    }

    public char[] getNamespace( char[] prefix )
       //throws XmlPullParserException
    {
       //int count = namespaceCount[ depth ];
       if(prefix != null) {
           for( int i = namespaceEnd -1; i >= 0; i--) {
               if( prefix == namespacePrefix[ i ] ) {
                   return namespaceUri[ i ];
               }
           }
           if("xml" == prefix ) {
               return XML_URI;
           } else if("xmlns" == prefix ) {
               return XMLNS_URI;
           }
       } else {
           for( int i = namespaceEnd -1; i >= 0; i--) {
               if( namespacePrefix[ i ]  == null) { //"") { //null ) { //TODO check FIXME Alek
                   return namespaceUri[ i ];
               }
           }

       }
       return null;
    }


    public int getDepth()
    {
       return depth;
    }


    private static int findFragment(int bufMinPos, char[] b, int start, int end) {
       //System.err.println("bufStart="+bufStart+" b="+printable(new char[](b, start, end - start))+" start="+start+" end="+end);
       if(start < bufMinPos) {
           start = bufMinPos;
           if(start > end) start = end;
           return start;
       }
       if(end - start > 65) {
           start = end - 10; // try to find good location
       }
       int i = start + 1;
       while(--i > bufMinPos) {
           if((end - i) > 65) break;
           char c = b[i];
           if(c == '<' && (start - i) > 10) break;
       }
       return i;
    }


    /**
    * Return string describing current position of parsers as
    * text 'STATE [seen %s...] @line:column'.
    */
    public char[] getPositionDescription ()
    {
       char[] fragment = null;
       if(posStart <= pos) {
           int start = findFragment(0, buf, posStart, pos);
           //System.err.println("start="+start);
           if(start < pos) {
               fragment = buf[start .. pos];
           }
           if(bufAbsoluteStart > 0 || start > 0) fragment = "..." ~ fragment;
       }
       //        return " at line "+tokenizerPosRow
       //            +" and column "+(tokenizerPosCol-1)
       //            +(fragment != null ? " seen "+printable(fragment)+"..." : "");
       return sprint.format(" {}{} {}@{}:{}", TYPES[eventType], (fragment != null ? " seen "~printable(fragment)~"..." : ""), location, getLineNumber(), getColumnNumber());
    }

    public int getLineNumber()
    {
       return lineNumber;
    }

    public int getColumnNumber()
    {
       return columnNumber;
    }


    public boolean isWhitespace() /* throws XmlPullParserException */
    {
       if(eventType == TEXT || eventType == CDSECT) {
           if(usePC) {
               for (int i = pcStart; i <pcEnd; i++)
               {
                   if(!isS(pc[ i ])) return false;
               }
               return true;
           } else {
               for (int i = posStart; i <posEnd; i++)
               {
                   if(!isS(buf[ i ])) return false;
               }
               return true;
           }
       } else if(eventType == IGNORABLE_WHITESPACE) {
           return true;
       }
       throw new XmlPullParserException("no content available to check for white spaces");
    }

    public char[] getText()
    {
       if(eventType == START_DOCUMENT || eventType == END_DOCUMENT) {
           //throw new XmlPullParserException("no content available to read");
           //      if(roundtripSupported) {
           //          text = new char[](buf, posStart, posEnd - posStart);
           //      } else {
           return null;
           //      }
       } else if(eventType == ENTITY_REF) {
           return text;
       }
       if(text == null) {
           if(!usePC || eventType == START_TAG || eventType == END_TAG) {
               text = buf[posStart .. posEnd].dup;
           } else {
               text = pc[pcStart .. pcEnd].dup;
           }
       }
       return text;
    }

    public char[] getTextCharacters(int [] holderForStartAndLength)
    {
       if( eventType == TEXT ) {
           if(usePC) {
               holderForStartAndLength[0] = pcStart;
               holderForStartAndLength[1] = pcEnd - pcStart;
               return pc;
           } else {
               holderForStartAndLength[0] = posStart;
               holderForStartAndLength[1] = posEnd - posStart;
               return buf;

           }
       } else if( eventType == START_TAG
                     || eventType == END_TAG
                     || eventType == CDSECT
                     || eventType == COMMENT
                     || eventType == ENTITY_REF
                     || eventType == PROCESSING_INSTRUCTION
                     || eventType == IGNORABLE_WHITESPACE
                     || eventType == DOCDECL)
       {
           holderForStartAndLength[0] = posStart;
           holderForStartAndLength[1] = posEnd - posStart;
           return buf;
       } else if(eventType == START_DOCUMENT
                     || eventType == END_DOCUMENT) {
           //throw new XmlPullParserException("no content available to read");
           holderForStartAndLength[0] = holderForStartAndLength[1] = -1;
           return null;
       } else {
           throw new IllegalArgumentException(sprint.format("unknown text eventType: {}", eventType));
       }
       //      char[] s = getText();
       //      char[] cb = null;
       //      if(s!= null) {
       //          cb = s.dup;
       //          holderForStartAndLength[0] = 0;
       //          holderForStartAndLength[1] = s.length;
       //      } else {
       //      }
       //      return cb;
    }

    public char[] getNamespace()
    {
       if(eventType == START_TAG) {
           //return processNamespaces ? elUri[ depth - 1 ] : NO_NAMESPACE;
           return processNamespaces ? elUri[ depth  ] : NO_NAMESPACE;
       } else if(eventType == END_TAG) {
           return processNamespaces ? elUri[ depth ] : NO_NAMESPACE;
       }
       return null;
       //        char[] prefix = elPrefix[ maxDepth ];
       //        if(prefix != null) {
       //            for( int i = namespaceEnd -1; i >= 0; i--) {
       //                if( prefix == namespacePrefix[ i ] ) {
       //                    return namespaceUri[ i ];
       //                }
       //            }
       //        } else {
       //            for( int i = namespaceEnd -1; i >= 0; i--) {
       //                if( namespacePrefix[ i ]  == null ) {
       //                    return namespaceUri[ i ];
       //                }
       //            }
       //
       //        }
       //        return "";
    }

    public char[] getName()
    {
       if(eventType == START_TAG) {
           //return elName[ depth - 1 ] ;
           return elName[ depth ] ;
       } else if(eventType == END_TAG) {
           return elName[ depth ] ;
       } else if(eventType == ENTITY_REF) {
           if(entityRefName == null) {
               entityRefName = newString(buf, posStart, posEnd - posStart);
           }
           return entityRefName;
       } else {
           return null;
       }
    }

    public char[] getPrefix()
    {
       if(eventType == START_TAG) {
           //return elPrefix[ depth - 1 ] ;
           return elPrefix[ depth ] ;
       } else if(eventType == END_TAG) {
           return elPrefix[ depth ] ;
       }
       return null;
       //        if(eventType != START_TAG && eventType != END_TAG) return null;
       //        int maxDepth = eventType == END_TAG ? depth : depth - 1;
       //        return elPrefix[ maxDepth ];
    }


    public boolean isEmptyElementTag() /* throws XmlPullParserException */
    {
       if(eventType != START_TAG) throw new XmlPullParserException(
               "parser must be on START_TAG to check for empty element", this);
       return emptyElementTag;
    }

    public int getAttributeCount()
    {
       if(eventType != START_TAG) return -1;
       return attributeCount;
    }

    public char[] getAttributeNamespace(int index)
    {
       if(eventType != START_TAG) throw new IndexOutOfBoundsException(
               "only START_TAG can have attributes");
       if(processNamespaces == false) return NO_NAMESPACE;
       if(index < 0 || index >= attributeCount) throw new IndexOutOfBoundsException(
               sprint.format("attribute position must be 0..{} and not {}", attributeCount-1, index));
       return attributeUri[ index ];
    }

    public char[] getAttributeName(int index)
    {
       if(eventType != START_TAG) throw new IndexOutOfBoundsException(
               "only START_TAG can have attributes");
       if(index < 0 || index >= attributeCount) throw new IndexOutOfBoundsException(
               sprint.format("attribute position must be 0..{} and not {}", attributeCount-1, index));
       return attributeName[ index ];
    }

    public char[] getAttributePrefix(int index)
    {
       if(eventType != START_TAG) throw new IndexOutOfBoundsException(
               "only START_TAG can have attributes");
       if(processNamespaces == false) return null;
       if(index < 0 || index >= attributeCount) throw new IndexOutOfBoundsException(
               sprint.format("attribute position must be 0..{} and not {}", attributeCount-1, index));
       return attributePrefix[ index ];
    }

    public char[] getAttributeType(int index) {
       if(eventType != START_TAG) throw new IndexOutOfBoundsException(
               "only START_TAG can have attributes");
       if(index < 0 || index >= attributeCount) throw new IndexOutOfBoundsException(
               sprint.format("attribute position must be 0..{} and not {}", attributeCount-1, index));
       return "CDATA";
    }

    public boolean isAttributeDefault(int index) {
       if(eventType != START_TAG) throw new IndexOutOfBoundsException(
               "only START_TAG can have attributes");
       if(index < 0 || index >= attributeCount) throw new IndexOutOfBoundsException(
               sprint.format("attribute position must be 0..{} and not {}", attributeCount-1, index));
       return false;
    }

    public char[] getAttributeValue(int index)
    {
       if(eventType != START_TAG) throw new IndexOutOfBoundsException(
               "only START_TAG can have attributes");
       if(index < 0 || index >= attributeCount) throw new IndexOutOfBoundsException(
               sprint.format("attribute position must be 0..{} and not {}", attributeCount-1, index));
       return attributeValue[ index ];
    }

    public char[] getAttributeValue(char[] namespace,
                                   char[] name)
    {
       if(eventType != START_TAG) throw new IndexOutOfBoundsException(
               "only START_TAG can have attributes" ~ getPositionDescription());
       if(name == null) {
           throw new IllegalArgumentException("attribute name can not be null");
       }
       // TODO make check if namespace is interned!!! etc. for names!!!
       if(processNamespaces) {
           if(namespace == null) {
               namespace = "";
           }

           for(int i = 0; i < attributeCount; ++i) {
               if((namespace == attributeUri[ i ] ||
                       namespace == attributeUri[ i ] )
                      //(namespace != null && namespace == attributeUri[ i ])
                      // taking advantage of char[].intern()
                      && name == attributeName[ i ] )
               {
                   return attributeValue[i];
               }
           }
       } else {
           if(namespace != null && namespace.length == 0) {
               namespace = null;
           }
           if(namespace != null) throw new IllegalArgumentException(
                   "when namespaces processing is disabled attribute namespace must be null");
           for(int i = 0; i < attributeCount; ++i) {
               if(name == attributeName[i])
               {
                   return attributeValue[i];
               }
           }
       }
       return null;
    }


    public int getEventType()
       /* throws XmlPullParserException */
    {
       return eventType;
    }

    public void require(int type, char[] namespace, char[] name)
       /* throws XmlPullParserException, IOException */
    {
       if(processNamespaces == false && namespace != null) {
           throw new XmlPullParserException(
               "processing namespaces must be enabled on parser (or factory)"
                   " to have possible namespaces declared on elements", this);
       }
       if (type != getEventType()
               || (namespace != null && namespace != getNamespace())
               || (name != null && name != getName ()) )
       {
           throw new XmlPullParserException (
               "expected event " ~ TYPES[ type ]
                   ~(name != null ? " with name '"~name~"'" : "")
                   ~(namespace != null && name != null ? " and" : "")
                   ~(namespace != null ? " with namespace '"~namespace~"'" : "")
                   ~" but got"
                   ~(type != getEventType() ? " "~TYPES[ getEventType() ] : "")
                   ~(name != null && getName() != null && name != getName()
                         ? " name '"~getName()~"'" : "")
                   ~(namespace != null && name != null
                         && getName() != null && name != getName ()
                         && getNamespace() != null && namespace != getNamespace()
                         ? " and" : "")
                   ~(namespace != null && getNamespace() != null && namespace != getNamespace()
                         ? " namespace '"~getNamespace()~"'" : "")
                   ~(" (position:"~ getPositionDescription())~")");
       }
    }


    /**
    * Skip sub tree that is currently parser positioned on.
    * <br>NOTE: parser must be on START_TAG and when function returns
    * parser will be positioned on corresponding END_TAG
    */
    public void skipSubTree()
       /* throws XmlPullParserException, IOException */
    {
       require(START_TAG, null, null);
       int level = 1;
       while(level > 0) {
           int eventType = next();
           if(eventType == END_TAG) {
               --level;
           } else if(eventType == START_TAG) {
               ++level;
           }
       }
    }

    //    public char[] readText() /* throws XmlPullParserException, IOException */
    //    {
    //        if (getEventType() != TEXT) return "";
    //        char[] result = getText();
    //        next();
    //        return result;
    //    }

    public char[] nextText() /* throws XmlPullParserException, IOException */
    {
       //        char[] result = null;
       //        boolean onStartTag = false;
       //        if(eventType == START_TAG) {
       //            onStartTag = true;
       //            next();
       //        }
       //        if(eventType == TEXT) {
       //            result = getText();
       //            next();
       //        } else if(onStartTag && eventType == END_TAG) {
       //            result = "";
       //        } else {
       //            throw new XmlPullParserException(
       //                "parser must be on START_TAG or TEXT to read text", this, null);
       //        }
       //        if(eventType != END_TAG) {
       //            throw new XmlPullParserException(
       //                "event TEXT it must be immediately followed by END_TAG", this, null);
       //        }
       //        return result;
       if(getEventType() != START_TAG) {
           throw new XmlPullParserException(
               "parser must be on START_TAG to read next text", this);
       }
       int eventType = next();
       if(eventType == TEXT) {
           char[] result = getText();
           eventType = next();
           if(eventType != END_TAG) {
               throw new XmlPullParserException(
                   "TEXT must be immediately followed by END_TAG and not "
                       ~TYPES[ getEventType() ], this);
           }
           return result;
       } else if(eventType == END_TAG) {
           return "";
       } else {
           throw new XmlPullParserException(
               "parser must be on START_TAG or TEXT to read text", this);
       }
    }

    public int nextTag() /* throws XmlPullParserException, IOException */
    {
       next();
       if(eventType == TEXT && isWhitespace()) {  // skip whitespace
           next();
       }
       if (eventType != START_TAG && eventType != END_TAG) {
           throw new XmlPullParserException("expected START_TAG or END_TAG not "
                                                ~TYPES[ getEventType() ], this);
       }
       return eventType;
    }

    public int next()
       /* throws XmlPullParserException, IOException */
    {
       tokenize = false;
       return nextImpl();
    }

    public int nextToken()
       /* throws XmlPullParserException, IOException */
    {
       tokenize = true;
       return nextImpl();
    }


    protected int nextImpl()
       /* throws XmlPullParserException, IOException */
    {
       text = null;
       pcEnd = pcStart = 0;
       usePC = false;
       bufStart = posEnd;
       if(pastEndTag) {
           pastEndTag = false;
           --depth;
           namespaceEnd = elNamespaceCount[ depth ]; // less namespaces available
       }
       if(emptyElementTag) {
           emptyElementTag = false;
           pastEndTag = true;
           return eventType = END_TAG;
       }

       // [1] document ::= prolog element Misc*
       if(depth > 0) {

           if(seenStartTag) {
               seenStartTag = false;
               return eventType = parseStartTag();
           }
           if(seenEndTag) {
               seenEndTag = false;
               return eventType = parseEndTag();
           }

           // ASSUMPTION: we are _on_ first character of content or markup!!!!
           // [43] content ::= CharData? ((element | Reference | CDSect | PI | Comment) CharData?)*
           char ch;
           if(seenMarkup) {  // we have read ahead ...
               seenMarkup = false;
               ch = '<';
           } else if(seenAmpersand) {
               seenAmpersand = false;
               ch = '&';
           } else {
               ch = more();
           }
           posStart = pos - 1; // VERY IMPORTANT: this is correct start of event!!!

           // when true there is some potential event TEXT to return - keep gathering
           boolean hadCharData = false;

           // when true TEXT data is not continual (like <![CDATA[text]]>) and requires PC merging
           boolean needsMerging = false;

           MAIN_LOOP:
           while(true) {
               // work on MARKUP
               if(ch == '<') {
                   if(hadCharData) {
                       //posEnd = pos - 1;
                       if(tokenize) {
                           seenMarkup = true;
                           return eventType = TEXT;
                       }
                   }
                   ch = more();
                   if(ch == '/') {
                       if(!tokenize && hadCharData) {
                           seenEndTag = true;
                           //posEnd = pos - 2;
                           return eventType = TEXT;
                       }
                       return eventType = parseEndTag();
                   } else if(ch == '!') {
                       ch = more();
                       if(ch == '-') {
                           // note: if(tokenize == false) posStart/End is NOT changed!!!!
                           parseComment();
                           if(tokenize) return eventType = COMMENT;
                           if( !usePC && hadCharData ) {
                               needsMerging = true;
                           } else {
                               posStart = pos;  //completely ignore comment
                           }
                       } else if(ch == '[') {
                           //posEnd = pos - 3;
                           // must remember previous posStart/End as it merges with content of CDATA
                           //int oldStart = posStart + bufAbsoluteStart;
                           //int oldEnd = posEnd + bufAbsoluteStart;
                           parseCDSect(hadCharData);
                           if(tokenize) return eventType = CDSECT;
                           int cdStart = posStart;
                           int cdEnd = posEnd;
                           int cdLen = cdEnd - cdStart;


                           if(cdLen > 0) { // was there anything inside CDATA section?
                               hadCharData = true;
                               if(!usePC) {
                                   needsMerging = true;
                               }
                           }

                           //                          posStart = oldStart;
                           //                          posEnd = oldEnd;
                           //                          if(cdLen > 0) { // was there anything inside CDATA section?
                           //                              if(hadCharData) {
                           //                                  // do merging if there was anything in CDSect!!!!
                           //                                  //                                    if(!usePC) {
                           //                                  //                                        // posEnd is correct already!!!
                           //                                  //                                        if(posEnd > posStart) {
                           //                                  //                                            joinPC();
                           //                                  //                                        } else {
                           //                                  //                                            usePC = true;
                           //                                  //                                            pcStart = pcEnd = 0;
                           //                                  //                                        }
                           //                                  //                                    }
                           //                                  //                                    if(pcEnd + cdLen >= pc.length) ensurePC(pcEnd + cdLen);
                           //                                  //                                    // copy [cdStart..cdEnd) into PC
                           //                                  //                                    System.arraycopy(buf, cdStart, pc, pcEnd, cdLen);
                           //                                  //                                    pcEnd += cdLen;
                           //                                  if(!usePC) {
                           //                                      needsMerging = true;
                           //                                      posStart = cdStart;
                           //                                      posEnd = cdEnd;
                           //                                  }
                           //                              } else {
                           //                                  if(!usePC) {
                           //                                      needsMerging = true;
                           //                                      posStart = cdStart;
                           //                                      posEnd = cdEnd;
                           //                                      hadCharData = true;
                           //                                  }
                           //                              }
                           //                              //hadCharData = true;
                           //                          } else {
                           //                              if( !usePC && hadCharData ) {
                           //                                  needsMerging = true;
                           //                              }
                           //                          }
                       } else {
                           throw new XmlPullParserException(
                               "unexpected character in markup "~printable(ch), this);
                       }
                   } else if(ch == '?') {
                       parsePI();
                       if(tokenize) return eventType = PROCESSING_INSTRUCTION;
                       if( !usePC && hadCharData ) {
                           needsMerging = true;
                       } else {
                           posStart = pos;  //completely ignore PI
                       }

                   } else if( isNameStartChar(ch) ) {
                       if(!tokenize && hadCharData) {
                           seenStartTag = true;
                           //posEnd = pos - 2;
                           return eventType = TEXT;
                       }
                       return eventType = parseStartTag();
                   } else {
                       throw new XmlPullParserException(
                           "unexpected character in markup "~printable(ch), this);
                   }
                   // do content compaction if it makes sense!!!!

               } else if(ch == '&') {
                   // work on ENTITTY
                   //posEnd = pos - 1;
                   if(tokenize && hadCharData) {
                       seenAmpersand = true;
                       return eventType = TEXT;
                   }
                   int oldStart = posStart + bufAbsoluteStart;
                   int oldEnd = posEnd + bufAbsoluteStart;
                   char[] resolvedEntity = parseEntityRef();
                   if(tokenize) return eventType = ENTITY_REF;
                   // check if replacement text can be resolved !!!
                   if(resolvedEntity == null) {
                       if(entityRefName == null) {
                           entityRefName = newString(buf, posStart, posEnd - posStart);
                       }
                       throw new XmlPullParserException(
                           "could not resolve entity named '"~printable(entityRefName)~"'",
                           this);
                   }
                   //int entStart = posStart;
                   //int entEnd = posEnd;
                   posStart = oldStart - bufAbsoluteStart;
                   posEnd = oldEnd - bufAbsoluteStart;
                   if(!usePC) {
                       if(hadCharData) {
                           joinPC(); // posEnd is already set correctly!!!
                           needsMerging = false;
                       } else {
                           usePC = true;
                           pcStart = pcEnd = 0;
                       }
                   }
                   //assert usePC == true;
                   // write into PC replacement text - do merge for replacement text!!!!
                   for (int i = 0; i < resolvedEntity.length; i++)
                   {
                       if(pcEnd >= pc.length) ensurePC(pcEnd);
                       pc[pcEnd++] = resolvedEntity[ i ];

                   }
                   hadCharData = true;
                   //assert needsMerging == false;
               } else {

                   if(needsMerging) {
                       //assert usePC == false;
                       joinPC();  // posEnd is already set correctly!!!
                       //posStart = pos  -  1;
                       needsMerging = false;
                   }


                   //no MARKUP not ENTITIES so work on character data ...



                   // [14] CharData ::=   [^<&]* - ([^<&]* ']]>' [^<&]*)


                   hadCharData = true;

                   boolean normalizedCR = false;
                   boolean normalizeInput = tokenize == false || roundtripSupported == false;
                   // use loop locality here!!!!
                   boolean seenBracket = false;
                   boolean seenBracketBracket = false;
                   do {

                       // check that ]]> does not show in
                       if(ch == ']') {
                           if(seenBracket) {
                               seenBracketBracket = true;
                           } else {
                               seenBracket = true;
                           }
                       } else if(seenBracketBracket && ch == '>') {
                           throw new XmlPullParserException(
                               "characters ]]> are not allowed in content", this);
                       } else {
                           if(seenBracket) {
                               seenBracketBracket = seenBracket = false;
                           }
                           // assert seenTwoBrackets == seenBracket == false;
                       }
                       if(normalizeInput) {
                           // deal with normalization issues ...
                           if(ch == '\r') {
                               normalizedCR = true;
                               posEnd = pos -1;
                               // posEnd is already is set
                               if(!usePC) {
                                   if(posEnd > posStart) {
                                       joinPC();
                                   } else {
                                       usePC = true;
                                       pcStart = pcEnd = 0;
                                   }
                               }
                               //assert usePC == true;
                               if(pcEnd >= pc.length) ensurePC(pcEnd);
                               pc[pcEnd++] = '\n';
                           } else if(ch == '\n') {
                               //   if(!usePC) {  joinPC(); } else { if(pcEnd >= pc.length) ensurePC(); }
                               if(!normalizedCR && usePC) {
                                   if(pcEnd >= pc.length) ensurePC(pcEnd);
                                   pc[pcEnd++] = '\n';
                               }
                               normalizedCR = false;
                           } else {
                               if(usePC) {
                                   if(pcEnd >= pc.length) ensurePC(pcEnd);
                                   pc[pcEnd++] = ch;
                               }
                               normalizedCR = false;
                           }
                       }

                       ch = more();
                   } while(ch != '<' && ch != '&');
                   posEnd = pos - 1;
                   continue MAIN_LOOP;  // skip ch = more() from below - we are alreayd ahead ...
               }
               ch = more();
           } // endless while(true)
       } else {
           if(seenRoot) {
               return parseEpilog();
           } else {
               return parseProlog();
           }
       }
    }


    protected int parseProlog()
       /* throws XmlPullParserException, IOException */
    {
       // [2] prolog: ::= XMLDecl? Misc* (doctypedecl Misc*)? and look for [39] element

       char ch;
       if(seenMarkup) {
           ch = buf[ pos - 1 ];
       } else {
           ch = more();
       }

       /* some problem with UTF character below
       if(eventType == START_DOCUMENT) {
           // bootstrap parsing with getting first character input!
           // deal with BOM
           // detect BOM and drop it (Unicode int Order Mark)
           if(ch == '\uFFFE') {
               throw new XmlPullParserException(
                   "first character in input was UNICODE noncharacter (0xFFFE)"+
                       "- input requires int swapping", this, null);
           }
           if(ch == '\uFEFF') {
               // skipping UNICODE int Order Mark (so called BOM)
               ch = more();
           }
       }
       */
       seenMarkup = false;
       boolean gotS = false;
       posStart = pos - 1;
       boolean normalizeIgnorableWS = tokenize == true && roundtripSupported == false;
       boolean normalizedCR = false;
       while(true) {
           // deal with Misc
           // [27] Misc ::= Comment | PI | S
           // deal with docdecl --> mark it!
           // else parseStartTag seen <[^/]
           if(ch == '<') {
               if(gotS && tokenize) {
                   posEnd = pos - 1;
                   seenMarkup = true;
                   return eventType = IGNORABLE_WHITESPACE;
               }
               ch = more();
               if(ch == '?') {
                   // check if it is 'xml'
                   // deal with XMLDecl
                   if(parsePI()) {  // make sure to skip XMLDecl
                       if(tokenize) {
                           return eventType = PROCESSING_INSTRUCTION;
                       }
                   } else {
                       // skip over - continue tokenizing
                       posStart = pos;
                       gotS = false;
                   }

               } else if(ch == '!') {
                   ch = more();
                   if(ch == 'D') {
                       if(seenDocdecl) {
                           throw new XmlPullParserException(
                               "only one docdecl allowed in XML document", this);
                       }
                       seenDocdecl = true;
                       parseDocdecl();
                       if(tokenize) return eventType = DOCDECL;
                   } else if(ch == '-') {
                       parseComment();
                       if(tokenize) return eventType = COMMENT;
                   } else {
                       throw new XmlPullParserException(
                           "unexpected markup <!"~printable(ch), this);
                   }
               } else if(ch == '/') {
                   throw new XmlPullParserException(
                       "expected start tag name and not "~printable(ch), this);
               } else if(isNameStartChar(ch)) {
                   seenRoot = true;
                   return parseStartTag();
               } else {
                   throw new XmlPullParserException(
                       "expected start tag name and not "~printable(ch), this);
               }
           } else if(isS(ch)) {
               gotS = true;
               if(normalizeIgnorableWS) {
                   if(ch == '\r') {
                       normalizedCR = true;
                       //posEnd = pos -1;
                       //joinPC();
                       // posEnd is already is set
                       if(!usePC) {
                           posEnd = pos -1;
                           if(posEnd > posStart) {
                               joinPC();
                           } else {
                               usePC = true;
                               pcStart = pcEnd = 0;
                           }
                       }
                       //assert usePC == true;
                       if(pcEnd >= pc.length) ensurePC(pcEnd);
                       pc[pcEnd++] = '\n';
                   } else if(ch == '\n') {
                       if(!normalizedCR && usePC) {
                           if(pcEnd >= pc.length) ensurePC(pcEnd);
                           pc[pcEnd++] = '\n';
                       }
                       normalizedCR = false;
                   } else {
                       if(usePC) {
                           if(pcEnd >= pc.length) ensurePC(pcEnd);
                           pc[pcEnd++] = ch;
                       }
                       normalizedCR = false;
                   }
               }
           } else {
               throw new XmlPullParserException(
                   "only whitespace content allowed before start tag and not "~printable(ch),
                   this);
           }
           ch = more();
       }
    }

    protected int parseEpilog()
       /* throws XmlPullParserException, IOException */
    {
       if(eventType == END_DOCUMENT) {
           throw new XmlPullParserException("already reached end of XML input", this);
       }
       if(reachedEnd) {
           return eventType = END_DOCUMENT;
       }
       boolean gotS = false;
       boolean normalizeIgnorableWS = tokenize == true && roundtripSupported == false;
       boolean normalizedCR = false;
       try {
           // epilog: Misc*
           char ch;
           if(seenMarkup) {
               ch = buf[ pos - 1 ];
           } else {
               ch = more();
           }
           seenMarkup = false;
           posStart = pos - 1;
           if(!reachedEnd) {
               while(true) {
                   // deal with Misc
                   // [27] Misc ::= Comment | PI | S
                   if(ch == '<') {
                       if(gotS && tokenize) {
                           posEnd = pos - 1;
                           seenMarkup = true;
                           return eventType = IGNORABLE_WHITESPACE;
                       }
                       ch = more();
                       if(reachedEnd) {
                           break;
                       }
                       if(ch == '?') {
                           // check if it is 'xml'
                           // deal with XMLDecl
                           parsePI();
                           if(tokenize) return eventType = PROCESSING_INSTRUCTION;

                       } else if(ch == '!') {
                           ch = more();
                           if(reachedEnd) {
                               break;
                           }
                           if(ch == 'D') {
                               parseDocdecl(); //FIXME
                               if(tokenize) return eventType = DOCDECL;
                           } else if(ch == '-') {
                               parseComment();
                               if(tokenize) return eventType = COMMENT;
                           } else {
                               throw new XmlPullParserException(
                                   "unexpected markup <!"~printable(ch), this);
                           }
                       } else if(ch == '/') {
                           throw new XmlPullParserException(
                               "end tag not allowed in epilog but got "~printable(ch), this);
                       } else if(isNameStartChar(ch)) {
                           throw new XmlPullParserException(
                               "start tag not allowed in epilog but got "~printable(ch), this);
                       } else {
                           throw new XmlPullParserException(
                               "in epilog expected ignorable content and not "~printable(ch),
                               this);
                       }
                   } else if(isS(ch)) {
                       gotS = true;
                       if(normalizeIgnorableWS) {
                           if(ch == '\r') {
                               normalizedCR = true;
                               //posEnd = pos -1;
                               //joinPC();
                               // posEnd is alreadys set
                               if(!usePC) {
                                   posEnd = pos -1;
                                   if(posEnd > posStart) {
                                       joinPC();
                                   } else {
                                       usePC = true;
                                       pcStart = pcEnd = 0;
                                   }
                               }
                               //assert usePC == true;
                               if(pcEnd >= pc.length) ensurePC(pcEnd);
                               pc[pcEnd++] = '\n';
                           } else if(ch == '\n') {
                               if(!normalizedCR && usePC) {
                                   if(pcEnd >= pc.length) ensurePC(pcEnd);
                                   pc[pcEnd++] = '\n';
                               }
                               normalizedCR = false;
                           } else {
                               if(usePC) {
                                   if(pcEnd >= pc.length) ensurePC(pcEnd);
                                   pc[pcEnd++] = ch;
                               }
                               normalizedCR = false;
                           }
                       }
                   } else {
                       throw new XmlPullParserException(
                           "in epilog non whitespace content is not allowed but got "~printable(ch),
                           this);
                   }
                   ch = more();
                   if(reachedEnd) {
                       break;
                   }

               }
           }

           // throw Exception("unexpected content in epilog
           // catch IOException return END_DOCUEMENT
           //try {
       } catch(IOException ex) {
           reachedEnd = true;
       }
       if(reachedEnd) {
           if(tokenize && gotS) {
               posEnd = pos; // well - this is LAST available character pos
               return eventType = IGNORABLE_WHITESPACE;
           }
           return eventType = END_DOCUMENT;
       } else {
           throw new XmlPullParserException("internal error in parseEpilog");
       }
    }


    public int parseEndTag() /* throws XmlPullParserException, IOException */ {
       //ASSUMPTION ch is past "</"
       // [42] ETag ::=  '</' Name S? '>'
       char ch = more();
       if(!isNameStartChar(ch)) {
           throw new XmlPullParserException(
               "expected name start and not "~printable(ch), this);
       }
       posStart = pos - 3;
       int nameStart = pos - 1 + bufAbsoluteStart;
       do {
           ch = more();
       } while(isNameChar(ch));

       // now we go one level down -- do checks
       //--depth;  //FIXME

       // check that end tag name is the same as start tag
       //char[] name = new char[](buf, nameStart - bufAbsoluteStart,
       //                           (pos - 1) - (nameStart - bufAbsoluteStart));
       //int last = pos - 1;
       int off = nameStart - bufAbsoluteStart;
       //int len = last - off;
       int len = (pos - 1) - off;
       char[] cbuf = elRawName[depth];
       if(elRawNameEnd[depth] != len) {
           // construct strings for exception
           char[] startname = cbuf[0 .. elRawNameEnd[depth]];
           char[] endname = buf[off .. off+len];
           throw new XmlPullParserException(
               sprint.format("end tag name </{}> must match start tag name <{}> from line {}", endname, startname, elRawNameLine[depth]), this);
       }
       for (int i = 0; i < len; i++)
       {
           if(buf[off++] != cbuf[i]) {
               // construct strings for exception
               char[] startname = cbuf[0 .. len];
               char[] endname = buf[off - i - 1 .. off-i-1+len];
               throw new XmlPullParserException(
                   sprint.format("end tag name </{}> must match start tag name <{}> from line {}", endname, startname, elRawNameLine[depth]), this);
           }
       }

       while(isS(ch)) { ch = more(); } // skip additional white spaces
       if(ch != '>') {
           throw new XmlPullParserException(
               sprint.format("expected > to finish end tag not {} from line {}", printable(ch), elRawNameLine[depth]), this);
       }


       //namespaceEnd = elNamespaceCount[ depth ]; //FIXME

       posEnd = pos;
       pastEndTag = true;
       return eventType = END_TAG;
    }

    public int parseStartTag() /* throws XmlPullParserException, IOException */ {
       //ASSUMPTION ch is past <T
       // [40] STag ::=  '<' Name (S Attribute)* S? '>'
       // [44] EmptyElemTag ::= '<' Name (S Attribute)* S? '/>'
       ++depth; //FIXME

       posStart = pos - 2;

       emptyElementTag = false;
       attributeCount = 0;
       // retrieve name
       int nameStart = pos - 1 + bufAbsoluteStart;
       int colonPos = -1;
       char ch = buf[ pos - 1];
       if(ch == ':' && processNamespaces) throw new XmlPullParserException(
               "when namespaces processing enabled colon can not be at element name start",
               this);
       while(true) {
           ch = more();
           if(!isNameChar(ch)) break;
           if(ch == ':' && processNamespaces) {
               if(colonPos != -1) throw new XmlPullParserException(
                       "only one colon is allowed in name of element when namespaces are enabled",
                       this);
               colonPos = pos - 1 + bufAbsoluteStart;
           }
       }

       // retrieve name
       ensureElementsCapacity();


       //TODO check for efficient interning and then use elRawNameInterned!!!!

       int elLen = (pos - 1) - (nameStart - bufAbsoluteStart);
       if(elRawName[ depth ].length < elLen) {
           elRawName[ depth ].length = 2 * elLen;
       }
       elRawName[depth] = buf[nameStart - bufAbsoluteStart .. nameStart - bufAbsoluteStart + elLen];
       elRawNameEnd[ depth ] = elLen;
       elRawNameLine[ depth ] = lineNumber;

       char[] name = null;

       // work on prefixes and namespace URI
       char[] prefix = null;
       if(processNamespaces) {
           if(colonPos != -1) {
               prefix = elPrefix[ depth ] = newString(buf, nameStart - bufAbsoluteStart,
                                                      colonPos - nameStart);
               name = elName[ depth ] = newString(buf, colonPos + 1 - bufAbsoluteStart,
                                                  //(pos -1) - (colonPos + 1));
                                                  pos - 2 - (colonPos - bufAbsoluteStart));
           } else {
               prefix = elPrefix[ depth ] = null;
               name = elName[ depth ] = newString(buf, nameStart - bufAbsoluteStart, elLen);
           }
       } else {

           name = elName[ depth ] = newString(buf, nameStart - bufAbsoluteStart, elLen);

       }


       while(true) {

           while(isS(ch)) { ch = more(); } // skip additional white spaces

           if(ch == '>') {
               break;
           } else if(ch == '/') {
               if(emptyElementTag) throw new XmlPullParserException(
                       "repeated / in tag declaration", this);
               emptyElementTag = true;
               ch = more();
               if(ch != '>') throw new XmlPullParserException(
                       "expected > to end empty tag not "~printable(ch), this);
               break;
           } else if(isNameStartChar(ch)) {
               ch = parseAttribute();
               ch = more();
               continue;
           } else {
               throw new XmlPullParserException(
                   "start tag unexpected character "~printable(ch), this);
           }
           //ch = more(); // skip space
       }

       // now when namespaces were declared we can resolve them
       if(processNamespaces) {
           char[] uri = getNamespace(prefix);
           if(uri == null) {
               if(prefix == null) { // no prefix and no uri => use default namespace
                   uri = NO_NAMESPACE;
               } else {
                   throw new XmlPullParserException(
                       "could not determine namespace bound to element prefix "~prefix,
                       this);
               }

           }
           elUri[ depth ] = uri;


           //char[] uri = getNamespace(prefix);
           //if(uri == null && prefix == null) { // no prefix and no uri => use default namespace
           //  uri = "";
           //}
           // resolve attribute namespaces
           for (int i = 0; i < attributeCount; i++)
           {
               char[] attrPrefix = attributePrefix[ i ];
               if(attrPrefix != null) {
                   char[] attrUri = getNamespace(attrPrefix);
                   if(attrUri == null) {
                       throw new XmlPullParserException(
                           "could not determine namespace bound to attribute prefix "~attrPrefix,
                           this);

                   }
                   attributeUri[ i ] = attrUri;
               } else {
                   attributeUri[ i ] = NO_NAMESPACE;
               }
           }

           //TODO
           //[ WFC: Unique Att Spec ]
           // check attribute uniqueness constraint for attributes that has namespace!!!

           for (int i = 1; i < attributeCount; i++)
           {
               for (int j = 0; j < i; j++)
               {
                   if( attributeUri[j] == attributeUri[i]
                          && (allStringsInterned && attributeName[j] == attributeName[i]
                                  || (!allStringsInterned
                                          && attributeNameHash[ j ] == attributeNameHash[ i ]
                                          && attributeName[j] == attributeName[i]) )

                     ) {
                       // prepare data for nice error message?
                       char[] attr1 = attributeName[j];
                       if(attributeUri[j] != null) attr1 = attributeUri[j]~":"~attr1;
                       char[] attr2 = attributeName[i];
                       if(attributeUri[i] != null) attr2 = attributeUri[i]~":"~attr2;
                       throw new XmlPullParserException(
                           "duplicated attributes "~attr1~" and "~attr2, this);
                   }
               }
           }


       } else { // ! processNamespaces

           //[ WFC: Unique Att Spec ]
           // check raw attribute uniqueness constraint!!!
           for (int i = 1; i < attributeCount; i++)
           {
               for (int j = 0; j < i; j++)
               {
                   if((allStringsInterned && attributeName[j] == attributeName[i]
                           || (!allStringsInterned
                                   && attributeNameHash[ j ] == attributeNameHash[ i ]
                                   && attributeName[j] == attributeName[i]) )

                     ) {
                       // prepare data for nice error message?
                       char[] attr1 = attributeName[j];
                       char[] attr2 = attributeName[i];
                       throw new XmlPullParserException(
                           "duplicated attributes "~attr1~" and "~attr2, this);
                   }
               }
           }
       }

       elNamespaceCount[ depth ] = namespaceEnd;
       posEnd = pos;
       return eventType = START_TAG;
    }

    protected char parseAttribute() /* throws XmlPullParserException, IOException */
    {
       // parse attribute
       // [41] Attribute ::= Name Eq AttValue
       // [WFC: No External Entity References]
       // [WFC: No < in Attribute Values]
       int prevPosStart = posStart + bufAbsoluteStart;
       int nameStart = pos - 1 + bufAbsoluteStart;
       int colonPos = -1;
       char ch = buf[ pos - 1 ];
       if(ch == ':' && processNamespaces) throw new XmlPullParserException(
               "when namespaces processing enabled colon can not be at attribute name start",
               this);


       boolean startsWithXmlns = processNamespaces && ch == 'x';
       int xmlnsPos = 0;

       ch = more();
       while(isNameChar(ch)) {
           if(processNamespaces) {
               if(startsWithXmlns && xmlnsPos < 5) {
                   ++xmlnsPos;
                   if(xmlnsPos == 1) { if(ch != 'm') startsWithXmlns = false; }
                   else if(xmlnsPos == 2) { if(ch != 'l') startsWithXmlns = false; }
                   else if(xmlnsPos == 3) { if(ch != 'n') startsWithXmlns = false; }
                   else if(xmlnsPos == 4) { if(ch != 's') startsWithXmlns = false; }
                   else if(xmlnsPos == 5) {
                       if(ch != ':') throw new XmlPullParserException(
                               "after xmlns in attribute name must be colon when namespaces are enabled", this);
                       //colonPos = pos - 1 + bufAbsoluteStart;
                   }
               }
               if(ch == ':') {
                   if(colonPos != -1) throw new XmlPullParserException(
                           "only one colon is allowed in attribute name when namespaces are enabled", this);
                   colonPos = pos - 1 + bufAbsoluteStart;
               }
           }
           ch = more();
       }

       ensureAttributesCapacity(attributeCount);

       // --- start processing attributes
       char[] name = null;
       char[] prefix = null;
       // work on prefixes and namespace URI
       if(processNamespaces) {
           if(xmlnsPos < 4) startsWithXmlns = false;
           if(startsWithXmlns) {
               if(colonPos != -1) {
                   //prefix = attributePrefix[ attributeCount ] = null;
                   int nameLen = pos - 2 - (colonPos - bufAbsoluteStart);
                   if(nameLen == 0) {
                       throw new XmlPullParserException(
                           "namespace prefix is required after xmlns:  when namespaces are enabled", this);
                   }
                   name = //attributeName[ attributeCount ] =
                       newString(buf, colonPos - bufAbsoluteStart + 1, nameLen);
                   //pos - 1 - (colonPos + 1 - bufAbsoluteStart)
               }
           } else {
               if(colonPos != -1) {
                   int prefixLen = colonPos - nameStart;
                   prefix = attributePrefix[ attributeCount ] =
                       newString(buf, nameStart - bufAbsoluteStart,prefixLen);
                   //colonPos - (nameStart - bufAbsoluteStart));
                   int nameLen = pos - 2 - (colonPos - bufAbsoluteStart);
                   name = attributeName[ attributeCount ] =
                       newString(buf, colonPos - bufAbsoluteStart + 1, nameLen);
                   //pos - 1 - (colonPos + 1 - bufAbsoluteStart));

                   //name.substring(0, colonPos-nameStart);
               } else {
                   prefix = attributePrefix[ attributeCount ]  = null;
                   name = attributeName[ attributeCount ] =
                       newString(buf, nameStart - bufAbsoluteStart,
                                 pos - 1 - (nameStart - bufAbsoluteStart));
               }
               if(!allStringsInterned) {
                   attributeNameHash[ attributeCount ] = fastHash(name);
               }
           }

       } else {
           // retrieve name
           name = attributeName[ attributeCount ] =
               newString(buf, nameStart - bufAbsoluteStart,
                         pos - 1 - (nameStart - bufAbsoluteStart));
           ////assert name != null;
           if(!allStringsInterned) {
               attributeNameHash[ attributeCount ] = fastHash(name);
           }
       }

       // [25] Eq ::=  S? '=' S?
       while(isS(ch)) { ch = more(); } // skip additional spaces
       if(ch != '=') throw new XmlPullParserException(
               "expected = after attribute name", this);
       ch = more();
       while(isS(ch)) { ch = more(); } // skip additional spaces

       // [10] AttValue ::=   '"' ([^<&"] | Reference)* '"'
       //                  |  "'" ([^<&'] | Reference)* "'"
       char delimit = ch;
       if(delimit != '"' && delimit != '\'') throw new XmlPullParserException(
               "attribute value must start with quotation or apostrophe not "
                   ~printable(delimit), this);
       // parse until delimit or < and resolve Reference
       //[67] Reference ::= EntityRef | CharRef
       //int valueStart = pos + bufAbsoluteStart;


       boolean normalizedCR = false;
       usePC = false;
       pcStart = pcEnd;
       posStart = pos;

       while(true) {
           ch = more();
           if(ch == delimit) {
               break;
           } if(ch == '<') {
               throw new XmlPullParserException(
                   "markup not allowed inside attribute value - illegal < ", this);
           } if(ch == '&') {
               // extractEntityRef
               posEnd = pos - 1;
               if(!usePC) {
                   boolean hadCharData = posEnd > posStart;
                   if(hadCharData) {
                       // posEnd is already set correctly!!!
                       joinPC();
                   } else {
                       usePC = true;
                       pcStart = pcEnd = 0;
                   }
               }
               //assert usePC == true;

               char[] resolvedEntity = parseEntityRef();
               // check if replacement text can be resolved !!!
               if(resolvedEntity == null) {
                   if(entityRefName == null) {
                       entityRefName = newString(buf, posStart, posEnd - posStart);
                   }
                   throw new XmlPullParserException(
                       "could not resolve entity named '"~printable(entityRefName)~"'",
                       this);
               }
               // write into PC replacement text - do merge for replacement text!!!!
               for (int i = 0; i < resolvedEntity.length; i++)
               {
                   if(pcEnd >= pc.length) ensurePC(pcEnd);
                   pc[pcEnd++] = resolvedEntity[ i ];
               }
           } else if(ch == '\t' || ch == '\n' || ch == '\r') {
               // do attribute value normalization
               // as described in http://www.w3.org/TR/REC-xml#AVNormalize
               // TODO add test for it form spec ...
               // handle EOL normalization ...
               if(!usePC) {
                   posEnd = pos - 1;
                   if(posEnd > posStart) {
                       joinPC();
                   } else {
                       usePC = true;
                       pcEnd = pcStart = 0;
                   }
               }
               //assert usePC == true;
               if(pcEnd >= pc.length) ensurePC(pcEnd);
               if(ch != '\n' || !normalizedCR) {
                   pc[pcEnd++] = ' '; //'\n';
               }

           } else {
               if(usePC) {
                   if(pcEnd >= pc.length) ensurePC(pcEnd);
                   pc[pcEnd++] = ch;
               }
           }
           normalizedCR = ch == '\r';
       }


       if(processNamespaces && startsWithXmlns) {
           char[] ns = null;
           if(!usePC) {
               ns = newStringIntern(buf, posStart, pos - 1 - posStart);
           } else {
               ns = newStringIntern(pc, pcStart, pcEnd - pcStart);
           }
           ensureNamespacesCapacity(namespaceEnd);
           int prefixHash = -1;
           if(colonPos != -1) {
               if(ns.length == 0) {
                   throw new XmlPullParserException(
                       "non-default namespace can not be declared to be empty string", this);
               }
               // declare new namespace
               namespacePrefix[ namespaceEnd ] = name;
               if(!allStringsInterned) {
                   prefixHash = namespacePrefixHash[ namespaceEnd ] = fastHash(name);
               }
           } else {
               // declare  new default namespace ...
               namespacePrefix[ namespaceEnd ] = null; //""; //null; //TODO check FIXME Alek
               if(!allStringsInterned) {
                   prefixHash = namespacePrefixHash[ namespaceEnd ] = -1;
               }
           }
           namespaceUri[ namespaceEnd ] = ns;

           // detect duplicate namespace declarations!!!
           int startNs = elNamespaceCount[ depth - 1 ];
           for (int i = namespaceEnd - 1; i >= startNs; --i)
           {
               if(((allStringsInterned || name == null) && namespacePrefix[ i ] == name)
                      || (!allStringsInterned && name != null &&
                              namespacePrefixHash[ i ] == prefixHash
                              && name == namespacePrefix[ i ]
                         ))
               {
                   char[] s = name == null ? "default" : "'"~name~"'";
                   throw new XmlPullParserException(
                       "duplicated namespace declaration for "~s~" prefix", this);
               }
           }

           ++namespaceEnd;

       } else {
           if(!usePC) {
               attributeValue[ attributeCount ] =
                   buf[posStart .. pos - 1].dup;
           } else {
               attributeValue[ attributeCount ] =
                   pc[pcStart .. pcEnd].dup;
           }
           ++attributeCount;
       }
       posStart = prevPosStart - bufAbsoluteStart;
       return ch;
    }

    protected char[] charRefOneCharBuf;

    protected char[] parseEntityRef()
       /* throws XmlPullParserException, IOException */
    {
       // entity reference http://www.w3.org/TR/2000/REC-xml-20001006#NT-Reference
       // [67] Reference          ::=          EntityRef | CharRef

       // ASSUMPTION just after &
       entityRefName = null;
       posStart = pos;
       char ch = more();
       if(ch == '#') {
           // parse character reference
           char charRef = 0;
           ch = more();
           if(ch == 'x') {
               //encoded in hex
               while(true) {
                   ch = more();
                   if(ch >= '0' && ch <= '9') {
                       charRef = cast(char)(charRef * 16 + (ch - '0'));
                   } else if(ch >= 'a' && ch <= 'f') {
                       charRef = cast(char)(charRef * 16 + (ch - ('a' - 10)));
                   } else if(ch >= 'A' && ch <= 'F') {
                       charRef = cast(char)(charRef * 16 + (ch - ('A' - 10)));
                   } else if(ch == ';') {
                       break;
                   } else {
                       throw new XmlPullParserException(
                           "character reference (with hex value) may not contain "
                               ~printable(ch), this);
                   }
               }
           } else {
               // encoded in decimal
               while(true) {
                   if(ch >= '0' && ch <= '9') {
                       charRef = cast(char)(charRef * 10 + (ch - '0'));
                   } else if(ch == ';') {
                       break;
                   } else {
                       throw new XmlPullParserException(
                           "character reference (with decimal value) may not contain "
                               ~printable(ch), this);
                   }
                   ch = more();
               }
           }
           posEnd = pos - 1;
           charRefOneCharBuf[0] = charRef;
           if(tokenize) {
               text = newString(charRefOneCharBuf, 0, 1);
           }
           return charRefOneCharBuf;
       } else {
           // [68]     EntityRef          ::=          '&' Name ';'
           // scan name until ;
           if(!isNameStartChar(ch)) {
               throw new XmlPullParserException(
                   "entity reference names can not start with character '"
                       ~printable(ch)~"'", this);
           }
           while(true) {
               ch = more();
               if(ch == ';') {
                   break;
               }
               if(!isNameChar(ch)) {
                   throw new XmlPullParserException(
                       "entity reference name can not contain character "
                           ~printable(ch)~"'", this);
               }
           }
           posEnd = pos - 1;
           // determine what name maps to
           int len = posEnd - posStart;
           if(len == 2 && buf[posStart] == 'l' && buf[posStart+1] == 't') {
               if(tokenize) {
                   text = "<";
               }
               charRefOneCharBuf[0] = '<';
               return charRefOneCharBuf;
               //if(paramPC || isParserTokenizing) {
               //    if(pcEnd >= pc.length) ensurePC();
               //   pc[pcEnd++] = '<';
               //}
           } else if(len == 3 && buf[posStart] == 'a'
                         && buf[posStart+1] == 'm' && buf[posStart+2] == 'p') {
               if(tokenize) {
                   text = "&";
               }
               charRefOneCharBuf[0] = '&';
               return charRefOneCharBuf;
           } else if(len == 2 && buf[posStart] == 'g' && buf[posStart+1] == 't') {
               if(tokenize) {
                   text = ">";
               }
               charRefOneCharBuf[0] = '>';
               return charRefOneCharBuf;
           } else if(len == 4 && buf[posStart] == 'a' && buf[posStart+1] == 'p'
                         && buf[posStart+2] == 'o' && buf[posStart+3] == 's')
           {
               if(tokenize) {
                   text = "'";
               }
               charRefOneCharBuf[0] = '\'';
               return charRefOneCharBuf;
           } else if(len == 4 && buf[posStart] == 'q' && buf[posStart+1] == 'u'
                         && buf[posStart+2] == 'o' && buf[posStart+3] == 't')
           {
               if(tokenize) {
                   text = "\"";
               }
               charRefOneCharBuf[0] = '"';
               return charRefOneCharBuf;
           } else {
               char[] result = lookuEntityReplacement(len);
               if(result != null) {
                   return result;
               }
           }
           if(tokenize) text = null;
           return null;
       }
    }

    protected char[] lookuEntityReplacement(int entitNameLen)
       /* throws XmlPullParserException, IOException */

    {
       if(!allStringsInterned) {
           int hash = fastHash(buf, posStart, posEnd - posStart);
           LOOP:
           for (int i = entityEnd - 1; i >= 0; --i)
           {
               if(hash == entityNameHash[ i ] && entitNameLen == entityNameBuf[ i ].length) {
                   char[] entityBuf = entityNameBuf[ i ];
                   for (int j = 0; j < entitNameLen; j++)
                   {
                       if(buf[posStart + j] != entityBuf[j]) continue LOOP;
                   }
                   if(tokenize) text = entityReplacement[ i ];
                   return entityReplacementBuf[ i ];
               }
           }
       } else {
           entityRefName = newString(buf, posStart, posEnd - posStart);
           for (int i = entityEnd - 1; i >= 0; --i)
           {
               // take advantage that interning for newStirng is enforced
               if(entityRefName == entityName[ i ]) {
                   if(tokenize) text = entityReplacement[ i ];
                   return entityReplacementBuf[ i ];
               }
           }
       }
       return null;
    }


    protected void parseComment()
       /* throws XmlPullParserException, IOException */
    {
       // implements XML 1.0 Section 2.5 Comments

       //ASSUMPTION: seen <!-
       char ch = more();
       if(ch != '-') throw new XmlPullParserException(
               "expected <!-- for comment start", this);
       if(tokenize) posStart = pos;

       int curLine = lineNumber;
       int curColumn = columnNumber;
       try {
           boolean normalizeIgnorableWS = tokenize == true && roundtripSupported == false;
           boolean normalizedCR = false;

           boolean seenDash = false;
           boolean seenDashDash = false;
           while(true) {
               // scan until it hits -->
               ch = more();
               if(seenDashDash && ch != '>') {
                   throw new XmlPullParserException(
                       "in comment after two dashes (--) next character must be > not "~printable(ch), this);
               }
               if(ch == '-') {
                   if(!seenDash) {
                       seenDash = true;
                   } else {
                       seenDashDash = true;
                       seenDash = false;
                   }
               } else if(ch == '>') {
                   if(seenDashDash) {
                       break;  // found end sequence!!!!
                   } else {
                       seenDashDash = false;
                   }
                   seenDash = false;
               } else {
                   seenDash = false;
               }
               if(normalizeIgnorableWS) {
                   if(ch == '\r') {
                       normalizedCR = true;
                       //posEnd = pos -1;
                       //joinPC();
                       // posEnd is already set
                       if(!usePC) {
                           posEnd = pos -1;
                           if(posEnd > posStart) {
                               joinPC();
                           } else {
                               usePC = true;
                               pcStart = pcEnd = 0;
                           }
                       }
                       //assert usePC == true;
                       if(pcEnd >= pc.length) ensurePC(pcEnd);
                       pc[pcEnd++] = '\n';
                   } else if(ch == '\n') {
                       if(!normalizedCR && usePC) {
                           if(pcEnd >= pc.length) ensurePC(pcEnd);
                           pc[pcEnd++] = '\n';
                       }
                       normalizedCR = false;
                   } else {
                       if(usePC) {
                           if(pcEnd >= pc.length) ensurePC(pcEnd);
                           pc[pcEnd++] = ch;
                       }
                       normalizedCR = false;
                   }
               }
           }

       } catch(IOException ex) {
           // detect EOF and create meaningful error ...
           throw new XmlPullParserException(
               sprint.format("comment started on line {} and column {} was not closed", curLine, curColumn),
               this /*, ex */);
       }
       if(tokenize) {
           posEnd = pos - 3;
           if(usePC) {
               pcEnd -= 2;
           }
       }
    }

    protected boolean parsePI()
       /* throws XmlPullParserException, IOException */
    {
       // implements XML 1.0 Section 2.6 Processing Instructions

       // [16] PI ::= '<?' PITarget (S (Char* - (Char* '?>' Char*)))? '?>'
       // [17] PITarget         ::=    Name - (('X' | 'x') ('M' | 'm') ('L' | 'l'))
       //ASSUMPTION: seen <?
       if(tokenize) posStart = pos;
       int curLine = lineNumber;
       int curColumn = columnNumber;
       int piTargetStart = pos + bufAbsoluteStart;
       int piTargetEnd = -1;
       boolean normalizeIgnorableWS = tokenize == true && roundtripSupported == false;
       boolean normalizedCR = false;

       try {
           boolean seenQ = false;
           char ch = more();
           if(isS(ch)) {
               throw new XmlPullParserException(
                   "processing instruction PITarget must be exactly after <? and not white space character",
                   this);
           }
           while(true) {
               // scan until it hits ?>
               //ch = more();

               if(ch == '?') {
                   seenQ = true;
               } else if(ch == '>') {
                   if(seenQ) {
                       break;  // found end sequence!!!!
                   }
                   seenQ = false;
               } else {
                   if(piTargetEnd == -1 && isS(ch)) {
                       piTargetEnd = pos - 1 + bufAbsoluteStart;

                       // [17] PITarget ::= Name - (('X' | 'x') ('M' | 'm') ('L' | 'l'))
                       if((piTargetEnd - piTargetStart) == 3) {
                           if((buf[piTargetStart] == 'x' || buf[piTargetStart] == 'X')
                                  && (buf[piTargetStart+1] == 'm' || buf[piTargetStart+1] == 'M')
                                  && (buf[piTargetStart+2] == 'l' || buf[piTargetStart+2] == 'L')
                             )
                           {
                               if(piTargetStart > 3) {  //<?xml is allowed as first characters in input ...
                                   throw new XmlPullParserException(
                                       "processing instruction can not have PITarget with reserveld xml name",
                                       this);
                               } else {
                                   if(buf[piTargetStart] != 'x'
                                          && buf[piTargetStart+1] != 'm'
                                          && buf[piTargetStart+2] != 'l')
                                   {
                                       throw new XmlPullParserException(
                                           "XMLDecl must have xml name in lowercase",
                                           this);
                                   }
                               }
                               parseXmlDecl(ch);
                               if(tokenize) posEnd = pos - 2;
                               int off = piTargetStart - bufAbsoluteStart + 3;
                               int len = pos - 2 - off;
                               xmlDeclContent = newString(buf, off, len);
                               return false;
                           }
                       }
                   }
                   seenQ = false;
               }
               if(normalizeIgnorableWS) {
                   if(ch == '\r') {
                       normalizedCR = true;
                       //posEnd = pos -1;
                       //joinPC();
                       // posEnd is already set
                       if(!usePC) {
                           posEnd = pos -1;
                           if(posEnd > posStart) {
                               joinPC();
                           } else {
                               usePC = true;
                               pcStart = pcEnd = 0;
                           }
                       }
                       //assert usePC == true;
                       if(pcEnd >= pc.length) ensurePC(pcEnd);
                       pc[pcEnd++] = '\n';
                   } else if(ch == '\n') {
                       if(!normalizedCR && usePC) {
                           if(pcEnd >= pc.length) ensurePC(pcEnd);
                           pc[pcEnd++] = '\n';
                       }
                       normalizedCR = false;
                   } else {
                       if(usePC) {
                           if(pcEnd >= pc.length) ensurePC(pcEnd);
                           pc[pcEnd++] = ch;
                       }
                       normalizedCR = false;
                   }
               }
               ch = more();
           }
       } catch(IOException ex) {
           // detect EOF and create meaningful error ...
           throw new XmlPullParserException(
               sprint.format("processing instruction started on line {} and column {} was not closed", curLine, curColumn),
               this /*, ex */);
       }
       if(piTargetEnd == -1) {
           piTargetEnd = pos - 2 + bufAbsoluteStart;
           //throw new XmlPullParserException(
           //    "processing instruction must have PITarget name", this);
       }
       piTargetStart -= bufAbsoluteStart;
       piTargetEnd -= bufAbsoluteStart;
       if(tokenize) {
           posEnd = pos - 2;
           if(normalizeIgnorableWS) {
               --pcEnd;
           }
       }
       return true;
    }

    //    protected final static char[] VERSION = {'v','e','r','s','i','o','n'};
    //    protected final static char[] NCODING = {'n','c','o','d','i','n','g'};
    //    protected final static char[] TANDALONE = {'t','a','n','d','a','l','o','n','e'};
    //    protected final static char[] YES = {'y','e','s'};
    //    protected final static char[] NO = {'n','o'};

    protected final static char[] VERSION = "version";
    protected final static char[] NCODING = "ncoding";
    protected final static char[] TANDALONE = "tandalone";
    protected final static char[] YES = "yes";
    protected final static char[] NO = "no";



    protected void parseXmlDecl(char ch)
       /* throws XmlPullParserException, IOException */
    {
       // [23] XMLDecl ::= '<?xml' VersionInfo EncodingDecl? SDDecl? S? '?>'

       // first make sure that relative positions will stay OK
       preventBufferCompaction = true;
       bufStart = 0; // necessary to keep pos unchanged during expansion!

       // --- parse VersionInfo

       // [24] VersionInfo ::= S 'version' Eq ("'" VersionNum "'" | '"' VersionNum '"')
       // parse is positioned just on first S past <?xml
       ch = skipS(ch);
       ch = requireInput(ch, VERSION);
       // [25] Eq ::= S? '=' S?
       ch = skipS(ch);
       if(ch != '=') {
           throw new XmlPullParserException(
               "expected equals sign (=) after version and not "~printable(ch), this);
       }
       ch = more();
       ch = skipS(ch);
       if(ch != '\'' && ch != '"') {
           throw new XmlPullParserException(
               "expected apostrophe (') or quotation mark (\") after version and not "
                   ~printable(ch), this);
       }
       char quotChar = ch;
       //int versionStart = pos + bufAbsoluteStart;  // required if preventBufferCompaction==false
       int versionStart = pos;
       ch = more();
       // [26] VersionNum ::= ([a-zA-Z0-9_.:] | '-')+
       while(ch != quotChar) {
           if((ch  < 'a' || ch > 'z') && (ch  < 'A' || ch > 'Z') && (ch  < '0' || ch > '9')
                  && ch != '_' && ch != '.' && ch != ':' && ch != '-')
           {
               throw new XmlPullParserException(
                   "<?xml version value expected to be in ([a-zA-Z0-9_.:] | '-') not "~printable(ch), this);
           }
           ch = more();
       }
       int versionEnd = pos - 1;
       parseXmlDeclWithVersion(versionStart, versionEnd);
       preventBufferCompaction = false; // alow again buffer commpaction - pos MAY chnage
    }
    //protected char[] xmlDeclVersion;

    protected void parseXmlDeclWithVersion(int versionStart, int versionEnd)
       /* throws XmlPullParserException, IOException */
    {
       char[] oldEncoding = this.inputEncoding;

       // check version is "1.0"
       if((versionEnd - versionStart != 3)
              || buf[versionStart] != '1'
              || buf[versionStart+1] != '.'
              || buf[versionStart+2] != '0')
       {
           throw new XmlPullParserException(
               "only 1.0 is supported as <?xml version not '"
                   ~printable(buf[versionStart .. versionEnd])~"'", this);
       }
       xmlDeclVersion = newString(buf, versionStart, versionEnd - versionStart);

       // [80] EncodingDecl ::= S 'encoding' Eq ('"' EncName '"' | "'" EncName "'" )
       char ch = more();
       ch = skipS(ch);
       if(ch == 'e') {
           ch = more();
           ch = requireInput(ch, NCODING);
           ch = skipS(ch);
           if(ch != '=') {
               throw new XmlPullParserException(
                   "expected equals sign (=) after encoding and not "~printable(ch), this);
           }
           ch = more();
           ch = skipS(ch);
           if(ch != '\'' && ch != '"') {
               throw new XmlPullParserException(
                   "expected apostrophe (') or quotation mark (\") after encoding and not "
                       ~printable(ch), this);
           }
           char quotChar = ch;
           int encodingStart = pos;
           ch = more();
           // [81] EncName ::= [A-Za-z] ([A-Za-z0-9._] | '-')*
           if((ch  < 'a' || ch > 'z') && (ch  < 'A' || ch > 'Z'))
           {
               throw new XmlPullParserException(
                   "<?xml encoding name expected to start with [A-Za-z] not "~printable(ch), this);
           }
           ch = more();
           while(ch != quotChar) {
               if((ch  < 'a' || ch > 'z') && (ch  < 'A' || ch > 'Z') && (ch  < '0' || ch > '9')
                      && ch != '.' && ch != '_' && ch != '-')
               {
                   throw new XmlPullParserException(
                       "<?xml encoding value expected to be in ([A-Za-z0-9._] | '-') not "~printable(ch), this);
               }
               ch = more();
           }
           int encodingEnd = pos - 1;


           // TODO reconcile with setInput encodingName
           inputEncoding = newString(buf, encodingStart, encodingEnd - encodingStart);
           ch = more();
       }

       ch = skipS(ch);
       // [32] SDDecl ::= S 'standalone' Eq (("'" ('yes' | 'no') "'") | ('"' ('yes' | 'no') '"'))
       if(ch == 's') {
           ch = more();
           ch = requireInput(ch, TANDALONE);
           ch = skipS(ch);
           if(ch != '=') {
               throw new XmlPullParserException(
                   "expected equals sign (=) after standalone and not "~printable(ch),
                   this);
           }
           ch = more();
           ch = skipS(ch);
           if(ch != '\'' && ch != '"') {
               throw new XmlPullParserException(
                   "expected apostrophe (') or quotation mark (\") after encoding and not "
                       ~printable(ch), this);
           }
           char quotChar = ch;
           int standaloneStart = pos;
           ch = more();
           if(ch == 'y') {
               ch = requireInput(ch, YES);
               //Boolean standalone = new Boolean(true);
               xmlDeclStandalone = true;
           } else if(ch == 'n') {
               ch = requireInput(ch, NO);
               //Boolean standalone = new Boolean(false);
               xmlDeclStandalone = false;
           } else {
               throw new XmlPullParserException(
                   "expected 'yes' or 'no' after standalone and not "
                       ~printable(ch), this);
           }
           if(ch != quotChar) {
               throw new XmlPullParserException(
                   "expected "~quotChar~" after standalone value not "
                       ~printable(ch), this);
           }
           ch = more();
       }


       ch = skipS(ch);
       if(ch != '?') {
           throw new XmlPullParserException(
               "expected ?> as last part of <?xml not "
                   ~printable(ch), this);
       }
       ch = more();
       if(ch != '>') {
           throw new XmlPullParserException(
               "expected ?> as last part of <?xml not "
                   ~printable(ch), this);
       }

    //NOTE: this code is broken as for some types of input streams (URLConnection ...)
    //it is not possible to do more than once new InputStreamReader(inputStream)
    //as it somehow detects it and closes undelrying inout stram (b.....d!)
    //In future one will need better low level byte-by-byte reading of prolog and then doing InputStream ...
    //for more details see http://www.extreme.indiana.edu/bugzilla/show_bug.cgi?id=135
       //        //reset input stream
    //   if ((this.inputEncoding != oldEncoding) && (this.inputStream != null)) {
    //       if ((this.inputEncoding != null) && (!this.inputEncoding.equalsIgnoreCase(oldEncoding))) {
    //           //              //there is need to reparse input to set location OK
    //           //              reset();
    //           this.reader = new InputStreamReader(this.inputStream, this.inputEncoding);
    //           //              //skip <?xml
    //           //              for (int i = 0; i < 5; i++){
    //           //                  ch=more();
    //           //              }
    //           //              parseXmlDecl(ch);
    //       }
    //   }
    }
    protected void parseDocdecl()
       /* throws XmlPullParserException, IOException */
    {
       //ASSUMPTION: seen <!D
       char ch = more();
       if(ch != 'O') throw new XmlPullParserException(
               "expected <!DOCTYPE", this);
       ch = more();
       if(ch != 'C') throw new XmlPullParserException(
               "expected <!DOCTYPE", this);
       ch = more();
       if(ch != 'T') throw new XmlPullParserException(
               "expected <!DOCTYPE", this);
       ch = more();
       if(ch != 'Y') throw new XmlPullParserException(
               "expected <!DOCTYPE", this);
       ch = more();
       if(ch != 'P') throw new XmlPullParserException(
               "expected <!DOCTYPE", this);
       ch = more();
       if(ch != 'E') throw new XmlPullParserException(
               "expected <!DOCTYPE", this);
       posStart = pos;
       // do simple and crude scanning for end of doctype

       // [28]  doctypedecl ::= '<!DOCTYPE' S Name (S ExternalID)? S? ('['
       //                      (markupdecl | DeclSep)* ']' S?)? '>'
       int bracketLevel = 0;
       boolean normalizeIgnorableWS = tokenize == true && roundtripSupported == false;
       boolean normalizedCR = false;
       while(true) {
           ch = more();
           if(ch == '[') ++bracketLevel;
           if(ch == ']') --bracketLevel;
           if(ch == '>' && bracketLevel == 0) break;
           if(normalizeIgnorableWS) {
               if(ch == '\r') {
                   normalizedCR = true;
                   //posEnd = pos -1;
                   //joinPC();
                   // posEnd is alreadys set
                   if(!usePC) {
                       posEnd = pos -1;
                       if(posEnd > posStart) {
                           joinPC();
                       } else {
                           usePC = true;
                           pcStart = pcEnd = 0;
                       }
                   }
                   //assert usePC == true;
                   if(pcEnd >= pc.length) ensurePC(pcEnd);
                   pc[pcEnd++] = '\n';
               } else if(ch == '\n') {
                   if(!normalizedCR && usePC) {
                       if(pcEnd >= pc.length) ensurePC(pcEnd);
                       pc[pcEnd++] = '\n';
                   }
                   normalizedCR = false;
               } else {
                   if(usePC) {
                       if(pcEnd >= pc.length) ensurePC(pcEnd);
                       pc[pcEnd++] = ch;
                   }
                   normalizedCR = false;
               }
           }

       }
       posEnd = pos - 1;
    }

    protected void parseCDSect(boolean hadCharData)
       /* throws XmlPullParserException, IOException */
    {
       // implements XML 1.0 Section 2.7 CDATA Sections

       // [18] CDSect ::= CDStart CData CDEnd
       // [19] CDStart ::=  '<![CDATA['
       // [20] CData ::= (Char* - (Char* ']]>' Char*))
       // [21] CDEnd ::= ']]>'

       //ASSUMPTION: seen <![
       char ch = more();
       if(ch != 'C') throw new XmlPullParserException(
               "expected <[CDATA[ for comment start", this);
       ch = more();
       if(ch != 'D') throw new XmlPullParserException(
               "expected <[CDATA[ for comment start", this);
       ch = more();
       if(ch != 'A') throw new XmlPullParserException(
               "expected <[CDATA[ for comment start", this);
       ch = more();
       if(ch != 'T') throw new XmlPullParserException(
               "expected <[CDATA[ for comment start", this);
       ch = more();
       if(ch != 'A') throw new XmlPullParserException(
               "expected <[CDATA[ for comment start", this);
       ch = more();
       if(ch != '[') throw new XmlPullParserException(
               "expected <![CDATA[ for comment start", this);

       //if(tokenize) {
       int cdStart = pos + bufAbsoluteStart;
       int curLine = lineNumber;
       int curColumn = columnNumber;
       boolean normalizeInput = tokenize == false || roundtripSupported == false;
       try {
           if(normalizeInput) {
               if(hadCharData) {
                   if(!usePC) {
                       // posEnd is correct already!!!
                       if(posEnd > posStart) {
                           joinPC();
                       } else {
                           usePC = true;
                           pcStart = pcEnd = 0;
                       }
                   }
               }
           }
           boolean seenBracket = false;
           boolean seenBracketBracket = false;
           boolean normalizedCR = false;
           while(true) {
               // scan until it hits "]]>"
               ch = more();
               if(ch == ']') {
                   if(!seenBracket) {
                       seenBracket = true;
                   } else {
                       seenBracketBracket = true;
                       //seenBracket = false;
                   }
               } else if(ch == '>') {
                   if(seenBracket && seenBracketBracket) {
                       break;  // found end sequence!!!!
                   } else {
                       seenBracketBracket = false;
                   }
                   seenBracket = false;
               } else {
                   if(seenBracket) {
                       seenBracket = false;
                   }
               }
               if(normalizeInput) {
                   // deal with normalization issues ...
                   if(ch == '\r') {
                       normalizedCR = true;
                       posStart = cdStart - bufAbsoluteStart;
                       posEnd = pos - 1; // posEnd is alreadys set
                       if(!usePC) {
                           if(posEnd > posStart) {
                               joinPC();
                           } else {
                               usePC = true;
                               pcStart = pcEnd = 0;
                           }
                       }
                       //assert usePC == true;
                       if(pcEnd >= pc.length) ensurePC(pcEnd);
                       pc[pcEnd++] = '\n';
                   } else if(ch == '\n') {
                       if(!normalizedCR && usePC) {
                           if(pcEnd >= pc.length) ensurePC(pcEnd);
                           pc[pcEnd++] = '\n';
                       }
                       normalizedCR = false;
                   } else {
                       if(usePC) {
                           if(pcEnd >= pc.length) ensurePC(pcEnd);
                           pc[pcEnd++] = ch;
                       }
                       normalizedCR = false;
                   }
               }
           }
       } catch(IOException ex) {
           // detect EOF and create meaningful error ...
           throw new XmlPullParserException(
               sprint.format("CDATA section started on line {} and column {} was not closed", curLine, curColumn),
               this /*, ex */);
       }
       if(normalizeInput) {
           if(usePC) {
               pcEnd = pcEnd - 2;
           }
       }
       posStart = cdStart - bufAbsoluteStart;
       posEnd = pos - 3;
    }

    protected void fillBuf() /* throws IOException, XmlPullParserException */ {
       if(input == null) throw new XmlPullParserException(
               "reader must be set before parsing is started");

       // see if we are in compaction area
       if(bufEnd > bufSoftLimit) {

           // expand buffer it makes sense!!!!
           boolean compact = bufStart > bufSoftLimit;
           boolean expand = false;
           if(preventBufferCompaction) {
               compact = false;
               expand = true;
           } else if(!compact) {
               //freeSpace
               if(bufStart < buf.length / 2) {
                   // less then half buffer available forcompactin --> expand instead!!!
                   expand = true;
               } else {
                   // at least half of buffer can be reclaimed --> worthwhile effort!!!
                   compact = true;
               }
           }

           // if buffer almost full then compact it
           if(compact) {
               //TODO: look on trashing
               // //assert bufStart > 0
               buf[0 .. bufEnd - bufStart] = buf[bufStart .. bufEnd];
               if(TRACE_SIZING) Stdout.formatln(
                       "TRACE_SIZING fillBuf() compacting {0} bufEnd={1} pos={2} posStart={3} posEnd={4} buf first 100 chars:{5}",
                       bufStart, bufEnd, pos, posStart, posEnd, buf[bufStart .. bufEnd - bufStart < 100 ? bufEnd : 100]);
           } else if(expand) {
               int newSize = 2 * buf.length;
               if(TRACE_SIZING) Stdout.formatln("TRACE_SIZING fillBuf() {0} => {1}", buf.length, newSize);
               buf.length = newSize;
               if(bufLoadFactor > 0) {
                   //bufSoftLimit = ( bufLoadFactor * buf.length ) /100;
                   bufSoftLimit = cast(int) (( (cast(long) bufLoadFactor) * buf.length ) /100);
               }

           } else {
               throw new XmlPullParserException("internal error in fillBuffer()");
           }
           bufEnd -= bufStart;
           pos -= bufStart;
           posStart -= bufStart;
           posEnd -= bufStart;
           bufAbsoluteStart += bufStart;
           bufStart = 0;
           if(TRACE_SIZING) Stdout.formatln(
                   "TRACE_SIZING fillBuf() after bufEnd={0} pos={1} posStart={2} posEnd={3} buf first 100 chars:{4}",
                   bufEnd, pos, posStart, posEnd, buf[0 .. bufEnd < 100 ? bufEnd : 100]);
       }
       // at least one character must be read or error
       int len = buf.length - bufEnd > READ_CHUNK_SIZE ? READ_CHUNK_SIZE : buf.length - bufEnd;
       int ret = input.read(buf[bufEnd .. $]);
       if(ret > 0) {
           bufEnd += ret;
           if(TRACE_SIZING) Stdout.formatln(
                   "TRACE_SIZING fillBuf() after filling in buffer buf first 100 chars:{0}", buf[0 .. bufEnd < 100 ? bufEnd : 100]);

           return;
       }
       if(ret == -1) {
           if(bufAbsoluteStart == 0 && pos == 0) {
               throw new IOException("input contained no data");
           } else {
               if(seenRoot && depth == 0) { // inside parsing epilog!!!
                   reachedEnd = true;
                   return;
               } else {
                   char[] expectedTagStack;
                   if(depth > 0) {
                       //char[] cbuf = elRawName[depth];
                       //char[] startname = new char[](cbuf, 0, elRawNameEnd[depth]);
                       expectedTagStack ~= " - expected end tag";
                       if(depth > 1) {
                           expectedTagStack ~= "s"; //more than one end tag
                       }
                       expectedTagStack ~= " ";
                       for (int i = depth; i > 0; i--)
                       {
                           char[] tagName = elRawName[i][0 .. elRawNameEnd[i]].dup;
                           expectedTagStack ~= "</" ~ tagName ~ '>';
                       }
                       expectedTagStack ~= " to close";
                       for (int i = depth; i > 0; i--)
                       {
                           if(i != depth) {
                               expectedTagStack ~= " and"; //more than one end tag
                           }
                           char[] tagName = elRawName[i][0 .. elRawNameEnd[i]].dup;
                           expectedTagStack ~= sprint.format(" start tag <{}> from line {}", tagName, elRawNameLine[i]);
                       }
                       expectedTagStack ~= ", parser stopped on";
                   }
                   throw new IOException("no more data available"
                                              ~ expectedTagStack ~ getPositionDescription());
               }
           }
       } else {
           throw new IOException(sprint.format("error reading input, returned {}", ret));
       }
    }

    protected char more() /* throws IOException, XmlPullParserException */ {
       if(pos >= bufEnd) {
           fillBuf();
           // this return value should be ignonored as it is used in epilog parsing ...
           if(reachedEnd) return cast(char)-1;
       }
       char ch = buf[pos++];
       //line/columnNumber
       if(ch == '\n') { ++lineNumber; columnNumber = 1; }
       else { ++columnNumber; }
       //System.out.print(ch);
       return ch;
    }

    //    /**
    //     * This function returns position of parser in XML input stream
    //     * (how many <b>characters</b> were processed.
    //     * <p><b>NOTE:</b> this logical position and not byte offset as encodings
    //     * such as UTF8 may use more than one byte to encode one character.
    //     */
    //    public int getCurrentInputPosition() {
    //        return pos + bufAbsoluteStart;
    //    }

    protected void ensurePC(int end) {
       //assert end >= pc.length;
       int newSize = end > READ_CHUNK_SIZE ? 2 * end : 2 * READ_CHUNK_SIZE;
       if(TRACE_SIZING) Stdout.formatln("TRACE_SIZING ensurePC() {0} ==> {1} end={2}", pc.length, newSize, end);
       pc.length = newSize;
       //assert end < pc.length;
    }

    protected void joinPC() {
       //assert usePC == false;
       //assert posEnd > posStart;
       int len = posEnd - posStart;
       int newEnd = pcEnd + len + 1;
       if(newEnd >= pc.length) ensurePC(newEnd); // add 1 for extra space for one char
       //assert newEnd < pc.length;
       pc[pcEnd .. pcEnd+len] = buf[posStart .. posStart+len];
       pcEnd += len;
       usePC = true;

    }

    protected char requireInput(char ch, char[] input)
       /* throws XmlPullParserException, IOException */
    {
       for (int i = 0; i < input.length; i++)
       {
           if(ch != input[i]) {
               throw new XmlPullParserException(
                   "expected "~printable(input[i])~" in " ~ input
                       ~" and not "~printable(ch), this);
           }
           ch = more();
       }
       return ch;
    }

    protected char requireNextS()
       /* throws XmlPullParserException, IOException */
    {
       char ch = more();
       if(!isS(ch)) {
           throw new XmlPullParserException(
               "white space is required and not "~printable(ch), this);
       }
       return skipS(ch);
    }

    protected char skipS(char ch)
       /* throws XmlPullParserException, IOException */
    {
       while(isS(ch)) { ch = more(); } // skip additional spaces
       return ch;
    }

    // nameStart / name lookup tables based on XML 1.1 http://www.w3.org/TR/2001/WD-xml11-20011213/
    protected static const wchar LOOKUP_MAX = 0x400;
    protected static const wchar LOOKUP_MAX_CHAR = LOOKUP_MAX;
    //    protected static int lookupNameStartChar[] = new int[ LOOKUP_MAX_CHAR / 32 ];
    //    protected static int lookupNameChar[] = new int[ LOOKUP_MAX_CHAR / 32 ];
    protected static boolean lookupNameStartChar[];
    protected static boolean lookupNameChar[];

    private static final void setName(wchar ch)
       //{ lookupNameChar[ (int)ch / 32 ] |= (1 << (ch % 32)); }
    { lookupNameChar[ ch ] = true; }
    private static final void setNameStart(wchar ch)
       //{ lookupNameStartChar[ (int)ch / 32 ] |= (1 << (ch % 32)); setName(ch); }
    { lookupNameStartChar[ ch ] = true; setName(ch); }

    static this() {
       lookupNameStartChar = new boolean[ LOOKUP_MAX ];
       lookupNameChar = new boolean[ LOOKUP_MAX ];

       setNameStart(':');
       for (char ch = 'A'; ch <= 'Z'; ++ch) setNameStart(ch);
       setNameStart('_');
       for (char ch = 'a'; ch <= 'z'; ++ch) setNameStart(ch);
       for (wchar ch = '\u00c0'; ch <= '\u02FF'; ++ch) setNameStart(ch);
       for (wchar ch = '\u0370'; ch <= '\u037d'; ++ch) setNameStart(ch);
       for (wchar ch = '\u037f'; ch < '\u0400'; ++ch) setNameStart(ch);

       setName('-');
       setName('.');
       for (char ch = '0'; ch <= '9'; ++ch) setName(ch);
       setName('\u00b7');
       for (wchar ch = '\u0300'; ch <= '\u036f'; ++ch) setName(ch);
    }

    //private final static boolean isNameStartChar(char ch) {
    protected boolean isNameStartChar(char ch) {
       return (ch < LOOKUP_MAX_CHAR && lookupNameStartChar[ ch ])
           || (ch >= LOOKUP_MAX_CHAR && ch <= '\u2027')
           || (ch >= '\u202A' &&  ch <= '\u218F')
           || (ch >= '\u2800' &&  ch <= '\uFFEF')
           ;

       //      if(ch < LOOKUP_MAX_CHAR) return lookupNameStartChar[ ch ];
       //      else return ch <= '\u2027'
       //              || (ch >= '\u202A' &&  ch <= '\u218F')
       //              || (ch >= '\u2800' &&  ch <= '\uFFEF')
       //              ;
       //return false;
       //        return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == ':'
       //          || (ch >= '0' && ch <= '9');
       //        if(ch < LOOKUP_MAX_CHAR) return (lookupNameStartChar[ (int)ch / 32 ] & (1 << (ch % 32))) != 0;
       //        if(ch <= '\u2027') return true;
       //        //[#x202A-#x218F]
       //        if(ch < '\u202A') return false;
       //        if(ch <= '\u218F') return true;
       //        // added pairts [#x2800-#xD7FF] | [#xE000-#xFDCF] | [#xFDE0-#xFFEF] | [#x10000-#x10FFFF]
       //        if(ch < '\u2800') return false;
       //        if(ch <= '\uFFEF') return true;
       //        return false;


       // else return (supportXml11 && ( (ch < '\u2027') || (ch > '\u2029' && ch < '\u2200') ...
    }

    //private final static boolean isNameChar(char ch) {
    protected boolean isNameChar(char ch) {
       //return isNameStartChar(ch);

       //        if(ch < LOOKUP_MAX_CHAR) return (lookupNameChar[ (int)ch / 32 ] & (1 << (ch % 32))) != 0;

       return (ch < LOOKUP_MAX_CHAR && lookupNameChar[ ch ])
           || (ch >= LOOKUP_MAX_CHAR && ch <= '\u2027')
           || (ch >= '\u202A' &&  ch <= '\u218F')
           || (ch >= '\u2800' &&  ch <= '\uFFEF')
           ;
       //return false;
       //        return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == ':'
       //          || (ch >= '0' && ch <= '9');
       //        if(ch < LOOKUP_MAX_CHAR) return (lookupNameStartChar[ (int)ch / 32 ] & (1 << (ch % 32))) != 0;

       //else return
       //  else if(ch <= '\u2027') return true;
       //        //[#x202A-#x218F]
       //        else if(ch < '\u202A') return false;
       //        else if(ch <= '\u218F') return true;
       //        // added pairts [#x2800-#xD7FF] | [#xE000-#xFDCF] | [#xFDE0-#xFFEF] | [#x10000-#x10FFFF]
       //        else if(ch < '\u2800') return false;
       //        else if(ch <= '\uFFEF') return true;
       //else return false;
    }

    protected boolean isS(char ch) {
       return (ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t');
       // || (supportXml11 && (ch == '\u0085' || ch == '\u2028');
    }

    //protected boolean isChar(char ch) { return (ch < '\uD800' || ch > '\uDFFF')
    //  ch != '\u0000' ch < '\uFFFE'


    //protected char printable(char ch) { return ch; }
    protected char[] printable(char ch) {
       if(ch == '\n') {
           return "\\n";
       } else if(ch == '\r') {
           return "\\r";
       } else if(ch == '\t') {
           return "\\t";
       } else if(ch == '\'') {
           return "\\'";
       } if(ch > 127 || ch < 32) {
           char[16] temp;
           return "\\u"~format(temp, ch, Style.Hex);
       }
       return [ch];
    }

    protected char[] printable(char[] s) {
       char[] buf;
       foreach(c; s) {
           buf ~= printable(c);
       }
       return buf;
    }
}

/*
* Indiana University Extreme! Lab Software License, Version 1.2
*
* Copyright (C) 2003 The Trustees of Indiana University.
* All rights reserved.
*
* Redistribution and use in source and binary forms, with or without
* modification, are permitted provided that the following conditions are
* met:
*
* 1) All redistributions of source code must retain the above
*    copyright notice, the list of authors in the original source
*    code, this list of conditions and the disclaimer listed in this
*    license;
*
* 2) All redistributions in binary form must reproduce the above
*    copyright notice, this list of conditions and the disclaimer
*    listed in this license in the documentation and/or other
*    materials provided with the distribution;
*
* 3) Any documentation included with all redistributions must include
*    the following acknowledgement:
*
*      "This product includes software developed by the Indiana
*      University Extreme! Lab.  For further information please visit
*      http://www.extreme.indiana.edu/"
*
*    Alternatively, this acknowledgment may appear in the software
*    itself, and wherever such third-party acknowledgments normally
*    appear.
*
* 4) The name "Indiana University" or "Indiana University
*    Extreme! Lab" shall not be used to endorse or promote
*    products derived from this software without prior written
*    permission from Indiana University.  For written permission,
*    please contact http://www.extreme.indiana.edu/.
*
* 5) Products derived from this software may not use "Indiana
*    University" name nor may "Indiana University" appear in their name,
*    without prior written permission of the Indiana University.
*
* Indiana University provides no reassurances that the source code
* provided does not infringe the patent or any other intellectual
* property rights of any other entity.  Indiana University disclaims any
* liability to any recipient for claims brought by any other entity
* based on infringement of intellectual property rights or otherwise.
*
* LICENSEE UNDERSTANDS THAT SOFTWARE IS PROVIDED "AS IS" FOR WHICH
* NO WARRANTIES AS TO CAPABILITIES OR ACCURACY ARE MADE. INDIANA
* UNIVERSITY GIVES NO WARRANTIES AND MAKES NO REPRESENTATION THAT
* SOFTWARE IS FREE OF INFRINGEMENT OF THIRD PARTY PATENT, COPYRIGHT, OR
* OTHER PROPRIETARY RIGHTS.  INDIANA UNIVERSITY MAKES NO WARRANTIES THAT
* SOFTWARE IS FREE FROM "BUGS", "VIRUSES", "TROJAN HORSES", "TRAP
* DOORS", "WORMS", OR OTHER HARMFUL CODE.  LICENSEE ASSUMES THE ENTIRE
* RISK AS TO THE PERFORMANCE OF SOFTWARE AND/OR ASSOCIATED MATERIALS,
* AND TO THE PERFORMANCE AND VALIDITY OF INFORMATION GENERATED USING
* SOFTWARE.
*/

