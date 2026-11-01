(* Pastel - writing XML: e-invoices, exports, feeds, settings for other programs.

    var
      X: TXmlWriter;
    begin
      X := TXmlWriter.Create;
      try
        X.Open('invoice', ['number', '2026-0012', 'date', '2026-11-03']);
        X.Element('customer', 'Ayşe Yılmaz');
        X.Open('lines');
        X.Element('line', 'Color', ['price', '900.50']);
        X.Close;                      // </lines>
        X.Close;                      // </invoice>
        X.SaveToFile('invoice.xml');
      finally
        X.Free;
      end;
    end;

  gives

    <?xml version="1.0" encoding="UTF-8"?>
    <invoice number="2026-0012" date="2026-11-03">
      <customer>Ayşe Yılmaz</customer>
      <lines>
        <line price="900.50">Color</line>
      </lines>
    </invoice>

  To read XML, Free Pascal's DOM and XMLRead units are there:
  ReadXMLFile(Doc, 'file.xml'), Doc.DocumentElement.FindNode('lines').
  Part of the Pastel project, MIT License. *)
unit Pastel.Xml;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  EXmlError = class(Exception);

  TXmlWriter = class
  private
    FOut: TStringList;
    FOpen: TStringList;
    FIndent: string;
    function Pad: string;
    function Attrs(const NamesAndValues: array of string): string;
  public
    constructor Create(const Indent: string = '  ');
    destructor Destroy; override;
    { <Name a="1" b="2">, and the elements that follow go inside, until Close. }
    procedure Open(const Name: string; const Attributes: array of string);
    procedure Open(const Name: string);
    { </Name> of the last Open. }
    procedure Close;
    { <Name a="1">Text</Name> (or <Name a="1"/> when Text is ''). }
    procedure Element(const Name, Text: string; const Attributes: array of string);
    procedure Element(const Name, Text: string);
    { A comment: <!-- Text --> }
    procedure Comment(const Text: string);
    { Text that is already XML, as it is. }
    procedure Raw(const Xml: string);
    function ToString: string; override;
    procedure SaveToFile(const FileName: string);
  end;

{ & < > " ' as &amp; &lt; &gt; &quot; &apos;; characters XML does not allow are left out. }
function XmlEscape(const S: string): string;

implementation

function XmlEscape(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    case S[I] of
      '&': Result := Result + '&amp;';
      '<': Result := Result + '&lt;';
      '>': Result := Result + '&gt;';
      '"': Result := Result + '&quot;';
      '''': Result := Result + '&apos;';
      #0..#8, #11, #12, #14..#31: ;
    else
      Result := Result + S[I];
    end;
end;

function ValidName(const Name: string): Boolean;
var
  I: Integer;
begin
  Result := (Name <> '') and (Name[1] in ['A'..'Z', 'a'..'z', '_', ':', #$80..#$FF]);
  for I := 2 to Length(Name) do
    if not (Name[I] in ['A'..'Z', 'a'..'z', '0'..'9', '_', ':', '-', '.', #$80..#$FF]) then
      Result := False;
end;

constructor TXmlWriter.Create(const Indent: string);
begin
  inherited Create;
  FOut := TStringList.Create;
  FOpen := TStringList.Create;
  FIndent := Indent;
  FOut.Add('<?xml version="1.0" encoding="UTF-8"?>');
end;

destructor TXmlWriter.Destroy;
begin
  FOut.Free;
  FOpen.Free;
  inherited Destroy;
end;

function TXmlWriter.Pad: string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to FOpen.Count do
    Result := Result + FIndent;
end;

function TXmlWriter.Attrs(const NamesAndValues: array of string): string;
var
  I: Integer;
begin
  Result := '';
  if Odd(Length(NamesAndValues)) then
    raise EXmlError.Create('attributes come in pairs: name, value, name, value...');
  I := 0;
  while I < High(NamesAndValues) do
  begin
    if not ValidName(NamesAndValues[I]) then
      raise EXmlError.CreateFmt('"%s" is not an XML name', [NamesAndValues[I]]);
    Result := Result + ' ' + NamesAndValues[I] + '="' + XmlEscape(NamesAndValues[I + 1]) + '"';
    Inc(I, 2);
  end;
end;

procedure TXmlWriter.Open(const Name: string; const Attributes: array of string);
begin
  if not ValidName(Name) then
    raise EXmlError.CreateFmt('"%s" is not an XML name', [Name]);
  FOut.Add(Pad + '<' + Name + Attrs(Attributes) + '>');
  FOpen.Add(Name);
end;

procedure TXmlWriter.Open(const Name: string);
begin
  Open(Name, []);
end;

procedure TXmlWriter.Close;
var
  Name: string;
begin
  if FOpen.Count = 0 then
    raise EXmlError.Create('Close without Open');
  Name := FOpen[FOpen.Count - 1];
  FOpen.Delete(FOpen.Count - 1);
  FOut.Add(Pad + '</' + Name + '>');
end;

procedure TXmlWriter.Element(const Name, Text: string; const Attributes: array of string);
begin
  if not ValidName(Name) then
    raise EXmlError.CreateFmt('"%s" is not an XML name', [Name]);
  if Text = '' then
    FOut.Add(Pad + '<' + Name + Attrs(Attributes) + '/>')
  else
    FOut.Add(Pad + '<' + Name + Attrs(Attributes) + '>' + XmlEscape(Text) + '</' + Name + '>');
end;

procedure TXmlWriter.Element(const Name, Text: string);
begin
  Element(Name, Text, []);
end;

procedure TXmlWriter.Comment(const Text: string);
begin
  FOut.Add(Pad + '<!-- ' + StringReplace(Text, '--', '- -', [rfReplaceAll]) + ' -->');
end;

procedure TXmlWriter.Raw(const Xml: string);
begin
  FOut.Add(Pad + Xml);
end;

function TXmlWriter.ToString: string;
begin
  if FOpen.Count > 0 then
    raise EXmlError.CreateFmt('<%s> is not closed', [FOpen[FOpen.Count - 1]]);
  Result := FOut.Text;
end;

procedure TXmlWriter.SaveToFile(const FileName: string);
var
  F: TFileStream;
  S: string;
begin
  S := ToString;
  F := TFileStream.Create(FileName, fmCreate);
  try
    if S <> '' then
      F.WriteBuffer(S[1], Length(S));
  finally
    F.Free;
  end;
end;

end.
