(* Pastel - translations and the number and date formats of a language.

    assets/lang/tr.json:   { "Save": "Kaydet", "Delete %s?": "%s silinsin mi?" }

    Status.Text := _('Save');
    Ask(Format(_('Delete %s?'), [Name]));
    Total.Text := FormatNumber(1234.5, 2);      // 1.234,50 in Turkish

  The language is the computer's (LANG, or Windows' setting), or PASTEL_LANG,
  or UseLanguage('tr') before the forms are created. Texts in .pform files
  (Text, Caption, Title, Placeholder, Hint, Items) are translated when the
  form loads. A text without a translation stays as it is. "pastel lang"
  collects the texts of a project into the files.
  Part of the Pastel project, MIT License. *)
unit Pastel.Lang;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

{ The translation of S in the current language; S when there is none. }
function _(const S: string): string;
function Translate(const S: string): string;

{ Switches to a language ('tr', 'de', 'pt-BR'): loads assets/lang/<code>.json
  (also 'pt' for 'pt-BR') and sets the number and date formats. False when
  there are no translations for it (the formats change anyway). }
function UseLanguage(const Code: string): Boolean;
{ The current language code; 'en' at the start. }
function Language: string;
{ UseLanguage was called (Pastel.App uses the computer's language otherwise). }
function LanguageChosen: Boolean;
{ The language of the computer: PASTEL_LANG, LANG/LC_ALL, or Windows' setting. }
function SystemLanguage: string;
{ The languages that have a file in assets/lang/. }
function AvailableLanguages: TStringArray;
{ Pastel's own texts (dialog buttons...); built in for some languages. }
function FrameworkTexts: TStringArray;
{ Adds translations from code (Source=Translation pairs). }
procedure AddTranslation(const Source, Translated: string);

{ 1234.5 -> '1,234.50' (en), '1.234,50' (tr, de), '1 234,50' (fr). }
function FormatNumber(Value: Double; Decimals: Integer = 0): string;
{ The date in the language's short form: 31.10.2026, 10/31/2026, 2026-10-31... }
function FormatDateShort(D: TDateTime): string;
function FormatDateTimeShort(D: TDateTime): string;
{ 'November' / 'Kasım' (Month 1..12), in the current language. }
function MonthName(Month: Integer): string;
{ 'Mo' / 'Pzt' (Day 1 = Monday .. 7 = Sunday, like DayOfTheWeek), in the current language. }
function DayNameShort(Day: Integer): string;
{ Reads a number the way users of the language write it ('1.234,5' in tr). }
function TryParseNumber(const S: string; out Value: Double): Boolean;

implementation

uses
  StrUtils, contnrs, fpjson, Pastel.Json, Pastel.Assets{$IFDEF WINDOWS}, Windows{$ENDIF};

var
  Strings: TFPStringHashTable = nil;
  Current: string = '';

const
  { Pastel's own texts (dialog buttons...), so dialogs speak the language
    without any files; assets/lang/ can change them. }
  BuiltInKeys: array[0..31] of string = (
    'OK',
    'Cancel',
    'Abort',
    'Retry',
    'Ignore',
    'Yes',
    'No',
    'Close',
    'Open',
    'Save',
    'Choose',
    'Choose a folder',
    'File name',
    'All files',
    'The folder above',
    '"%s" was not found.',
    '"%s" exists already. Replace it?',
    'Fill this in',
    'This is not an e-mail address',
    'This is not a number',
    'This is not a whole number',
    'Give a number from %s to %s',
    'At least %d characters',
    'At most %d characters',
    'This is not in the right form',
    'E-mail',
    'Password',
    'The e-mail or the password is wrong.',
    'The server cannot be reached: %s',
    'Too many tries; wait a minute.',
    'The server answered %d.',
    'Please log in again.');
  BuiltInLangs: array[0..9] of string = ('tr', 'az', 'de', 'fr', 'es', 'it', 'pt', 'nl', 'ru', 'pl');
  BuiltIn: array[0..9, 0..31] of string = (
    ('Tamam',
     'İptal',
     'Durdur',
     'Yeniden dene',
     'Yok say',
     'Evet',
     'Hayır',
     'Kapat',
     'Aç',
     'Kaydet',
     'Seç',
     'Bir klasör seçin',
     'Dosya adı',
     'Tüm dosyalar',
     'Üst klasör',
     '"%s" bulunamadı.',
     '"%s" zaten var. Değiştirilsin mi?',
     'Bunu doldurun',
     'Bu bir e-posta adresi değil',
     'Bu bir sayı değil',
     'Bu bir tam sayı değil',
     '%s ile %s arasında bir sayı girin',
     'En az %d karakter',
     'En çok %d karakter',
     'Bu doğru biçimde değil',
     'E-posta',
     'Parola',
     'E-posta ya da parola yanlış.',
     'Sunucuya ulaşılamıyor: %s',
     'Çok fazla deneme; bir dakika bekleyin.',
     'Sunucu %d ile yanıt verdi.',
     'Lütfen yeniden giriş yapın.'),
    ('Oldu',
     'Ləğv et',
     'Dayandır',
     'Yenidən cəhd et',
     'Nəzərə alma',
     'Bəli',
     'Xeyr',
     'Bağla',
     'Aç',
     'Yadda saxla',
     'Seç',
     'Qovluq seçin',
     'Fayl adı',
     'Bütün fayllar',
     'Üst qovluq',
     '"%s" tapılmadı.',
     '"%s" artıq var. Əvəz edilsin?',
     'Bunu doldurun',
     'Bu e-poçt ünvanı deyil',
     'Bu rəqəm deyil',
     'Bu tam ədəd deyil',
     '%s ilə %s arasında rəqəm yazın',
     'Ən azı %d simvol',
     'Ən çoxu %d simvol',
     'Bu düzgün formada deyil',
     'E-poçt',
     'Parol',
     'E-poçt və ya parol səhvdir.',
     'Serverə çatmaq olmur: %s',
     'Çox cəhd; bir dəqiqə gözləyin.',
     'Server %d cavabını verdi.',
     'Zəhmət olmasa yenidən daxil olun.'),
    ('OK',
     'Abbrechen',
     'Abbrechen',
     'Wiederholen',
     'Ignorieren',
     'Ja',
     'Nein',
     'Schließen',
     'Öffnen',
     'Speichern',
     'Auswählen',
     'Ordner auswählen',
     'Dateiname',
     'Alle Dateien',
     'Übergeordneter Ordner',
     '"%s" wurde nicht gefunden.',
     '"%s" ist bereits vorhanden. Ersetzen?',
     'Bitte ausfüllen',
     'Das ist keine E-Mail-Adresse',
     'Das ist keine Zahl',
     'Das ist keine ganze Zahl',
     'Eine Zahl von %s bis %s',
     'Mindestens %d Zeichen',
     'Höchstens %d Zeichen',
     'Das hat nicht die richtige Form',
     'E-Mail',
     'Passwort',
     'E-Mail oder Passwort ist falsch.',
     'Der Server ist nicht erreichbar: %s',
     'Zu viele Versuche; bitte eine Minute warten.',
     'Der Server antwortete %d.',
     'Bitte erneut anmelden.'),
    ('OK',
     'Annuler',
     'Abandonner',
     'Réessayer',
     'Ignorer',
     'Oui',
     'Non',
     'Fermer',
     'Ouvrir',
     'Enregistrer',
     'Choisir',
     'Choisir un dossier',
     'Nom du fichier',
     'Tous les fichiers',
     'Dossier parent',
     '"%s" est introuvable.',
     '"%s" existe déjà. Le remplacer ?',
     'Veuillez remplir ce champ',
     'Ce n''est pas une adresse e-mail',
     'Ce n''est pas un nombre',
     'Ce n''est pas un nombre entier',
     'Un nombre de %s à %s',
     'Au moins %d caractères',
     'Au plus %d caractères',
     'Le format n''est pas correct',
     'E-mail',
     'Mot de passe',
     'L''e-mail ou le mot de passe est incorrect.',
     'Le serveur est injoignable : %s',
     'Trop d''essais ; attendez une minute.',
     'Le serveur a répondu %d.',
     'Veuillez vous reconnecter.'),
    ('Aceptar',
     'Cancelar',
     'Anular',
     'Reintentar',
     'Omitir',
     'Sí',
     'No',
     'Cerrar',
     'Abrir',
     'Guardar',
     'Elegir',
     'Elegir una carpeta',
     'Nombre del archivo',
     'Todos los archivos',
     'Carpeta superior',
     'No se encontró "%s".',
     '"%s" ya existe. ¿Reemplazarlo?',
     'Rellene este campo',
     'No es una dirección de correo',
     'No es un número',
     'No es un número entero',
     'Un número de %s a %s',
     'Al menos %d caracteres',
     'Como máximo %d caracteres',
     'El formato no es correcto',
     'Correo',
     'Contraseña',
     'El correo o la contraseña no son correctos.',
     'No se puede contactar con el servidor: %s',
     'Demasiados intentos; espere un minuto.',
     'El servidor respondió %d.',
     'Inicie sesión de nuevo.'),
    ('OK',
     'Annulla',
     'Interrompi',
     'Riprova',
     'Ignora',
     'Sì',
     'No',
     'Chiudi',
     'Apri',
     'Salva',
     'Scegli',
     'Scegli una cartella',
     'Nome file',
     'Tutti i file',
     'Cartella superiore',
     '"%s" non trovato.',
     '"%s" esiste già. Sostituirlo?',
     'Compila questo campo',
     'Non è un indirizzo e-mail',
     'Non è un numero',
     'Non è un numero intero',
     'Un numero da %s a %s',
     'Almeno %d caratteri',
     'Al massimo %d caratteri',
     'Il formato non è corretto',
     'E-mail',
     'Password',
     'L''e-mail o la password non è corretta.',
     'Il server non è raggiungibile: %s',
     'Troppi tentativi; attendi un minuto.',
     'Il server ha risposto %d.',
     'Accedi di nuovo.'),
    ('OK',
     'Cancelar',
     'Abortar',
     'Tentar novamente',
     'Ignorar',
     'Sim',
     'Não',
     'Fechar',
     'Abrir',
     'Salvar',
     'Escolher',
     'Escolher uma pasta',
     'Nome do arquivo',
     'Todos os arquivos',
     'Pasta acima',
     '"%s" não foi encontrado.',
     '"%s" já existe. Substituir?',
     'Preencha este campo',
     'Não é um endereço de e-mail',
     'Não é um número',
     'Não é um número inteiro',
     'Um número de %s a %s',
     'Pelo menos %d caracteres',
     'No máximo %d caracteres',
     'O formato não está correto',
     'E-mail',
     'Senha',
     'O e-mail ou a senha está errado.',
     'O servidor não está acessível: %s',
     'Tentativas demais; espere um minuto.',
     'O servidor respondeu %d.',
     'Entre novamente.'),
    ('OK',
     'Annuleren',
     'Afbreken',
     'Opnieuw',
     'Negeren',
     'Ja',
     'Nee',
     'Sluiten',
     'Openen',
     'Opslaan',
     'Kiezen',
     'Kies een map',
     'Bestandsnaam',
     'Alle bestanden',
     'Bovenliggende map',
     '"%s" is niet gevonden.',
     '"%s" bestaat al. Vervangen?',
     'Vul dit in',
     'Dit is geen e-mailadres',
     'Dit is geen getal',
     'Dit is geen geheel getal',
     'Een getal van %s tot %s',
     'Minstens %d tekens',
     'Hoogstens %d tekens',
     'Dit heeft niet de juiste vorm',
     'E-mail',
     'Wachtwoord',
     'Het e-mailadres of het wachtwoord klopt niet.',
     'De server is niet bereikbaar: %s',
     'Te veel pogingen; wacht een minuut.',
     'De server antwoordde %d.',
     'Log opnieuw in.'),
    ('ОК',
     'Отмена',
     'Прервать',
     'Повторить',
     'Пропустить',
     'Да',
     'Нет',
     'Закрыть',
     'Открыть',
     'Сохранить',
     'Выбрать',
     'Выберите папку',
     'Имя файла',
     'Все файлы',
     'Папка выше',
     '"%s" не найден.',
     '"%s" уже существует. Заменить?',
     'Заполните это поле',
     'Это не адрес электронной почты',
     'Это не число',
     'Это не целое число',
     'Число от %s до %s',
     'Не менее %d символов',
     'Не более %d символов',
     'Неверный формат',
     'Эл. почта',
     'Пароль',
     'Неверная почта или пароль.',
     'Сервер недоступен: %s',
     'Слишком много попыток; подождите минуту.',
     'Сервер ответил %d.',
     'Пожалуйста, войдите снова.'),
    ('OK',
     'Anuluj',
     'Przerwij',
     'Ponów',
     'Ignoruj',
     'Tak',
     'Nie',
     'Zamknij',
     'Otwórz',
     'Zapisz',
     'Wybierz',
     'Wybierz folder',
     'Nazwa pliku',
     'Wszystkie pliki',
     'Folder nadrzędny',
     'Nie znaleziono "%s".',
     '"%s" już istnieje. Zastąpić?',
     'Wypełnij to pole',
     'To nie jest adres e-mail',
     'To nie jest liczba',
     'To nie jest liczba całkowita',
     'Liczba od %s do %s',
     'Co najmniej %d znaków',
     'Co najwyżej %d znaków',
     'To nie ma właściwej postaci',
     'E-mail',
     'Hasło',
     'E-mail lub hasło jest nieprawidłowe.',
     'Serwer jest niedostępny: %s',
     'Zbyt wiele prób; odczekaj minutę.',
     'Serwer odpowiedział %d.',
     'Zaloguj się ponownie.'));

function FrameworkTexts: TStringArray;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, Length(BuiltInKeys));
  for I := 0 to High(BuiltInKeys) do
    Result[I] := BuiltInKeys[I];
end;

procedure LoadBuiltIn(const Code: string);
var
  L, K: Integer;
begin
  for L := 0 to High(BuiltInLangs) do
    if SameText(BuiltInLangs[L], Code) then
      for K := 0 to High(BuiltInKeys) do
        AddTranslation(BuiltInKeys[K], BuiltIn[L, K]);
end;

function _(const S: string): string;
begin
  Result := Translate(S);
end;

function Translate(const S: string): string;
begin
  if (Strings = nil) or (Strings.Count = 0) or (S = '') then
    Exit(S);
  Result := Strings.Items[S];
  if Result = '' then
    Result := S;
end;

procedure AddTranslation(const Source, Translated: string);
begin
  if Source <> '' then
    Strings.Items[Source] := Translated;
end;

function Language: string;
begin
  Result := Current;
  if Result = '' then
    Result := 'en';
end;

function LanguageChosen: Boolean;
begin
  Result := Current <> '';
end;

{ number and date formats; a small table of the common languages }
procedure SetFormats(const Code: string);
var
  L: string;
begin
  FormatSettings := DefaultFormatSettings;
  L := LowerCase(Copy(Code, 1, 2));
  case L of
    'tr', 'de', 'nl', 'it', 'es', 'pt', 'id', 'da':
      begin
        FormatSettings.DecimalSeparator := ',';
        FormatSettings.ThousandSeparator := '.';
      end;
    'fr', 'ru', 'pl', 'cs', 'sv', 'fi', 'nb', 'no', 'uk', 'hu', 'sk', 'bg':
      begin
        FormatSettings.DecimalSeparator := ',';
        FormatSettings.ThousandSeparator := ' ';
      end;
  else
    FormatSettings.DecimalSeparator := '.';
    FormatSettings.ThousandSeparator := ',';
  end;
  case L of
    'tr', 'de', 'ru', 'pl', 'cs', 'fi', 'nb', 'no', 'uk', 'sk', 'da', 'bg':
      begin
        FormatSettings.DateSeparator := '.';
        FormatSettings.ShortDateFormat := 'dd.mm.yyyy';
      end;
    'fr', 'es', 'it', 'pt', 'id':
      begin
        FormatSettings.DateSeparator := '/';
        FormatSettings.ShortDateFormat := 'dd/mm/yyyy';
      end;
    'nl':
      begin
        FormatSettings.DateSeparator := '-';
        FormatSettings.ShortDateFormat := 'dd-mm-yyyy';
      end;
    'sv', 'hu', 'ja', 'zh', 'ko':
      begin
        FormatSettings.DateSeparator := '-';
        FormatSettings.ShortDateFormat := 'yyyy-mm-dd';
      end;
  else
    if LowerCase(Code) = 'en-gb' then
    begin
      FormatSettings.DateSeparator := '/';
      FormatSettings.ShortDateFormat := 'dd/mm/yyyy';
    end
    else
    begin
      FormatSettings.DateSeparator := '/';
      FormatSettings.ShortDateFormat := 'mm/dd/yyyy';
    end;
  end;
  FormatSettings.ShortTimeFormat := 'hh:nn';
  FormatSettings.TimeSeparator := ':';
end;

function LoadFile(const Name: string): Boolean;
var
  Data: TJSONData;
  O: TJSONObject;
  I: Integer;
begin
  Result := AssetExists('lang/' + Name + '.json');
  if not Result then
    Exit;
  Data := ParseJson(AssetText('lang/' + Name + '.json'));
  try
    if not (Data is TJSONObject) then
      raise Exception.CreateFmt('assets/lang/%s.json: expected { "text": "translation", ... }', [Name]);
    O := TJSONObject(Data);
    for I := 0 to O.Count - 1 do
      if O.Items[I].JSONType = jtString then
        AddTranslation(O.Names[I], O.Items[I].AsString);
  finally
    Data.Free;
  end;
end;

function UseLanguage(const Code: string): Boolean;
var
  C, Base: string;
begin
  C := StringReplace(Trim(Code), '_', '-', [rfReplaceAll]);
  if C = '' then
    C := 'en';
  Strings.Clear;
  Current := C;
  SetFormats(C);
  Base := Copy(C, 1, Pos('-', C + '-') - 1);
  Result := False;
  LoadBuiltIn(LowerCase(Base));
  { 'pt' first, then 'pt-BR' on top of it }
  if LowerCase(Base) <> LowerCase(C) then
    Result := LoadFile(LowerCase(Base));
  Result := LoadFile(C) or LoadFile(LowerCase(C)) or Result;
end;

function SystemLanguage: string;
{$IFDEF WINDOWS}
var
  Buf: array[0..84] of WideChar;
{$ENDIF}
begin
  Result := SysUtils.GetEnvironmentVariable('PASTEL_LANG');
  if Result <> '' then
    Exit;
  {$IFDEF WINDOWS}
  if GetLocaleInfoW(LOCALE_USER_DEFAULT, $59 {LOCALE_SISO639LANGNAME}, @Buf[0], Length(Buf)) > 0 then
    Exit(UTF8Encode(UnicodeString(PWideChar(@Buf[0]))));
  {$ENDIF}
  Result := SysUtils.GetEnvironmentVariable('LC_ALL');
  if Result = '' then
    Result := SysUtils.GetEnvironmentVariable('LC_MESSAGES');
  if Result = '' then
    Result := SysUtils.GetEnvironmentVariable('LANG');
  { 'tr_TR.UTF-8' -> 'tr-TR' }
  if Pos('.', Result) > 0 then
    SetLength(Result, Pos('.', Result) - 1);
  if Pos('@', Result) > 0 then
    SetLength(Result, Pos('@', Result) - 1);
  Result := StringReplace(Result, '_', '-', [rfReplaceAll]);
  if (Result = '') or (Result = 'C') or (Result = 'POSIX') then
    Result := 'en';
end;

function AvailableLanguages: TStringArray;
var
  N: string;
begin
  Result := nil;
  for N in AssetNames do
    if (Copy(N, 1, 5) = 'lang/') and (ExtractFileExt(N) = '.json') then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := ChangeFileExt(Copy(N, 6, MaxInt), '');
    end;
end;

const
  CalendarLangs: array[0..10] of string = ('en', 'tr', 'az', 'de', 'fr', 'es', 'it', 'pt', 'nl', 'ru', 'pl');
  MonthNames: array[0..10, 1..12] of string = (
    ('January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'),
    ('Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'),
    ('Yanvar', 'Fevral', 'Mart', 'Aprel', 'May', 'İyun', 'İyul', 'Avqust', 'Sentyabr', 'Oktyabr', 'Noyabr', 'Dekabr'),
    ('Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'),
    ('janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'),
    ('enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'),
    ('gennaio', 'febbraio', 'marzo', 'aprile', 'maggio', 'giugno', 'luglio', 'agosto', 'settembre', 'ottobre', 'novembre', 'dicembre'),
    ('janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'),
    ('januari', 'februari', 'maart', 'april', 'mei', 'juni', 'juli', 'augustus', 'september', 'oktober', 'november', 'december'),
    ('Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'),
    ('styczeń', 'luty', 'marzec', 'kwiecień', 'maj', 'czerwiec', 'lipiec', 'sierpień', 'wrzesień', 'październik', 'listopad', 'grudzień'));
  DayNames: array[0..10, 1..7] of string = (
    ('Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'),
    ('Pt', 'Sa', 'Ça', 'Pe', 'Cu', 'Ct', 'Pz'),
    ('B.e', 'Ç.a', 'Ç', 'C.a', 'C', 'Ş', 'B'),
    ('Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'),
    ('lu', 'ma', 'me', 'je', 've', 'sa', 'di'),
    ('lu', 'ma', 'mi', 'ju', 'vi', 'sá', 'do'),
    ('lu', 'ma', 'me', 'gi', 've', 'sa', 'do'),
    ('seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'),
    ('ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'),
    ('Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'),
    ('pn', 'wt', 'śr', 'cz', 'pt', 'so', 'nd'));

function CalendarLang: Integer;
var
  I: Integer;
begin
  for I := 0 to High(CalendarLangs) do
    if SameText(CalendarLangs[I], Copy(Language, 1, 2)) then
      Exit(I);
  Result := 0;
end;

function MonthName(Month: Integer): string;
begin
  if (Month < 1) or (Month > 12) then
    Exit('');
  Result := _(MonthNames[CalendarLang, Month]);
end;

function DayNameShort(Day: Integer): string;
begin
  if (Day < 1) or (Day > 7) then
    Exit('');
  Result := _(DayNames[CalendarLang, Day]);
end;

function FormatNumber(Value: Double; Decimals: Integer): string;
begin
  Result := FormatFloat('#,##0' + IfThen(Decimals > 0, '.' + StringOfChar('0', Decimals), ''), Value, FormatSettings);
end;

function FormatDateShort(D: TDateTime): string;
begin
  Result := FormatDateTime(FormatSettings.ShortDateFormat, D, FormatSettings);
end;

function FormatDateTimeShort(D: TDateTime): string;
begin
  Result := FormatDateTime(FormatSettings.ShortDateFormat + ' ' + FormatSettings.ShortTimeFormat, D, FormatSettings);
end;

function TryParseNumber(const S: string; out Value: Double): Boolean;
var
  T: string;
begin
  T := StringReplace(Trim(S), FormatSettings.ThousandSeparator, '', [rfReplaceAll]);
  if FormatSettings.ThousandSeparator = ' ' then
    T := StringReplace(T, #$C2#$A0, '', [rfReplaceAll]);
  Result := TryStrToFloat(T, Value, FormatSettings);
end;

initialization
  Strings := TFPStringHashTable.Create;

finalization
  FreeAndNil(Strings);

end.
