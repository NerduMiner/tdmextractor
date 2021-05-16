module lz77lookuptable;
import std.algorithm;
import std.range;

//Credit to ItsAllInTheCode for the lookup table https://github.com/ItsAllAboutTheCode/lz77_compressor

struct lengthOffset {
	int length; //Number of bytes compressed
	uint offset; //How far back in sliding window where bytes that match LookAheadBuffer is located
	bool compareEqual(lengthOffset lo_pair) {
		return length == lo_pair.length && offset == lo_pair.offset;
	}
}

class lz77LookupTable {
	this() {
		minimumMatch = 3;
		SlidingWindow = 4096;
		LookAheadWindow = 18;
		buffer.length = minimumMatch;
	}
	
	this(int iminimumMatch, int iSlidingWindow, int iLookAheadWindow) {
		if (iminimumMatch > 0) {
			minimumMatch = iminimumMatch;
		} else {
			minimumMatch = 3;
		}
		
		if (iSlidingWindow > 0) {
			SlidingWindow = iSlidingWindow;
		} else {
			SlidingWindow = 4096;
		}
		
		if (iLookAheadWindow > 0) {
			LookAheadWindow = iLookAheadWindow;
		} else {
			LookAheadWindow = 18;	
		}
		buffer.length = minimumMatch;
	}
	
	void setLookAheadWindow(int iLookAheadWindow) {
		if(iLookAheadWindow > 0) {
			LookAheadWindow = iLookAheadWindow;
		} else {
			LookAheadWindow = 18;
		}
	}
	
	lengthOffset search(ubyte *curPos, ubyte *dataBegin, ubyte *dataEnd) {
		lengthOffset lo_pair = new lenghtOffset(0, 0);
		//-1 as length means search failure
		if (curPos >= dataEnd) {
			lo_pair.length = -1;
			return lo_pair;
		}
		buffer.copy((curPos + minimumMatch) - curPos);
		int currentOffset = cast(int)(curPos - dataBegin);
		//Find Code
		if (currentOffset > 0 && (dataEnd - curPos) >= minimumMatch) {
			//TODO: finish converting auto elements = table.equal_range(buffer);
		}
	}
	private:
		ubyte[] buffer;
		int[ubyte[]] table;
		int minimumMatch;
		int SlidingWindow;
		int LookAheadWindow;
}
