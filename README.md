# tdmextractor
An Archive Extractor &amp; Repacker for "The Denpa Men" series
<br/>This tool can replace the usage of the existing quickbms script for The Denpa Men 3
<br/>Compatibility should be near 100% for archives in all games.
# Current Features
- Extraction of files from TDM1/TDM2/TDM3/TDMF archives
- Repacking to TDM1/TDM2/TDM3/TDMF version archives
# Planned Features
- Drag and Drop support for files/folders on Windows(Alternative is the use of batch files and the %1 operator)
# Usage
Run the executable in CLI/Terminal. The desired file/folder you wish to handle with the tool needs to be put in the arguments like so:
<br/>`tdmextractor [name of archive/folder]`
<br/>If you input a file, the archive will extract after some time, and a folder with the filename and an underscore will appear in your directory with the files.
<br/>If you input a folder, the archive will be created after sometime and be named "[foldername]_output", to which you can properly rename the archive for use in mods.
<br/>If you attempt to extract an archive more than once in the same directory, you will be asked to write over existing files, you can choose to deny this and exit the program.
<br/>Alternatively, you can make use of the 'extract' and 'repack' commands, though with these you must be exact with providing either an archive or a folder.
# JSON Configuration
When an archive is extracted, a JSON file is created and placed in the directory with the same name as the folder.  This file contains information from the file header in the archive which is used for archive repacking. Note that these values are currently based off file headers found in The Denpa Men 3 archives.
- "fileIndex": The index of the file inside the archive, its recommended to not change this value to avoid a game crash
- "fileID": A speculative term for a 4 byte sequence that is unique to each file, if you decide to change this, update the corresponding file name as well(and contact me if it somehow works)
- "unk": An unknown value that has an effect on how the file is read ingame, its purpose is unknown but it has important functions so its recommended to not change this value
- "extension": The extension used by the particular file in the directory, its recommended to not change this value as you might crash in game
- "isCompressed": Denotes whether or not this file was originally LZ77wii compressed inside the archive, there may be a relation to "unk" so you are welcome to experiment
- "compressedUnk": In TDMF, the value after the compression mode can change depending on whether the file is compressed or not, this value is currently a placeholder in case this needs to be accurately recreated
# Building
tdmextractor requires a D compiler(DMD v2.105.3+ is recommended), downloads can be found at https://dlang.org/.<br/>Once installed, run `dub build` in your CLI/Terminal in the root directory of the repository to compile the project.
# Contributing
I have not yet established a consistent code style for this project. Keep this in mind if you decide to submit a pull request with features. I aim to keep with the D style, however https://dlang.org/dstyle.html
<br/>If you are submitting an issue, please provide as much relevant information as possible(what archive you were working with, what game in the series, steps to reproduce, relevant system information, etc.).
# Credits
- Unknown Author of the Denpa Men 3 Archive Extraction quickbms script https://aluigi.altervista.org/bms/denpamen3.bms
- Robert Pasiński for the pack-d binary i/o library https://code.dlang.org/packages/pack-d
- Marcan on WiiBrew for LZ77wii decompression algorithm https://wiibrew.org/wiki/LZ77
- Barubary on Github for LZ77wii compression algorithm https://github.com/Barubary/dsdecmp
- Sönke Ludwig, et al. for vibe-d json library https://code.dlang.org/packages/vibe-d/0.9.3
- Richard 'rcythr' Laughlin for archive library https://code.dlang.org/packages/archive
