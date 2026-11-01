# Pastel: makes Free Pascal values readable in gdb (and so in VS Code):
# - strings as text, with UTF-8 letters (without it 'ş' is 'Å'#159, and
#   strings in fields of classes and records are garbage);
# - objects as their real class (a TStrings variable that holds a
#   TStringList shows a TStringList), with their properties;
# - TStringList, TList, TFPList and JSON values (fpjson, Pastel.Json) by
#   their contents: ['elma', 'şeftali'], {"name": "Ayşe", "age": 30}.
# The Pastel VS Code extension loads it; in a terminal: gdb -x pastel.py ./myapp
import gdb

STRING_TYPES = {'ansistring', 'string', 'rawbytestring', 'utf8string'}
WIDE_TYPES = {'unicodestring', 'widestring'}


def _quote(text):
    return "'" + text.replace("'", "''") + "'"


def _read(addr, size):
    return bytes(gdb.selected_inferior().read_memory(addr, size))


def _word(addr, size):
    return int.from_bytes(_read(addr, size), 'little', signed=True)


def _string_at(data, unit, ptr):
    """The string whose characters start at data, checked against the
    length before it and the #0 after it; None if it does not look like one."""
    if data == 0:
        return ''
    try:
        # header before the characters: code page and element size (words),
        # padding on 64-bit, reference count, length
        length = _word(data - ptr, ptr)
        refs = _word(data - 2 * ptr, ptr)
        element = _word(data - 2 * ptr - (8 if ptr == 8 else 4) + 2, 2)
        if length < 0 or length > 64 * 1024 * 1024 or refs == 0 or element != unit:
            return None
        raw = _read(data, length * unit + unit)
    except gdb.MemoryError:
        return None
    if raw[length * unit:] != b'\0' * unit:
        return None
    text = raw[:length * unit].decode('utf-16-le' if unit == 2 else 'utf-8', errors='replace')
    return None if '\0' in text else text


class PascalString:
    def __init__(self, value, unit):
        self.value = value
        self.unit = unit

    def to_string(self):
        try:
            ptr = gdb.lookup_type('void').pointer().sizeof
            addr = self.value.address
            if addr is None:
                return None
            addr = int(addr)
            # a variable: gdb already points at the characters
            text = _string_at(addr, self.unit, ptr)
            if text is None:
                # a field: gdb points at the field, which holds the pointer
                text = _string_at(_word(addr, ptr) & ((1 << (8 * ptr)) - 1), self.unit, ptr)
            return None if text is None else _quote(text)
        except (gdb.error, gdb.MemoryError):
            return None


def _ptr():
    return gdb.lookup_type('void').pointer().sizeof


def _uword(addr):
    return int.from_bytes(_read(addr, _ptr()), 'little', signed=False)


def _short_string(addr):
    n = _read(addr, 1)[0]
    return _read(addr + 1, n).decode('utf-8', errors='replace') if n else ''


def _class_chain(obj):
    """The class names of the object at obj, its own first: from the VMT
    (vmtParent is a reference to the parent's VMT)."""
    ptr = _ptr()
    names = []
    vmt = _uword(obj)
    while vmt and len(names) < 40:
        names.append(_short_string(_uword(vmt + 3 * ptr)))
        ref = _uword(vmt + 2 * ptr)
        vmt = _uword(ref) if ref else 0
    return names


def _is_object_pointer(t):
    """A class type: in gdb a pointer to a struct that starts with TObject."""
    t = t.strip_typedefs()
    if t.code != gdb.TYPE_CODE_PTR:
        return False
    s = t.target().strip_typedefs()
    for _ in range(40):
        if s.code != gdb.TYPE_CODE_STRUCT:
            return False
        if (s.name or '').lower() == 'tobject':
            return True
        bases = [f for f in s.fields() if f.is_base_class]
        if not bases:
            return False
        s = bases[0].type.strip_typedefs()
    return False


def _as(value, class_name):
    """The object at value as an instance of class_name (None when gdb does not know the class)."""
    try:
        t = gdb.lookup_type(class_name)
    except gdb.error:
        return None
    try:
        if t.strip_typedefs().code == gdb.TYPE_CODE_PTR:   # class types are pointers in gdb
            return value.cast(t).dereference()
        return value.cast(t.pointer()).dereference()
    except gdb.error:
        return None


def _fields(struct):
    """The fields of an object, those of its parents too; a property hides
    the field behind it (Count, not FCount)."""
    out = []

    def walk(v):
        for f in v.type.strip_typedefs().fields():
            if f.is_base_class:
                if (f.type.name or '').lower() != 'tobject':
                    walk(v[f])
            elif f.name and not f.name.startswith('_vptr'):
                out.append((f.name, f))
    walk(struct)
    names = {n.lower() for n, _ in out}
    seen = set()
    result = []
    for n, f in out:
        low = n.lower()
        if low in seen or (low.startswith('f') and low[1:] in names):
            continue
        seen.add(low)
        try:
            result.append((n, struct[n]))
        except gdb.error:
            pass
    return result


