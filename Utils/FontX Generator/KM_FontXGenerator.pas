unit KM_FontXGenerator;
{$I ..\..\KaM_Remake.inc}
interface
uses
  Windows,
  Classes, StrUtils, SysUtils,
  KM_CommonTypes,
  KM_ResFontsEdit;

type
  TKMFontXGenerator = class
  public
    FontCount: Integer;
    Fonts: array of TKMFontGenInfo;

    class function CollectChars(aExeDir: string; aProgress: TUnicodeStringEvent): string;

    procedure LoadPresetsXML(aXMLPath: string);
    procedure SavePresetsXML(aXMLPath: string);
  end;


implementation
uses
  KM_Defaults, KM_FileIO, KM_IoXML,
  KM_ResLocales;


class function TKMFontXGenerator.CollectChars(aExeDir: string; aProgress: TUnicodeStringEvent): string;
  procedure GetAllTextPaths(const aPath: string; aList: TStringList);
  var
    slFolders: TStringList;
    searchRec: TSearchRec;
    I: Integer;
  begin
    aList.Clear;

    slFolders := TStringList.Create;
    try
      // Sample alphabets
      slFolders.Add(aExeDir + 'TextSamples' + PathDelim);

      // Game texts
      slFolders.Add(aPath + 'data' + PathDelim + 'text' + PathDelim);

      // All the missions
      slFolders.Add(aPath + 'Maps' + PathDelim);
      slFolders.Add(aPath + 'MapsMP' + PathDelim);
      slFolders.Add(aPath + 'Tutorials' + PathDelim);

      // Append all campaigns
      FindFirst(aPath + 'Campaigns' + PathDelim + '*', faDirectory, searchRec);
      repeat
        if (searchRec.Name <> '.') and (searchRec.Name <> '..') then
          slFolders.Add(aPath + 'Campaigns' + PathDelim + searchRec.Name + PathDelim);
      until (FindNext(searchRec) <> 0);
      FindClose(searchRec);

      // Append all campaigns/tutorials missions (1-level deep is enough)
      for I := slFolders.Count - 1 downto 0 do
      if DirectoryExists(slFolders[I]) then
      begin
        FindFirst(slFolders[I] + '*', faDirectory, searchRec);
        repeat
          if (searchRec.Name <> '.') and (searchRec.Name <> '..') then
            slFolders.Add(slFolders[I] + searchRec.Name + PathDelim);
        until (FindNext(searchRec) <> 0);
        FindClose(searchRec);
      end;

      // Collect all libx files
      for I := 0 to slFolders.Count - 1 do
      if DirectoryExists(slFolders[I]) then
      begin
        FindFirst(slFolders[I] + '*.libx', faAnyFile - faDirectory, searchRec);
        repeat
          aList.Add(slFolders[I] + searchRec.Name);
        until (FindNext(searchRec) <> 0);
        FindClose(searchRec);
      end;
    finally
      slFolders.Free;
    end;
  end;
var
  libxList: TStringList;
  langCode: string;
  chars: array [0..High(Word)] of Integer;
  I, K: Integer;
  libTxt: UnicodeString;
  BaseDir: string;
begin
  FillChar(chars, SizeOf(chars), 0);

  BaseDir := aExeDir;

  if DirectoryExists(aExeDir + '..\..\data\') then // Remake project location
    BaseDir := aExeDir + '..\..\';
  if DirectoryExists(aExeDir + 'data\') then // Default location
    BaseDir := aExeDir;

  // Collect list of library files
  libxList := TStringList.Create;
  gResLocales := TKMLocales.Create(BaseDir + 'data\locales.txt', DEFAULT_LOCALE);
  try
    GetAllTextPaths(BaseDir, libxList);

    for I := 0 to libxList.Count - 1 do
    if FileExists(libxList[I]) then
    begin
      aProgress(IntToStr(I) + '/' + IntToStr(libxList.Count));

      //Load ANSI file with codepage we say into unicode string
      langCode := Copy(libxList[I], Length(libxList[I]) - 7, 3);
      libTxt := ReadTextU(libxList[I], gResLocales.LocaleByCode(langCode).FontCodepage);

      for K := 0 to Length(libTxt) - 1 do
        Inc(chars[Ord(libTxt[K+1])]);
    end;

    chars[10] := 0; // End of line chars are not needed
    chars[13] := 0; // End of line chars are not needed
    chars[32] := 0; // Space symbol, KaM uses word spacing property instead
    chars[124] := 0; // | symbol, end of line in KaM

    Result := '';
    for I := 0 to High(Word) do
    if chars[I] <> 0 then
      Result := Result + WideChar(I);
  finally
    libxList.Free;
    gResLocales.Free;
  end;
end;


procedure TKMFontXGenerator.LoadPresetsXML(aXMLPath: string);
var
  newXML: TKMXMLDocument;
  nRoot, nFont: TXMLNode;
  I: Integer;
begin
  if not FileExists(aXMLPath) then Exit;

  newXML := TKMXMLDocument.Create;
  try
    newXML.LoadFromFile(aXMLPath);

    nRoot := newXML.Root;

    FontCount := nRoot.ChildNodes.Count;
    SetLength(Fonts, FontCount);

    for I := 0 to nRoot.ChildNodes.Count - 1 do
    begin
      nFont := nRoot.ChildNodes[I];
      Fonts[I].LoadFromXml(nFont);
    end;
  finally
    newXML.Free;
  end;
end;


procedure TKMFontXGenerator.SavePresetsXML(aXMLPath: string);
var
  newXML: TKMXMLDocument;
  nRoot, nFont: TXMLNode;
  I: Integer;
begin
  newXML := TKMXMLDocument.Create;
  try
    nRoot := newXML.Root;

    for I := 0 to FontCount - 1 do
    begin
      nFont := nRoot.AddChild('item' + IntToStr(I));
      Fonts[I].SaveToXml(nFont);
    end;

    newXML.SaveToFile(aXMLPath);
  finally
    newXML.Free;
  end;
end;


end.
