# Pastel.Files

Files, folders and paths.

    Text := ReadText('notes.txt');
    WriteText('out/report.txt', Text);        // creates out/, never leaves half a file
    for F in ListFiles('photos', '*.jpg', True) do ...
    CopyFile('a.txt', 'backup/a.txt');
    WriteLn(FormatSize(FileSize('video.mp4')));   // 1.4 GB
    Path := JoinPath(['data', 'users', 'ali.json']);

  All text is UTF-8. Errors raise EFileError with the file name and the
  reason in plain words.

`uses Pastel.Files;` · source: [framework/src/pastel.files.pas](../../framework/src/pastel.files.pas)

**Contents:** [EFileError](#efileerror) · [ReadText](#readtext) · [WriteText](#writetext) · [AppendText](#appendtext) · [ReadLines](#readlines) · [WriteLines](#writelines) · [ReadBytes](#readbytes) · [WriteBytes](#writebytes) · [ListFiles](#listfiles) · [ListDirs](#listdirs) · [EnsureDir](#ensuredir) · [CopyFile](#copyfile) · [MoveFile](#movefile) · [DeleteFileIfExists](#deletefileifexists) · [DeleteDir](#deletedir) · [FileSize](#filesize) · [FileModified](#filemodified) · [JoinPath](#joinpath) · [AppDir](#appdir) · [HomeDir](#homedir) · [MakeTempDir](#maketempdir) · [RelativePath](#relativepath) · [FormatSize](#formatsize)

## Types

### EFileError

```pascal
type EFileError = class(Exception)
```

## Routines

### ReadText

```pascal
function ReadText(const FileName: string): string
```

### WriteText

```pascal
procedure WriteText(const FileName: string; const Text: string)
```

Writes through a temporary file that replaces FileName at the end, so a
crash or full disk never leaves a half-written file. Creates folders.

### AppendText

```pascal
procedure AppendText(const FileName: string; const Text: string)
```

### ReadLines

```pascal
function ReadLines(const FileName: string): TStringArray
```

### WriteLines

```pascal
procedure WriteLines(const FileName: string; const Lines: array of string)
```

### ReadBytes

```pascal
function ReadBytes(const FileName: string): TBytes
```

### WriteBytes

```pascal
procedure WriteBytes(const FileName: string; const Data: TBytes)
```

### ListFiles

```pascal
function ListFiles(const Dir: string; const Pattern: string = '*'; Recursive: Boolean = False): TStringArray
```

### ListDirs

```pascal
function ListDirs(const Dir: string): TStringArray
```

### EnsureDir

```pascal
procedure EnsureDir(const Dir: string)
```

### CopyFile

```pascal
procedure CopyFile(const Source: string; const Dest: string; Overwrite: Boolean = True)
```

### MoveFile

```pascal
procedure MoveFile(const Source: string; const Dest: string)
```

### DeleteFileIfExists

```pascal
procedure DeleteFileIfExists(const FileName: string)
```

### DeleteDir

```pascal
procedure DeleteDir(const Dir: string)
```

Deletes a folder with everything in it.

### FileSize

```pascal
function FileSize(const FileName: string): Int64
```

### FileModified

```pascal
function FileModified(const FileName: string): TDateTime
```

### JoinPath

```pascal
function JoinPath(const Parts: array of string): string
```

### AppDir

```pascal
function AppDir: string
```

The program's own folder.

### HomeDir

```pascal
function HomeDir: string
```

### MakeTempDir

```pascal
function MakeTempDir(const Prefix: string = 'pastel'): string
```

A new, empty folder for temporary files.

### RelativePath

```pascal
function RelativePath(const FileName: string; const BaseDir: string): string
```

Path of FileName relative to BaseDir, with / or \ for this system.

### FormatSize

```pascal
function FormatSize(Bytes: Int64): string
```

1536 -> '1.5 KB', 1300000000 -> '1.2 GB'

