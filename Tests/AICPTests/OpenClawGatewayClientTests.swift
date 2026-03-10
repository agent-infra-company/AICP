import XCTest
@testable import AICP

final class OpenClawGatewayClientTests: XCTestCase {
    func testBuildDeviceAuthSignaturePayloadMatchesCanonicalV3Shape() {
        let payload = OpenClawGatewayClient.buildDeviceAuthSignaturePayload(
            deviceId: "dev-1",
            clientId: "openclaw-macos",
            clientMode: "ui",
            role: "operator",
            scopes: ["operator.admin", "operator.read"],
            signedAtMs: 1_700_000_000_000,
            token: "tok-123",
            nonce: "nonce-abc",
            platform: "  MACOS 14.5.0  ",
            deviceFamily: "  Mac  "
        )

        XCTAssertEqual(
            payload,
            "v3|dev-1|openclaw-macos|ui|operator|operator.admin,operator.read|1700000000000|tok-123|nonce-abc|macos 14.5.0|mac"
        )
    }

    func testNormalizeMetadataFieldUsesASCIIOnlyLowercase() {
        XCTAssertEqual(OpenClawGatewayClient.normalizeMetadataField("  MAC  "), "mac")
        XCTAssertEqual(OpenClawGatewayClient.normalizeMetadataField("  İOS  "), "İos")
        XCTAssertEqual(OpenClawGatewayClient.normalizeMetadataField(nil), "")
    }

    func testParseLocalGatewayCredentialReadsTokenMode() throws {
        let data = """
        {
          "gateway": {
            "auth": {
              "mode": "token",
              "token": "local-gateway-token"
            }
          }
        }
        """.data(using: .utf8)!

        let parsed = OpenClawGatewayClient.parseLocalGatewayCredential(fromConfigData: data)
        XCTAssertEqual(parsed?.mode, "token")
        XCTAssertEqual(parsed?.credential, "local-gateway-token")
    }

    func testParseLocalGatewayCredentialReadsPasswordMode() throws {
        let data = """
        {
          "gateway": {
            "auth": {
              "mode": "password",
              "password": "local-gateway-password"
            }
          }
        }
        """.data(using: .utf8)!

        let parsed = OpenClawGatewayClient.parseLocalGatewayCredential(fromConfigData: data)
        XCTAssertEqual(parsed?.mode, "password")
        XCTAssertEqual(parsed?.credential, "local-gateway-password")
    }

    func testParseLocalGatewayCredentialResolvesEnvSecretRefToken() throws {
        let data = """
        {
          "secrets": {
            "defaults": {
              "env": "default"
            }
          },
          "gateway": {
            "auth": {
              "mode": "token",
              "token": {
                "source": "env",
                "provider": "default",
                "id": "OPENCLAW_GATEWAY_TOKEN"
              }
            }
          }
        }
        """.data(using: .utf8)!

        let parsed = OpenClawGatewayClient.parseLocalGatewayCredential(
            fromConfigData: data,
            environment: ["OPENCLAW_GATEWAY_TOKEN": "env-secret-token"]
        )
        XCTAssertEqual(parsed?.mode, "token")
        XCTAssertEqual(parsed?.credential, "env-secret-token")
    }

    func testParseLaunchAgentCredentialReadsEnvironmentToken() throws {
        let plist: [String: Any] = [
            "EnvironmentVariables": [
                "OPENCLAW_GATEWAY_TOKEN": "launchd-token",
            ],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)

        let parsed = OpenClawGatewayClient.parseLaunchAgentCredential(fromPlistData: data)
        XCTAssertEqual(parsed?.mode, "token")
        XCTAssertEqual(parsed?.credential, "launchd-token")
    }

    func testParseLaunchAgentCredentialReadsProgramArgumentsPassword() throws {
        let plist: [String: Any] = [
            "ProgramArguments": [
                "/opt/homebrew/bin/openclaw",
                "gateway",
                "--password",
                "launchd-password",
            ],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)

        let parsed = OpenClawGatewayClient.parseLaunchAgentCredential(fromPlistData: data)
        XCTAssertEqual(parsed?.mode, "password")
        XCTAssertEqual(parsed?.credential, "launchd-password")
    }

    func testParseLocalGatewayCredentialResolvesFileSecretRefToken() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openclaw-secret-\(UUID().uuidString).json")
        let secretPayload: [String: Any] = [
            "gateway": [
                "token": "file-secret-token",
            ],
        ]
        let secretData = try JSONSerialization.data(withJSONObject: secretPayload)
        try secretData.write(to: fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let config: [String: Any] = [
            "secrets": [
                "defaults": [
                    "file": "default",
                ],
                "providers": [
                    "default": [
                        "source": "file",
                        "path": fileURL.path,
                        "mode": "json",
                    ],
                ],
            ],
            "gateway": [
                "auth": [
                    "mode": "token",
                    "token": [
                        "source": "file",
                        "provider": "default",
                        "id": "/gateway/token",
                    ],
                ],
            ],
        ]
        let configData = try JSONSerialization.data(withJSONObject: config)

        let parsed = OpenClawGatewayClient.parseLocalGatewayCredential(fromConfigData: configData)
        XCTAssertEqual(parsed?.mode, "token")
        XCTAssertEqual(parsed?.credential, "file-secret-token")
    }

    func testParseLocalGatewayCredentialReturnsNilForTrustedProxyMode() throws {
        let data = """
        {
          "gateway": {
            "auth": {
              "mode": "trusted-proxy",
              "token": "should-not-be-used"
            }
          }
        }
        """.data(using: .utf8)!

        let parsed = OpenClawGatewayClient.parseLocalGatewayCredential(fromConfigData: data)
        XCTAssertNil(parsed)
    }
}
