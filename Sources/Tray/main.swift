import AppKit

switch CommandLine.arguments.dropFirst().first {
case nil:
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)  // also when run as a bare binary, outside Tray.app
    let menuBar = MenuBar()
    app.run()
    withExtendedLifetime(menuBar) {}
case "--dump":
    dump()
default:
    FileHandle.standardError.write(Data("usage: Tray [--dump]\n".utf8))
    exit(64)
}
