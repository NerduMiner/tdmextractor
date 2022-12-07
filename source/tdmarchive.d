module tdmarchive;
import binary.common; //Needed for some pack-d functions
import binary.pack; //For formatting data into specific types
import binary.reader; //For parsing data from raw byte arrays
import lz77helper; //Has helper functions for lz77wii compression
import std.algorithm;
import std.array;
import std.conv;
import std.file;
import std.format;
import std.path;
import std.stdio;
import std.string;
import std.zlib;
import archive.zip; //Used to handle zip files and obtain information about them
import vibe.data.json; //Used to write and read from the JSON helper file
import vibe.data.serialization;
///Stores archive header information
struct ArchiveHeader {
	///Version reported by the archive
	ArchiveVersion ver;
	///TNDM Exclusive: Some random integer
	@embedNullable uint NDMunk;
}

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
	///TDMF Exclusive: Related to compression mode(1 for uncompressed, 2 for lz77wii compressed)
	uint compressedUnk = 0;
	//The following are TNDM exclusive
	@embedNullable uint NDMunk1;
	@embedNullable uint NDMunk2;
	@embedNullable uint NDMunk3;
}

///A struct containing all info relating to an archive to be outputted into a JSON info file
struct ArchiveInfo {
	FileHeader[] fileHeader;
	ArchiveHeader archiveHeader;
}

///Used to determine extension of file, values refer to specific hex bytes in the header
enum KnownHeaders : ubyte[]
{
	BCH = [66, 67, 72, 0],
	CGF = [67, 71, 70, 88],
	ZIP = [80, 75, 3, 4],
	DAR = [100, 97, 114, 99],
	SAR = [83, 65, 82, 67],
	NFC = [3, 0, 0, 0], //No clue what this is supposed to be but quickbms recognizes it
	SDB = [2, 0, 0, 0],
	VAP = [1, 0, 0, 0]  

}

///Used to determine which game the archive belongs to
enum ArchiveVersion : uint
{
	TDM12 = 5,
	TDM3 = 7,
	TDMF = 10,
	TNDM = 14,
}

