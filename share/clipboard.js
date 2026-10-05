ObjC.import('AppKit');
ObjC.import('Foundation');

function readText(path) {
    var value = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
    if (value.isNil()) throw new Error('Cannot read ' + path);
    return ObjC.unwrap(value);
}
function excluded(type) {
    return type === 'org.nspasteboard.ConcealedType' || type === 'org.nspasteboard.TransientType';
}
function snapshot(board) {
    var saved = [], items = board.pasteboardItems;
    if (items.isNil()) return saved;
    for (var i = 0; i < items.count; i++) {
        var item = items.objectAtIndex(i), types = item.types, record = [];
        var protectedItem = false;
        for (var k = 0; k < types.count; k++) if (excluded(ObjC.unwrap(types.objectAtIndex(k)))) protectedItem = true;
        if (protectedItem) continue;
        for (var j = 0; j < types.count; j++) {
            var type = types.objectAtIndex(j), name = ObjC.unwrap(type);
            if (excluded(name)) continue;
            var data = item.dataForType(type);
            if (data.isNil()) continue;
            record.push({type: name, data: ObjC.unwrap(data.base64EncodedStringWithOptions(0))});
        }
        if (record.length) saved.push(record);
    }
    return saved;
}
function verify(board, expected) {
    var items = board.pasteboardItems;
    var count = items.isNil() ? 0 : Number(items.count);
    if (count !== expected.length) throw new Error('Pasteboard item count mismatch');
    expected.forEach(function (record, i) {
        record.forEach(function (entry) {
            var data = items.objectAtIndex(i).dataForType(entry.type);
            if (data.isNil() || ObjC.unwrap(data.base64EncodedStringWithOptions(0)) !== entry.data) {
                throw new Error('Pasteboard read-back mismatch: ' + entry.type);
            }
        });
    });
}
function write(board, records) {
    records = records.filter(function (record) { return !record.some(function (entry) { return excluded(entry.type); }); });
    var objects = [];
    records.forEach(function (record) {
        var item = $.NSPasteboardItem.alloc.init;
        record.forEach(function (entry) {
            if (excluded(entry.type)) return;
            var data = $.NSData.alloc.initWithBase64EncodedStringOptions(entry.data, 0);
            if (data.isNil() || !item.setDataForType(data, entry.type)) throw new Error('Cannot prepare ' + entry.type);
        });
        if (record.some(function (entry) { return !excluded(entry.type); })) objects.push(item);
    });
    board.clearContents;
    if (objects.length && !board.writeObjects($(objects))) throw new Error('Cannot write pasteboard');
    verify(board, records.map(function (record) { return record.filter(function (entry) { return !excluded(entry.type); }); }).filter(function (record) { return record.length; }));
}
function run(argv) {
    var name = $.NSProcessInfo.processInfo.environment.objectForKey('ROUTINE_PASTEBOARD_NAME');
    var board = name.isNil() ? $.NSPasteboard.generalPasteboard : $.NSPasteboard.pasteboardWithName(name);
    if (argv[0] === 'backup') {
        if (!$(JSON.stringify(snapshot(board))).writeToFileAtomicallyEncodingError(argv[1], true, $.NSUTF8StringEncoding, null)) throw new Error('Cannot save clipboard backup');
    } else if (argv[0] === 'set') {
        var html = $(readText(argv[1])).dataUsingEncoding($.NSUTF8StringEncoding);
        var text = $(readText(argv[2])).dataUsingEncoding($.NSUTF8StringEncoding);
        write(board, [[{type: 'public.html', data: ObjC.unwrap(html.base64EncodedStringWithOptions(0))}, {type: 'public.utf8-plain-text', data: ObjC.unwrap(text.base64EncodedStringWithOptions(0))}]]);
    } else if (argv[0] === 'restore') {
        try { write(board, JSON.parse(readText(argv[1]))); }
        catch (error) { throw new Error('Clipboard backup preserved at ' + argv[1] + ': ' + error.message); }
    } else throw new Error('Unknown clipboard operation');
}
