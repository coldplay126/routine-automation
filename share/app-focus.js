ObjC.import('AppKit');
function run(argv) {
    var front = $.NSWorkspace.sharedWorkspace.frontmostApplication;
    if (front.isNil()) throw new Error('Cannot identify foreground app');
    var bundle = ObjC.unwrap(front.bundleIdentifier);
    if (argv[0] === 'capture') {
        if (!bundle) throw new Error('Foreground app has no bundle identifier');
        return bundle;
    }
    if (argv[0] !== 'restore' || !argv[1]) throw new Error('Invalid focus operation');
    // Never steal focus back after the user switches to another app.
    if (bundle !== 'com.tinyspeck.slackmacgap' || argv[1] === bundle) return;
    var apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier(argv[1]);
    if (apps.count === 0) throw new Error('Previous foreground app is no longer running');
    if (!apps.objectAtIndex(0).activateWithOptions(0)) {
        throw new Error('Cannot restore previous foreground app');
    }
}