///Grabs from a list of possible extensions and then renames them according to header data
///\nReturns a string that denotes the extension
string determineExtension(string filepath, string filename) {
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

///Alternate version of lz77 compression found here https://github.com/Barubary/dsdecmp/blob/master/CSharp/DSDecmp/Formats/Nitro/LZ10.cs
ubyte[] packLZ77wiialt(File infile) {
	try {
		//Setup data arrays
		ubyte[] output;
		auto fileLength = infile.size();
		//File cannot be larger than 16.77MB
		if (fileLength > 16_777_215) {
			throw new Exception("File cannot be more than 16.77MB large.");
		}
		ubyte[] fileData = new ubyte[fileLength];
		//Create Header for compressed file(Size of File and compression type in 4 bytes)
		output ~= pack!`<I`(fileLength<<8 | 0x10);
		//Read entirety of file into fileData
		infile.rawRead(fileData);
		int compressedLength = 4;
		ubyte* instart = cast(ubyte*)fileData;
		//Output needs to be buffered due to flag byte
		//This algorithm only buffers 8 bytes at a time
		ubyte[] outbuffer = new ubyte[8*2 + 1];
		outbuffer[0] = 0;
		int bufferLength = 1, bufferedBlocks = 0;
		int readBytes = 0;
		while (readBytes < fileLength) {
			//Reset Buffer
			if (bufferedBlocks == 8) {
				output ~= outbuffer[0..bufferLength];
				compressedLength += bufferLength;
				outbuffer[0] = 0;
				bufferLength = 1;
				bufferedBlocks = 0;
			}

			//Determine whether data is compressed or raw
			int disp;
			const int oldLength = min(readBytes, 0x1000);
			int length = getOccurenceLength(cast(ubyte*)instart + readBytes, cast(int)min(fileLength - readBytes, 0x12), 
				instart + readBytes - oldLength, oldLength, &disp);
			//Length < 3 means next byte is raw data
			if (length < 3) {
				outbuffer[bufferLength++] = *(instart + (readBytes++));
			} else {
				//We need to create a reference, next [length] bytes will be compressed into 2 byte reference
				readBytes += length;
				//Mark next block as compressed
				outbuffer[0] |= cast(ubyte)(1 << (7 - bufferedBlocks));
				//Encode data length and offset
				outbuffer[bufferLength] = cast(ubyte)(((length - 3) << 4) & 0xF0);
				//Prevent integer underflow
				if (disp == 0) {
					writeln("Preventing overflow");
					outbuffer[bufferLength] |= cast(ubyte)((disp >> 8) & 0x0F);
					bufferLength++;
					outbuffer[bufferLength] = cast(ubyte)(disp & 0xFF);
					bufferLength++;
				} else {
					outbuffer[bufferLength] |= cast(ubyte)(((disp - 1) >> 8) & 0x0F);
					bufferLength++;
					outbuffer[bufferLength] = cast(ubyte)((disp - 1) & 0xFF);
					bufferLength++;
				}
			}
			bufferedBlocks++;
		}
		//Copy remaining blocks to the output
		if (bufferedBlocks > 0) {
			output ~= outbuffer;
			compressedLength += bufferLength;
		}
		return output;
	} catch (Exception e) {
		throw new Exception("Compression Failed.");
	}
}

//Credit for Algorithm goes to Marcan at https://wiibrew.org/wiki/LZ77
///Extract a file, decompressing it in the process
void extractLZ77wii(File archive, FileHeader fileheader, uint offset, string filename) {
	//Begin by reading the header
	ubyte[] data;
	data.length = 4;
	archive.seek(offset);
	archive.rawRead(data);
	auto reader = binaryReader(data);
	const uint header = reader.read!uint();
	//Funny bit magic to read a byte and 3 bytes from uint
	const auto uncompressedSize = header >> 8; //1 Byte
	const auto compressionType = header >> 4 & 0xF; //3 Bytes
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
		//Iterate through chunk using bitflag to determine reference or raw
		for (int i = 0; i < 8; i++) {
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
				//TODO: Consider what to do with this since this is unused
				const auto disp = info & 0xFFF;
				//Determine offset in uncompressed data
				auto ptr = uncompressedData.length - (info & 0xFFF) - 1;
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
}

///Takes a folder and repacks it into the proprietary archive format
int repackArchive(string filename) {
	//Start by opening the json file inside the folder so we can determine how to go about repacking the folder
	string offset = strip(filename, "_"); //Used whenever something cant be read at compile time
	string jsonFilename = filename ~ "/" ~ strip(filename, "_") ~ ".json";
	//string jsonArchver = filename ~ "/" ~ "version.json"; 
	ubyte[] compressedData;
	ubyte[] headerData;
	const string jsonData = readText(jsonFilename);
	//const string jsonVer = readText(jsonArchver);
	const Json fileinfo = parseJsonString(jsonData);
	//const Json archinfo = parseJsonString(jsonVer);
	//FileHeader[] fileheaders;
	//ArchiveHeader archiveheader = deserializeJson!ArchiveHeader(archinfo);
	ArchiveInfo archInfo = deserializeJson!ArchiveInfo(fileinfo);
	writeln("Archive Version: ", archInfo.archiveHeader.ver);
	//fileheaders.length = fileinfo.length;
	//Prepare output file
	File outputArchive = File(filename ~ "output", "wb");
	//Archive header needs to be written differently if we are packing a TDMF archive
	if (archInfo.archiveHeader.ver != ArchiveVersion.TNDM) {
		//Append Archive header
		headerData ~= pack!`<I`(archInfo.archiveHeader.ver); //Archive version
		headerData ~= pack!`<I`(parse!ulong(offset, 16)); //File offset
		headerData ~= pack!`<I`(archInfo.fileHeader.length); //Amount of files
	} else if (archInfo.archiveHeader.ver == ArchiveVersion.TDMF) {
		//Append Archive header
		headerData ~= pack!`<I`(archInfo.archiveHeader.ver); //Archive version
		headerData ~= pack!`<I`(parse!ulong(offset, 16)); //File offset
		headerData ~= pack!`<I`(0); //Unknown 1
		headerData ~= pack!`<I`(65_536); //Unknown 2
		headerData ~= pack!`<I`(archInfo.fileHeader.length); //Amount of files
		headerData ~= pack!`<I`(0); //Unknown 3
	} else {
		headerData ~= pack!`<I`(archInfo.archiveHeader.ver); //Archive version
		headerData ~= pack!`<I`(parse!ulong(offset, 16)); //File offset
		headerData ~= pack!`<I`(0); //Unknown 1
		headerData ~= pack!`<I`(458_758); //Unknown 2
		headerData ~= pack!`<I`(archInfo.fileHeader.length); //Amount of files
		headerData ~= pack!`<I`(archInfo.archiveHeader.NDMunk);
	}
	//Prepare some variables before hand to assist with archive creation
	ulong maxHeaderLength = headerData.length + (28 * archInfo.fileHeader.length); //Used when calculating file offset
	for (int i = 0; i < archInfo.fileHeader.length; i++) {
		//Read the corresponding json information
		//const auto current = fileinfo[i];
		//fileheaders[i] = deserializeJson!FileHeader(current);
		bool fileExists = true;
		File infile;
		if (exists(filename ~ "/" ~ archInfo.fileHeader[i].fileID ~ "." ~ archInfo.fileHeader[i].extension))
		{
			infile = File(filename ~ "/" ~ archInfo.fileHeader[i].fileID ~ "." ~ archInfo.fileHeader[i].extension, "rb");
		}
		else
		{
			fileExists = false;
			writeln("WARNING: File does not exist! Header will still be written");
		}
		writeln("File Index: ", archInfo.fileHeader[i].fileIndex);
		writeln("File ID: ", archInfo.fileHeader[i].fileID);
		auto arch_filename = filename ~ "/" ~ archInfo.fileHeader[i].fileID ~ "." ~ archInfo.fileHeader[i].extension; //This is for zip handling code, but apparently we can only get string properly here?
		writeln("File unk: ", archInfo.fileHeader[i].unk);
		writeln("File extension: ", archInfo.fileHeader[i].extension);
		writeln("Is file compressed?: ", archInfo.fileHeader[i].isCompressed);
		//Pack header into headerData
		headerData ~= pack!`<I`(parse!ulong(archInfo.fileHeader[i].fileID, 16)); //File ID?
		headerData ~= pack!`<I`(archInfo.fileHeader[i].unk); //Unk value
		//The following data requires the filesizes to be known beforehand
		if ((archInfo.fileHeader[i].isCompressed && fileExists) 
		|| archInfo.archiveHeader.ver == ArchiveVersion.TNDM) {
			//Pack corrseponding file into compressedData
			writeln("Compressing file...");
			ubyte[] buffer;
			if (archInfo.archiveHeader.ver == ArchiveVersion.TNDM)
			{
				auto filebuf = cast(ubyte[]) read(infile.name);
				buffer = compress(filebuf);
			} else {
				buffer = packLZ77wiialt(infile);
			}
			writeln("Compression Complete!");
			headerData ~= pack!`<I`(buffer.length); //Compressed length
			if (i == 0) { //Calculate File Offset in archive
				headerData ~= pack!`<I`(maxHeaderLength);
			} else {
				headerData ~= pack!`<I`(maxHeaderLength + compressedData.length);
			}
			headerData ~= pack!`<I`(6); //Compression Mode
			if (archInfo.archiveHeader.ver == ArchiveVersion.TDM3) {
				headerData ~= pack!`<I`(1); //TDM3 Padding
			} else if (archInfo.archiveHeader.ver == ArchiveVersion.TDM12) {
				headerData ~= pack!`<I`(0xFFFFFFFF); //TDM1-2 Padding
			} else {
				headerData ~= pack!`<I`(2); //TDMF Unknown
			}
			headerData ~= pack!`<I`(infile.size); //Uncompressed Length
			compressedData ~= buffer;
		} else if (fileExists) {
			//File is not compressed, so just put the whole thing in there
			ubyte[] rawDat;
			rawDat.length = infile.size();
			headerData ~= pack!`<I`(infile.size()); //Compressed length(but holds uncompressed size)
			if (i == 0) { //Calculate File Offset in archive
				headerData ~= pack!`<I`(maxHeaderLength);
			} else {
				headerData ~= pack!`<I`(maxHeaderLength + compressedData.length);
			}
			headerData ~= pack!`<I`(1); //Compression Mode
			if (archInfo.archiveHeader.ver == ArchiveVersion.TDM3) {
				headerData ~= pack!`<I`(1); //TDM3 Padding
			} else if (archInfo.archiveHeader.ver == ArchiveVersion.TDM12) {
				headerData ~= pack!`<I`(0xFFFFFFFF); //TDM1-2 Padding
			} else {
				headerData ~= pack!`<I`(1); //TDMF Unknown
			}
			//Uncompressed Size of file, for zip files, this equates to the total size of the extracted files
			if (archInfo.fileHeader[i].extension == "zip")
			{
				auto archive = new ZipArchive(read(arch_filename));
				uint uncompressed_size;
				foreach(file; archive.files)
				{
					uncompressed_size += file.data.length;
				}
				headerData ~= pack!`<I`(uncompressed_size);
				archive = null;
			}
			else
			{
				headerData ~= pack!`<I`(infile.size()); //Fallback option of just reporting the size of the file
			}
			infile.rawRead(rawDat);
			compressedData ~= rawDat;
		} else {
			//File does not exist, but we have to write header data anyways
			headerData ~= pack!`<I`(0); //Compressed length
			headerData ~= pack!`<I`(maxHeaderLength + compressedData.length); //Bogus Offset
			headerData ~= pack!`<I`(6); //Compression Mode
			if (archInfo.archiveHeader.ver == ArchiveVersion.TDM3) {
				headerData ~= pack!`<I`(1); //TDM3 Padding
			} else if (archInfo.archiveHeader.ver == ArchiveVersion.TDM12) {
				headerData ~= pack!`<I`(0xFFFFFFFF); //TDM1-2 Padding
			} else {
				headerData ~= pack!`<I`(2); //TDMF Unknown
			}
			headerData ~= pack!`<I`(0); //Uncompressed Length
		}
		infile.close();
	}
	outputArchive.rawWrite(headerData);
	outputArchive.rawWrite(compressedData);
	return 0;
}

///Takes an archive and extracts the files out of it, along with creating a helper JSON file for repacking
int extractArchive(File archive) {
//Begin reading the header portion of the file
	while (!archive.eof()) {
		//Determine format of header, TDM3 is always 7, TDM1-2 is always 5, TDMF is always 10 
		ubyte[] data;
		data.length = 12;
		archive.rawRead(data);
		auto reader = binaryReader(data);
		auto archVersion = reader.read!uint();
		writeln(archVersion);
		//TDMF and TNDM have a marginally different format to its header compared to the main games, thus we will extract in a separate function
		switch (archVersion)
		{
			case ArchiveVersion.TNDM:
				writeln("TNDM Archive detected.");
				extractArchiveTNDM(archive);
				return 0;
			case ArchiveVersion.TDMF:
				writeln("TDMF Archive detected.");
				extractArchiveTDMF(archive);
				return 0;
			default:
				break;
		}
		auto archOffset = reader.read!uint();
		writeln("Archive Version: ", archVersion);
		writeln("Archive Offset: ", format!"%X"(archOffset));
		//Create Folder to place extracted files into
		auto folderName = format!"%X"(archOffset) ~ "_";
		if (!folderName.exists) {
			mkdir(folderName);
		} else {
			writeln("Folder already exists. Do you wish to overwrite it's contents?[y/n]");
			stdout.flush;
			if (startsWith(readln, "n")) {
				writeln("Permission denied. Exiting program...");
				return 1;
			}
		}
		const int fileAmount = reader.read!uint();
		writeln("Number of Files: ", fileAmount);
		reader.clear();
		//Create JSON files to place extra data into
		File jsonfile = File(folderName ~ "/" ~ format!"%X"(archOffset) ~ ".json", "w");
		//File jsonarch = File(folderName ~ "/" ~ "version.json", "w");
		FileHeader[] fileheaders;
		ArchiveHeader archiveheader;
		if (archVersion == ArchiveVersion.TDM3) {
			archiveheader.ver = ArchiveVersion.TDM3;
		} else {
			archiveheader.ver = ArchiveVersion.TDM12;
		}
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
			writeln("Unknown 1: ", format!"%X"(fileID));
			fileheaders[i].fileIndex = i + 1;
			fileheaders[i].fileID = format!"%X"(fileID);
			fileheaders[i].unk = reader.read!uint();
			writeln("Unknown 2: ", fileheaders[i].unk);
			auto compressedSize = reader.read!uint();
			writeln("Compressed Size: ", compressedSize);
			auto fileOffset = reader.read!uint();
			writeln("File ", i, " Offset: ", format!"%X"(fileOffset));
			const auto compressionMode = reader.read!uint();
			const bool isCompressed = (compressionMode == 6) ? true : false;
			fileheaders[i].isCompressed = isCompressed;
			writeln("Is file compressed? ", isCompressed);
			//Skip Padding
			reader.read!uint();
			auto uncompressedSize = reader.read!uint();
			writeln("Uncompressed Size: ", uncompressedSize);
			reader.clear();
			auto filePath = folderName ~ "/" ~ format!"%X"(fileID);
			//HOLD UP! There are entries in TDMF that have file entries that are 0 bytes long, check for that!
			if (compressedSize == 0)
			{
				writeln("FILE IS EMPTY, SKIPPING.");
				continue;
			}
			//Begin Extracting file
			if (isCompressed) {
				//Decompress and Extract File Data
				auto origOffset = archive.tell();
				extractLZ77wii(archive, fileheaders[i], fileOffset, filePath);
				fileheaders[i].extension = determineExtension(filePath ~ ".bin", filePath);
				archive.seek(origOffset);
			} else {
				//Extract File Data
				auto origOffset = archive.tell();
				archive.seek(fileOffset);
				ubyte[] fileData;
				//Uncompressed size is in compressedSize
				fileData.length = compressedSize;
				archive.rawRead(fileData);
				File uncomFile = File(filePath ~ ".bin", "wb");
				uncomFile.rawWrite(fileData);
				uncomFile.close();
				fileheaders[i].extension = determineExtension(filePath ~ ".bin", filePath);
				archive.seek(origOffset);
			}
		}
		//Add elements to JSON file as array
		ArchiveInfo info = ArchiveInfo(fileheaders, archiveheader);
		jsonfile.writeln(info.serializeToPrettyJson);
		//jsonfile.writeln(fileheaders.serializeToPrettyJson);
		//jsonarch.writeln(archiveheader.serializeToPrettyJson);
		jsonfile.close();
		//jsonarch.close();
		break;
	}
	archive.close();
	return 0;
}

///Takes a TDMF archive and extracts the files out of it, along with creating a helper JSON file for repacking, near equivalent to extractArchive()
void extractArchiveTDMF(File archive) {
	//Finish reading archive header
	archive.seek(0);
	while(!archive.eof) {
		ubyte[] data;
		data.length = 24;
		archive.rawRead(data);
		auto reader = binaryReader(data);
		//Skip version, we know what it is already
		reader.read!uint();
		auto archOffset = reader.read!uint();
		writeln("Archive Offset: ", format!"%X"(archOffset));
		//Skip padding
		reader.read!ulong();
		//Create Folder to place extracted files into
		auto folderName = format!"%X"(archOffset) ~ "_";
		if (!folderName.exists) {
			mkdir(folderName);
		} else {
			writeln("Folder already exists. Do you wish to overwrite it's contents?[y/n]");
			stdout.flush;
			if (startsWith(readln, "n")) {
				writeln("Permission denied. Exiting program...");
				return;
			}
		}
		const int fileAmount = reader.read!uint();
		writeln("Number of Files: ", fileAmount);
		//Skip padding
		reader.read!uint();
		reader.clear();
		//Create JSON files to place extra data into
		File jsonfile = File(folderName ~ "/" ~ format!"%X"(archOffset) ~ ".json", "w");
		//File jsonarch = File(folderName ~ "/" ~ "version.json", "w");
		FileHeader[] fileheaders;
		ArchiveHeader archiveheader;
		archiveheader.ver = ArchiveVersion.TDMF;
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
			writeln("Unknown 1: ", format!"%X"(fileID));
			fileheaders[i].fileIndex = i + 1;
			fileheaders[i].fileID = format!"%X"(fileID);
			fileheaders[i].unk = reader.read!uint();
			writeln("Unknown 2: ", fileheaders[i].unk);
			auto compressedSize = reader.read!uint();
			writeln("Compressed Size: ", compressedSize);
			auto fileOffset = reader.read!uint();
			writeln("File ", i, " Offset: ", format!"%X"(fileOffset));
			const auto compressionMode = reader.read!uint();
			const bool isCompressed = (compressionMode == 6) ? true : false;
			fileheaders[i].isCompressed = isCompressed;
			writeln("Is file compressed? ", isCompressed);
			//Skip Padding
			reader.read!uint();
			auto uncompressedSize = reader.read!uint();
			writeln("Uncompressed Size: ", uncompressedSize);
			reader.clear();
			auto filePath = folderName ~ "/" ~ format!"%X"(fileID);
			//HOLD UP! There are entries in TDMF that have file entries that are 0 bytes long, check for that!
			if (compressedSize == 0)
			{
				writeln("FILE IS EMPTY, SKIPPING.");
				continue;
			}
			//Begin Extracting file
			if (isCompressed) {
				//Decompress and Extract File Data
				auto origOffset = archive.tell();
				extractLZ77wii(archive, fileheaders[i], fileOffset, filePath);
				fileheaders[i].extension = determineExtension(filePath ~ ".bin", filePath);
				archive.seek(origOffset);
			} else {
				//Extract File Data
				auto origOffset = archive.tell();
				archive.seek(fileOffset);
				ubyte[] fileData;
				//Uncompressed size is in compressedSize
				fileData.length = compressedSize;
				archive.rawRead(fileData);
				File uncomFile = File(filePath ~ ".bin", "wb");
				uncomFile.rawWrite(fileData);
				uncomFile.close();
				fileheaders[i].extension = determineExtension(filePath ~ ".bin", filePath);
				writefln("File extension is %s", fileheaders[i].extension);
				archive.seek(origOffset);
			}
		}
		//Add elements to JSON file as array
		ArchiveInfo info = ArchiveInfo(fileheaders, archiveheader);
		jsonfile.writeln(info.serializeToPrettyJson);
		//jsonfile.writeln(fileheaders.serializeToPrettyJson);
		//jsonarch.writeln(archiveheader.serializeToPrettyJson);
		jsonfile.close();
		//jsonarch.close();
		break;
	}
	archive.close();
	return;
}

