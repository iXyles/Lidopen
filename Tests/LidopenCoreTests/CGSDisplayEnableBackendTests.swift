import LidopenCore
import Testing

@Suite(.serialized)
struct CGSDisplayEnableBackendTests {
    @Test func missingSymbolReportsUnavailableCapability() {
        let backend = CGSDisplayEnableBackend(loader: FakeCGSLoader(symbols: [:], loaded: true))

        let capabilities = backend.capabilities(for: DisplaySnapshot(displays: [.builtIn()]))

        #expect(capabilities.isAvailable == false)
        #expect(capabilities.canDisableBuiltIn == false)
    }

    @Test func disableCallsConfigureDisplayEnabledWithZero() throws {
        FakeCGSLoader.reset()
        let backend = CGSDisplayEnableBackend(
            loader: FakeCGSLoader(
                symbols: [
                    "CGSConfigureDisplayEnabled": FakeCGSLoader.makeSymbol(FakeCGSLoader.configureDisplayEnabled),
                ],
                loaded: true
            )
        )

        try backend.disableBuiltIn(in: DisplaySnapshot(displays: [.builtIn()]))

        #expect(FakeCGSLoader.recordedEnabledValue() == 0)
    }

    @Test func restoreCallsConfigureDisplayEnabledWithOne() throws {
        FakeCGSLoader.reset()
        let backend = CGSDisplayEnableBackend(
            loader: FakeCGSLoader(
                symbols: [
                    "CGSConfigureDisplayEnabled": FakeCGSLoader.makeSymbol(FakeCGSLoader.configureDisplayEnabled),
                ],
                loaded: true
            )
        )

        try backend.restoreBuiltIn(in: DisplaySnapshot(displays: [.builtIn()]))

        #expect(FakeCGSLoader.recordedEnabledValue() == 1)
    }
}
