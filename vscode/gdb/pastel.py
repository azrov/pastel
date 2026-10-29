# Pastel: shows Free Pascal strings in gdb as text, with UTF-8 letters.
# Without it gdb shows 'ş' as 'Å'#159, and strings that are fields of a
# class or record as garbage.
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


def lookup(value):
    key = (value.type.name or str(value.type) or '').lower()
    if key in STRING_TYPES:
        return PascalString(value, 1)
    if key in WIDE_TYPES:
        return PascalString(value, 2)
    return None


gdb.pretty_printers.append(lookup)

# Pastel programs use UTF-8 for all text
try:
    gdb.execute('set host-charset UTF-8')
    gdb.execute('set target-charset UTF-8')
except gdb.error:
    pass
