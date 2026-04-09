import Foundation

public enum UITestAutomation {
    public static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["TALKTODO_UI_TEST_MODE"] == "1"
    }
}
