// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RPSBattleSimulator",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "RPSBattleSimulator",
            targets: ["RPSBattleSimulator"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "RPSBattleSimulator",
            path: "RPSBattleSimulator/RPSBattleSimulator",
            exclude: [
                "Info.plist",
                "RPSBattleSimulator.entitlements"
            ]
        ),
    ]
)
