import tdmarchive;
import std.file;
import std.path;
import std.stdio;

int main(string[] args)
{
	//Setup Arguments
	if (args.length == 1) {
		writeln("No arguments given. Please provide archive/folder.");
		return 1;
	}
	int workSuccess;
	switch(args[1])
	{
		case "extract":
			if (args[2] != null)
			{
				writeln("Extracting Archive...");
				File archive = File(args[2], "rb");
				workSuccess = extractArchive(archive);
			}
			else
			{
				throw new Exception("No filename given. Please provide filename or full filepath to file");
			}
			writeln("Done!");
			return workSuccess;
		case "repack":
			if (args[2] != null)
			{
				writeln("Repacking Folder...");
				workSuccess = repackArchive(args[2]);
			}
			else
			{
				throw new Exception("No foldername given. Please provide foldername or full filepath to folder");
			}
			writeln("Done!");
			return workSuccess;
		default:
			//Determine whether we are dealing with a file or a folder
			if (args[1].isFile()) {
				//Argument is file, so begin by opening the archive file
				writeln("Extracting Archive...");
				File archive = File(args[1], "rb");
				workSuccess = extractArchive(archive);
			} else {
				//Argument is directory, so begin packing directory
				writeln("Repacking Folder...");
				workSuccess = repackArchive(args[1]);
			}
			writeln("Done!");
			return workSuccess;
	}
}