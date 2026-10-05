ObjC.import('AppKit');
function run() {
    var app = $.NSWorkspace.sharedWorkspace.frontmostApplication;
    if (app.isNil() || ObjC.unwrap(app.bundleIdentifier) !== 'com.tinyspeck.slackmacgap') {
        throw new Error('Slack is not the foreground app; paste stopped');
    }
}