def _int(v):
    return int(v)


def _list_items(lst):
    """A TFPList's pointers."""
    count = _int(lst['FCount'])
    data = lst['FList']
    ptr = _ptr()
    base = int(data)
    return [_uword(base + i * ptr) for i in range(min(count, 1000))]


def _json(obj, depth=0):
    """An fpjson value as JSON text (short)."""
    if obj == 0:
        return 'null'
    if depth > 6:
        return '...'
    chain = [c.lower() for c in _class_chain(obj)]
    raw = gdb.Value(obj).cast(gdb.lookup_type('void').pointer())
    if 'tjsonstring' in chain:
        s = _as(raw, 'TJSONString')
        return '"' + str(s['FValue']).strip("'").replace("''", "'") + '"'
    if 'tjsonboolean' in chain:
        return 'true' if bool(_as(raw, 'TJSONBoolean')['FValue']) else 'false'
    if 'tjsonnull' in chain:
        return 'null'
    if 'tjsonarray' in chain:
        a = _as(raw, 'TJSONArray')
        items = _list_items(a['FList'].dereference()['FList'].dereference())
        return '[' + ', '.join(_json(i, depth + 1) for i in items[:50]) + (', ...' if len(items) > 50 else '') + ']'
    if 'tjsonobject' in chain:
        o = _as(raw, 'TJSONObject')
        hl = o['FHash'].dereference()['FHashList'].dereference()
        count = min(_int(hl['FCount']), 200)
        strs = int(hl['FStrs'])
        items = hl['FHashList'].dereference()
        parts = []
        for i in range(count):
            it = items[i]
            name = _short_string(strs + _int(it['StrIndex']))
            parts.append('"' + name + '": ' + _json(int(it['Data']), depth + 1))
        return '{' + ', '.join(parts) + '}'
    # numbers: FValue right after the VMT pointer (TJSONData has no fields)
    import struct
    at = obj + _ptr()
    if 'tjsonintegernumber' in chain:
        return str(_word(at, 4))
    if 'tjsonint64number' in chain:
        return str(_word(at, 8))
    if 'tjsonqwordnumber' in chain:
        return str(int.from_bytes(_read(at, 8), 'little'))
    if 'tjsonfloatnumber' in chain:
        return repr(struct.unpack('<d', _read(at, 8))[0])
    return '?'


class PascalObject:
    def __init__(self, value):
        self.value = value
        self.chain = []
        self.real = None
        addr = int(value)
        if addr:
            self.chain = _class_chain(addr)
            for name in self.chain:
                self.real = _as(value, name)
                if self.real is not None:
                    break

    def _kind(self):
        low = [c.lower() for c in self.chain]
        if 'tjsondata' in low:
            return 'json'
        if 'tstringlist' in low:
            return 'strings'
        if 'tfplist' in low or 'tlist' in low:
            return 'list'
        return 'object'

    def to_string(self):
        try:
            if int(self.value) == 0:
                return 'nil'
            name = self.chain[0] if self.chain else '?'
            kind = self._kind()
            if kind == 'json':
                text = _json(int(self.value))
                return name + ' ' + (text if len(text) < 400 else text[:400] + '...')
            if kind == 'strings':
                return '%s (%d)' % (name, _int(self.real['FCount']))
            if kind == 'list':
                lst = self.real if 'tfplist' in [c.lower() for c in self.chain] else self.real['FList'].dereference()
                return '%s (%d)' % (name, _int(lst['FCount']))
            return name
        except (gdb.error, gdb.MemoryError):
            return None

    def children(self):
        try:
            if self.real is None or int(self.value) == 0:
                return
            kind = self._kind()
            if kind == 'strings':
                items = self.real['FList'].dereference()
                for i in range(min(_int(self.real['FCount']), 1000)):
                    yield '[%d]' % i, items[i]['FString']
                return
            if kind == 'list':
                lst = self.real if 'tfplist' in [c.lower() for c in self.chain] else self.real['FList'].dereference()
                for i, p in enumerate(_list_items(lst)):
                    yield '[%d]' % i, gdb.Value(p).cast(gdb.lookup_type('void').pointer())
                return
            if kind == 'json':
                return
            for n, v in _fields(self.real):
                yield n, v
        except (gdb.error, gdb.MemoryError):
            return

    def display_hint(self):
        return 'array' if self._kind() in ('strings', 'list') else None


def lookup(value):
    key = (value.type.name or str(value.type) or '').lower()
    if key in STRING_TYPES:
        return PascalString(value, 1)
    if key in WIDE_TYPES:
        return PascalString(value, 2)
    try:
        if _is_object_pointer(value.type):
            return PascalObject(value)
    except gdb.error:
        pass
    return None


gdb.pretty_printers.append(lookup)

# Pastel programs use UTF-8 for all text
try:
    gdb.execute('set host-charset UTF-8')
    gdb.execute('set target-charset UTF-8')
except gdb.error:
    pass
