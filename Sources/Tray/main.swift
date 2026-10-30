import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())
switch (arguments.first, arguments.count) {
case (nil, _):
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)  // also when run as a bare binary, outside Tray.app
    let menuBar = MenuBar()
    app.run()
    withExtendedLifetime(menuBar) {}
case ("--dump", 1):
    dump()
case ("--capture", 2):
    exit(captureCommand(to: arguments[1]))
case ("--move", 3):
    guard let windowID = CGWindowID(arguments[1]) else { exit(64) }
    Task { exit(await moveCommand(windowID: windowID, to: arguments[2])) }
    CFRunLoopRun()  // event taps need the main run loop
default:
    FileHandle.standardError.write(Data("usage: Tray [--dump | --capture <dir> | --move <windowID> <right|tray>]\n".utf8))
    exit(64)
}
