import std.stdio; //Used for general functions
import std.file; //Used for handling archive files
import std.array; //Used for array manipulation
import std.format : format;
import std.getopt; //Used for parsing CLI arguments
import binary.reader; //Used for reading from archives
import binary.common; //cause D being mean
import asdf; //For handling the json file

///Stores file header information read from the archive
struct FileHeader {
	///Index of the file in the original archive
	int fileIndex;
	///The strange first 4 bytes that seem unique to each file
	string fileID;
	///A small number between 2-9
	uint unk;
	///The extension of the file
	string extension;
	///True = LZ77wii compressed\nFalse = Uncompressed
	bool isCompressed;
}

///Used to determine extension of file, values refer to specific hex bytes in the header
enum KnownHeaders : ubyte[]
{
	BCH = [66, 67, 72, 0],
	CGF = [67, 71, 70, 88],
	ZIP = [80, 75, 3, 4],
	DAR = [100, 97, 114, 99],
	NFC = [3, 0, 0, 0] //No clue what this is supposed to be but quickbms recognizes it
}

///Grabs from a list of possible extensions and then renames them according to header data
///\nReturns a string that denotes the extension
string determineExtension(string filepath, string filename) {
	//writeln("Filename: ", filename);
	//writeln("Filepath: ", filepath);
	try {
		//Attempt to read header of file, and rename extension accordingly
		auto data = cast(ubyte[]) read(filepath, 4);
		if(data == KnownHeaders.BCH) {
			rename(filepath, filename ~ ".bch"); 
			return "bch";
		}
		if(data == KnownHeaders.CGF) {
			rename(filepath, filename ~ ".cgf");
			return "cgf";
		}
		if(data == KnownHeaders.ZIP) {
			rename(filepath, filename ~ ".zip"); 
			return "zip";
		}
		if(data == KnownHeaders.DAR) {
			rename(filepath, filename ~ ".dar");
			return "dar";
		}
		if(data == KnownHeaders.NFC) {
			rename(filepath, filename ~ ".nfc"); 
			return "nfc";
		}
		rename(filepath, filename ~ ".dat");
		return "dat";
	} catch (FileException ex) {
		writeln("FAILED TO READ FROM FILE");
		throw ex;
	}
}

//Credit for Algorithm goes to Marcan at https://wiibrew.org/wiki/LZ77
///Extract a file, decompressing it in the process
void extractLZ77wii(File *archive, FileHeader *fileheader, uint offset, string filename) {
	//Begin by reading the header
	ubyte[] data;
	data.length = 4;
	archive.seek(offset);
	archive.rawRead(data);
	auto reader = binaryReader(data);
	const uint header = reader.read!uint();
	//Funny bit magic to read a byte and 3 bytes from uint
	const auto uncompressedSize = header>>8; //1 Byte
	const auto compressionType = header>>4 & 0xF; //3 Bytes
	//writeln("File Uncompressed Size: ", uncompressedSize);
	//writeln("File Compression Type: ", compressionType);
	//Make sure the compression type is right
	if (compressionType != 1) {
		throw new Exception("Invalid Compression Type");
	}
	//Now we actually create the file and begin the decompression process
	File extract = File (filename ~ ".bin", "wb");
	ubyte[] uncompressedData;
	//LZ77wii compression makes use of chunks, each with a flag before them
	//Flags are 8 bits where each bit represents a full byte of extracted
	//data
	//If a bit in the flag is 0, the corresponding byte in the chunk is
	//raw data, if it is 1, it is a 2 byte reference to previous data
	//where 1 Nibble is the length of data - 3 and 3 nibbles is the offset 
	//in uncompressed data used by the reference
	while (uncompressedData.length < uncompressedSize) {
		//Read Chunk Flag
		data = [];
		data.length = 1;
		archive.rawRead(data);
		reader.source(data);
		auto flags = reader.read!ubyte();
		//writeln("Chunk Flag: ", format!"%x"(flags));
		//Iterate through chunk using bitflag to determine reference or raw
		for (int i = 0; i < 8; i++) {
			//writeln("Current Flag Bit: ", flags & 0x80);
			//Is current bit set to 1?
			if (flags & 0x80) {
				//Read Reference
				data = [];
				data.length = 2;
				archive.rawRead(data);
				reader.source(data);
				//Reference must be read BigEndian
				reader.byteOrder = ByteOrder.BigEndian;
				const auto info = reader.read!ushort();
				reader.byteOrder = ByteOrder.LittleEndian;
				//Determine length of data
				const auto num = 3 + ((info>>12)&0xF);
				//Uhhhhhhhh
				const auto disp = info & 0xFFF;
				//Determine offset in uncompressed data
				//writeln("Current Data Length: ", uncompressedData.length);
				//writeln("Info: ", format!"%x"(info));
				auto ptr = uncompressedData.length - (info & 0xFFF) - 1;
				//writeln("Uncompressed Offset: ", ptr);
				for (int k = 0; k < num; k++) {
					uncompressedData ~= uncompressedData[ptr];
					ptr += 1;
					//small sanity check
					if (uncompressedData.length >= uncompressedSize)
						break;
				}
			} else {
				data = [];
				data.length = 1;
				reader.source(data);
				uncompressedData ~= archive.rawRead(data);
			}
			flags <<= 1;
			//small sanity check
			if (uncompressedData.length >= uncompressedSize)
				break;
		}
	}
	extract.rawWrite(uncompressedData);
	extract.close();
	fileheader.extension = determineExtension(filename ~ ".bin", filename);
}

