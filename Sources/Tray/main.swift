import Foundation

switch CommandLine.arguments.dropFirst().first {
case "--dump":
    dump()
default:
    FileHandle.standardError.write(Data("usage: Tray --dump\n(app mode is not implemented yet)\n".utf8))
    exit(64)
}
