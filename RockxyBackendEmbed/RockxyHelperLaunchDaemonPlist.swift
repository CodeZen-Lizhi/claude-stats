import Foundation

public enum RockxyHelperLaunchDaemonPlist {
    public static func dictionary(
        machServiceName: String,
        bundleProgram: String,
        allowedCallerIdentifiers: [String]
    ) -> [String: Any] {
        [
            "Label": machServiceName,
            "BundleProgram": bundleProgram,
            "MachServices": [machServiceName: true],
            "AssociatedBundleIdentifiers": allowedCallerIdentifiers,
        ]
    }

    public static func data(
        machServiceName: String,
        bundleProgram: String,
        allowedCallerIdentifiers: [String]
    ) throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: dictionary(
                machServiceName: machServiceName,
                bundleProgram: bundleProgram,
                allowedCallerIdentifiers: allowedCallerIdentifiers
            ),
            format: .xml,
            options: 0
        )
    }
}
