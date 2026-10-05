ObjC.import('AppKit');
ObjC.import('Foundation');
function run(argv) {
    var name = $.NSProcessInfo.processInfo.environment.objectForKey('ROUTINE_PASTEBOARD_NAME');
    if (name.isNil() || !ObjC.unwrap(name).match(/^routine-test-/)) throw new Error('Refusing general pasteboard');
    var board = $.NSPasteboard.pasteboardWithName(name);
    if (argv[0] === 'seed') {
        var records = JSON.parse(ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(argv[1], $.NSUTF8StringEncoding, null)));
        var items = records.map(function (record) {
            var item = $.NSPasteboardItem.alloc.init;
            record.forEach(function (entry) {
                var data = $.NSData.alloc.initWithBase64EncodedStringOptions(entry.data, 0);
                if (data.isNil() || !item.setDataForType(data, entry.type)) throw new Error('Invalid fixture type');
            });
            return item;
        });
        board.clearContents;
        if (items.length && !board.writeObjects($(items))) throw new Error('Fixture write failed');
    } else if (argv[0] === 'read') {
        var result = [], items = board.pasteboardItems;
        if (!items.isNil()) for (var i = 0; i < items.count; i++) {
            var record = [], item = items.objectAtIndex(i), types = item.types;
            for (var j = 0; j < types.count; j++) {
                var type = types.objectAtIndex(j), data = item.dataForType(type);
                if (data.isNil()) continue;
                record.push({type: ObjC.unwrap(type), data: ObjC.unwrap(data.base64EncodedStringWithOptions(0))});
            }
            result.push(record);
        }
        return JSON.stringify(result);
    } else if (argv[0] === 'clear') { board.clearContents; board.releaseGlobally; }
    else throw new Error('Unknown fixture operation');
}
