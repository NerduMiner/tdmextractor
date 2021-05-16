# tdmextractor
An Archive Extractor &amp; Repacker for "The Denpa Men" series
<br/>This tool can replace the usage of the existing quickbms script for The Denpa Men 3
# Current Features
- Extraction of files from TDM3 archives 
# Planned Features
- Extraction of files from TDM1/TDM2/TDMF archives
- Repacking to TDM1/TDM2/TDM3/TDMF version archives
- Drag and Drop support for files/folders on Windows
# Usage
Run the executable in CLI/Terminal. The desired file you wish to handle with the tool needs to be put in the arguments like so:
<br/>`tdmextractor --file [name of archive]`
<br/>The archive will extract after some time, and a folder with the filename and an underscore will appear in your directory with the files.
# Future Configuration
When an archive is extracted, a JSON file is created and placed in the directory with the same name as the folder.  This file contains information from the file header in the archive which will be used in the future for archive repacking. Note that these values are currently based off file headers found in The Denpa Men 3 archives.
- "fileIndex": The index of the file inside the archive
- "fileID": A speculative term for a 4 byte sequence that is unique to each file
- "unk": An unknown value that has an effect on how the file is read ingame
- "extension": The extension used by the particular file in the directory, will be used for repacking purposes in the future
- "isCompressed": Denotes whether or not this file was originally LZ77wii compressed inside the archive
# Building
tdmextractor requires a D compiler(DMD is recommended), downloads can be found at https://dlang.org/.<br/>Once installed, run `dub build` in your CLI/Terminal in the root directory of the repository to compile the project.
# Credits
- Robert Pasiński for the pack-d binary i/o library https://code.dlang.org/packages/pack-d
- Marcan on WiiBrew for LZ77wii decompression algorithm https://wiibrew.org/wiki/LZ77
- Ilya Yaroshenko & Yannick Koechlin for the asdf json library https://code.dlang.org/packages/asdf
