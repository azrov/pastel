# Pastel.Xml

Writing XML: e-invoices, exports, feeds, settings for other programs.

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

`uses Pastel.Xml;` · source: [framework/src/pastel.xml.pas](../../framework/src/pastel.xml.pas)

## Types

### EXmlError

```pascal
type EXmlError = class(Exception)
```

### TXmlWriter

```pascal
type TXmlWriter = class
```

| | |
|---|---|
| `constructor Create(const Indent: string = ' ')` |  |
| `destructor Destroy` |  |
| `procedure Open(const Name: string; const Attributes: array of string)` | <Name a="1" b="2">, and the elements that follow go inside, until Close. |
| `procedure Open(const Name: string)` |  |
| `procedure Close` | </Name> of the last Open. |
| `procedure Element(const Name: string; const Text: string; const Attributes: array of string)` | <Name a="1">Text</Name> (or <Name a="1"/> when Text is ''). |
| `procedure Element(const Name: string; const Text: string)` |  |
| `procedure Comment(const Text: string)` | A comment: <!-- Text --> |
| `procedure Raw(const Xml: string)` | Text that is already XML, as it is. |
| `function ToString: string` |  |
| `procedure SaveToFile(const FileName: string)` |  |

## Routines

### XmlEscape

```pascal
function XmlEscape(const S: string): string
```

& < > " ' as &amp; &lt; &gt; &quot; &apos;; characters XML does not allow are left out.