int main(string[] args)
{
	//Setup Arguments
	if (args.length == 1) {
        writeln("No arguments given. Please provide model file.");
        return 1;
	}
	string filename = "archive";
	auto const argInfo = getopt(args, "file", &filename);
	//Begin by opening the archive file
	File archive = File(filename, "rb");
	//Begin reading the header portion of the file
	while (!archive.eof()) {
		//Determine format of header, TDM3 Is always 7
		ubyte[] data;
		data.length = 12;
		archive.rawRead(data);
		auto reader = binaryReader(data);
		auto archVersion = reader.read!uint();
		auto archOffset = reader.read!uint();
		writeln("Archive Version: ", archVersion);
		writeln("Archive Offset: ", format!"%x"(archOffset));
		//Create Folder to place extracted files into
		auto folderName = format!"%x"(archOffset) ~ "_";
		mkdir(folderName);
		const int fileAmount = reader.read!uint();
		writeln("Number of Files: ", fileAmount);
		reader.clear();
		//Create JSON file to place extra data into
		File jsonfile = File(folderName ~ "/" ~ format!"%x"(archOffset) ~ ".json", "w");
		FileHeader[] fileheaders;
		fileheaders.length = fileAmount;
		//Determine information about file headers
		for (int i = 0; i < fileAmount; i++) {
			data = [];
			data.length = 28;
			archive.rawRead(data);
			reader.source(data);
			writeln("====FILE ", i + 1, " INFORMATION====");
			//Read file information while also applying them to our struct
			auto fileID = reader.read!uint();
			writeln("Unknown 1: ", format!"%x"(fileID));
			fileheaders[i].fileIndex = i + 1;
			fileheaders[i].fileID = format!"%x"(fileID);
			fileheaders[i].unk = reader.read!uint();
			writeln("Unknown 2: ", fileheaders[i].unk);
			auto compressedSize = reader.read!uint();
			writeln("Compressed Size: ", compressedSize);
			auto fileOffset = reader.read!uint();
			writeln("File ", i, " Offset: ", format!"%x"(fileOffset));
			const auto compressionMode = reader.read!uint();
			const bool isCompressed = (compressionMode == 6) ? true : false;
			fileheaders[i].isCompressed = isCompressed;
			writeln("Is file compressed? ", isCompressed);
			//Skip Padding
			reader.read!uint();
			auto uncompressedSize = reader.read!uint();
			writeln("Uncompressed Size: ", uncompressedSize);
			reader.clear();
			auto filePath = folderName ~ "/" ~ format!"%x"(fileID);
			//Begin Extracting file
			if (isCompressed) {
				//Decompress and Extract File Data
				auto origOffset = archive.tell();
				extractLZ77wii(&archive, &fileheaders[i], fileOffset, filePath);
				archive.seek(origOffset);
			} else {
				//Extract File Data
				auto origOffset = archive.tell();
				archive.seek(fileOffset);
				ubyte[] fileData;
				//Uncompressed size is in compressedSize
				fileData.length = compressedSize;
				//writeln("File Size: ", fileData.length);
				archive.rawRead(fileData);
				File uncomFile = File(filePath ~ ".bin", "wb");
				uncomFile.rawWrite(fileData);
				uncomFile.close();
				fileheaders[i].extension = determineExtension(filePath ~ ".bin", filePath);
				archive.seek(origOffset);
			}
			//Add element to JSON file
			jsonfile.writeln(fileheaders[i].serializeToJsonPretty());
		}
		jsonfile.close();
		break;
	}
	archive.close();
	return 0;
}
