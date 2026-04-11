import Darwin
import Foundation

enum SystemCommandRunner {
    static func quit() {
        exit(EXIT_SUCCESS)
    }

    private static func run(executable: String, arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try? process.run()
    }
}
