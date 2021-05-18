module lz77helper;
import std.algorithm;
import std.stdio;
import std.range;

//Credit to Brubary for the helper function https://github.com/Barubary/dsdecmp/blob/4ddd87206bacf4ce7d803b40ff3bd2663327b083/CSharp/DSDecmp/Utils/LZUtil.cs#L24

int getOccurenceLength(ubyte* newPtr, int newLength, ubyte* oldPtr, int oldLength, int *disp, int minDisp = 1) {
	*disp = cast(int*)0;
	if (newLength == 0)
		return 0;
	int maxLength = 0;
	//Try every possible value for disp (where disp = oldLength - i)
	for (int i = 0; i < oldLength - minDisp; i++) {
		//Work from start of old data to the end
		ubyte* currentOldStart = oldPtr + i;
		int currentLength = 0;
		//Determine the length to be copied when going back (oldLength - i) bytes
		//Always check the next 'newLength' bytes, and not just the available 'old' bytes,
		//as the copied data can also originate from the current chunk
		for (int j = 0; j < newLength; j++) {
			//Stop when bytes are no longer the same
			//writeln(currentOldStart + j);
			//writeln(newPtr + j);
			if (*(currentOldStart + j) != *(newPtr + j)) {
				//writeln("BYTES NO LONGER THE SAME");
				break;
			}
			currentLength++;
		}
		//Update the optimal value
		if (currentLength > maxLength) {
			maxLength = currentLength;
			*disp = cast(int*)(oldLength - i);
			//Stop if optimization is not possible
			if (maxLength == newLength) {
				//writeln("OPTIMIZATION NO LONGER POSSIBLE");
				break;
			}
		}
	}
	return maxLength;
}