///Takes a TNDM archive and extracts the files out of it, along with creating a helper JSON file for repacking, near equivalent to extractArchive()
void extractArchiveTNDM(File archive) {
	//Finish reading archive header
	archive.seek(0);
	while(!archive.eof) {
		ubyte[] data;
		data.length = 24;
		archive.rawRead(data);
		auto reader = binaryReader(data);
		reader.read!uint();
		auto archOffset = reader.read!uint();
		writeln("Archive Offset: ", format!"%X"(archOffset));
		//Skip padding
		reader.read!ulong();
		//Create Folder to place extracted files into
		auto folderName = format!"%X"(archOffset) ~ "_";
		if (!folderName.exists) {
			mkdir(folderName);
		} else {
			writeln("Folder already exists. Do you wish to overwrite it's contents?[y/n]");
			stdout.flush;
			if (startsWith(readln, "n")) {
				writeln("Permission denied. Exiting program...");
				return;
			}
		}
		const int fileAmount = reader.read!uint();
		writeln("Number of Files: ", fileAmount);
		uint unk_data = reader.read!uint();
		reader.clear();
		//Create JSON files to place extra data into
		File jsonfile = File(folderName ~ "/" ~ format!"%X"(archOffset) ~ ".json", "w");
		//File jsonarch = File(folderName ~ "/" ~ "version.json", "w");
		FileHeader[] fileheaders;
		ArchiveHeader archiveheader;
		archiveheader.ver = ArchiveVersion.TNDM;
		archiveheader.NDMunk = unk_data;
		fileheaders.length = fileAmount;
		//Determine information about file headers
		for (int i = 0; i < fileAmount; i++) {
			data = [];
			data.length = 32;
			archive.rawRead(data);
			reader.source(data);
			writeln("====FILE ", i + 1, " INFORMATION====");
			//Read file information while also applying them to our struct
			auto fileID = reader.read!uint();
			writeln("File ID: ", format!"%X"(fileID));
			fileheaders[i].fileIndex = i + 1;
			fileheaders[i].fileID = format!"%X"(fileID);
			fileheaders[i].unk = reader.read!uint();
			writeln("Unknown: ", fileheaders[i].unk);
			auto compressedSize = reader.read!uint();
			writeln("Compressed Size: ", compressedSize);
			auto fileOffset = reader.read!uint();
			writeln("File ", i, " Offset: ", format!"%X"(fileOffset));
			auto uncompressedSize = reader.read!uint();
			writeln("Uncompressed Size: ", uncompressedSize);
			//Get some extra data
			fileheaders[i].NDMunk1 = reader.read!uint();
			fileheaders[i].NDMunk2 = reader.read!uint();
			fileheaders[i].NDMunk3 = reader.read!uint();
			reader.clear();
			auto filePath = folderName ~ "/" ~ format!"%X"(fileID);
			//HOLD UP! There are entries in TDMF that have file entries that are 0 bytes long, check for that!
			if (compressedSize == 0)
			{
				writeln("FILE IS EMPTY, SKIPPING.");
				continue;
			}
			//Begin Extracting file
			if (true) {
				//Decompress and Extract File Data
				auto origOffset = archive.tell();
				//BEGIN STUPIDITY, Read ENTIRE data into bufffer and uncompress
				archive.seek(fileOffset);
				ubyte[] comData;
				comData.length = compressedSize;
				archive.rawRead(comData);
				ubyte[] fileData;
				//We need to spoof header data
				fileData ~= 0x1F;
				fileData ~= 0x8B;
				fileData ~= 0x08;
				fileData ~= 0x00;
				fileData ~= 0x00;
				fileData ~= 0x00;
				fileData ~= 0x00;
				fileData ~= 0x00;
				fileData = cast(ubyte[]) uncompress(comData, cast(size_t)uncompressedSize, -15);
				File uncomFile = File(filePath ~ ".bin", "wb");
				uncomFile.rawWrite(fileData);
				uncomFile.close();
				fileheaders[i].extension = determineExtension(filePath ~ ".bin", filePath);
				writefln("File extension is %s", fileheaders[i].extension);
				archive.seek(origOffset);
			} else {
				//Extract File Data
				auto origOffset = archive.tell();
				archive.seek(fileOffset);
				ubyte[] fileData;
				//Uncompressed size is in compressedSize
				fileData.length = compressedSize;
				archive.rawRead(fileData);
				File uncomFile = File(filePath ~ ".bin", "wb");
				uncomFile.rawWrite(fileData);
				uncomFile.close();
				fileheaders[i].extension = determineExtension(filePath ~ ".bin", filePath);
				writefln("File extension is %s", fileheaders[i].extension);
				archive.seek(origOffset);
			}
		}
		//Add elements to JSON file as array
		ArchiveInfo info = ArchiveInfo(fileheaders, archiveheader);
		jsonfile.writeln(info.serializeToPrettyJson);
		//jsonfile.writeln(fileheaders.serializeToPrettyJson);
		//jsonarch.writeln(archiveheader.serializeToPrettyJson);
		jsonfile.close();
		//jsonarch.close();
		break;
	}
	archive.close();
	return;
}