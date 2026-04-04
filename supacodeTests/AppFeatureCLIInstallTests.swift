import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import Testing

@testable import supacode

@MainActor
struct AppFeatureCLIInstallTests {
  @Test(.dependencies) func installCLICallsClientAndShowsSuccessAlert() async {
    let installed = LockIsolated(false)
    let store = TestStore(
      initialState: AppFeature.State(settings: SettingsFeature.State())
    ) {
      AppFeature()
    } withDependencies: {
      $0.cliInstallClient.install = { _ in
        installed.setValue(true)
      }
      $0.cliInstallClient.installationStatus = { _ in .installed(path: "/usr/local/bin/prowl") }
    }

    await store.send(.installCLI)
    await store.receive(\.cliInstallCompleted.success) {
      $0.alert = AlertState {
        TextState("Command Line Tool Installed")
      } actions: {
        ButtonState(action: .dismiss) { TextState("OK") }
      } message: {
        TextState("The prowl command is now available at /usr/local/bin/prowl.")
      }
    }
    await store.receive(\.settings.refreshCLIInstallStatus) {
      $0.settings.cliInstallStatus = .installed(path: "/usr/local/bin/prowl")
    }

    #expect(installed.value == true)
  }

  @Test(.dependencies) func installCLIShowsErrorAlertOnFailure() async {
    let store = TestStore(
      initialState: AppFeature.State(settings: SettingsFeature.State())
    ) {
      AppFeature()
    } withDependencies: {
      $0.cliInstallClient.install = { _ in
        throw CLIInstallError(message: "Permission denied")
      }
      $0.cliInstallClient.installationStatus = { _ in .notInstalled }
    }

    await store.send(.installCLI)
    await store.receive(\.cliInstallCompleted.failure) {
      $0.alert = AlertState {
        TextState("Command Line Tool Error")
      } actions: {
        ButtonState(action: .dismiss) { TextState("OK") }
      } message: {
        TextState("Permission denied")
      }
    }
    await store.receive(\.settings.refreshCLIInstallStatus)
  }

  @Test(.dependencies) func uninstallCLICallsClientAndShowsSuccessAlert() async {
    let uninstalled = LockIsolated(false)
    let store = TestStore(
      initialState: AppFeature.State(settings: SettingsFeature.State())
    ) {
      AppFeature()
    } withDependencies: {
      $0.cliInstallClient.uninstall = { _ in
        uninstalled.setValue(true)
      }
      $0.cliInstallClient.installationStatus = { _ in .notInstalled }
    }

    await store.send(.uninstallCLI)
    await store.receive(\.cliInstallCompleted.success) {
      $0.alert = AlertState {
        TextState("Command Line Tool Uninstalled")
      } actions: {
        ButtonState(action: .dismiss) { TextState("OK") }
      } message: {
        TextState("The prowl command line tool has been removed.")
      }
    }
    await store.receive(\.settings.refreshCLIInstallStatus)

    #expect(uninstalled.value == true)
  }

  @Test(.dependencies) func commandPaletteInstallCLIDelegateForwardsToInstallCLI() async {
    let installed = LockIsolated(false)
    let store = TestStore(
      initialState: AppFeature.State(settings: SettingsFeature.State())
    ) {
      AppFeature()
    } withDependencies: {
      $0.cliInstallClient.install = { _ in
        installed.setValue(true)
      }
      $0.cliInstallClient.installationStatus = { _ in .installed(path: "/usr/local/bin/prowl") }
    }

    await store.send(.commandPalette(.delegate(.installCLI)))
    await store.receive(\.installCLI)
    await store.receive(\.cliInstallCompleted.success) {
      $0.alert = AlertState {
        TextState("Command Line Tool Installed")
      } actions: {
        ButtonState(action: .dismiss) { TextState("OK") }
      } message: {
        TextState("The prowl command is now available at /usr/local/bin/prowl.")
      }
    }
    await store.receive(\.settings.refreshCLIInstallStatus) {
      $0.settings.cliInstallStatus = .installed(path: "/usr/local/bin/prowl")
    }

    #expect(installed.value == true)
  }

  @Test(.dependencies) func settingsInstallCLIDelegateForwardsToInstallCLI() async {
    let installed = LockIsolated(false)
    let store = TestStore(
      initialState: AppFeature.State(settings: SettingsFeature.State())
    ) {
      AppFeature()
    } withDependencies: {
      $0.cliInstallClient.install = { _ in
        installed.setValue(true)
      }
      $0.cliInstallClient.installationStatus = { _ in .installed(path: "/usr/local/bin/prowl") }
    }

    await store.send(.settings(.delegate(.installCLIRequested)))
    await store.receive(\.installCLI)
    await store.receive(\.cliInstallCompleted.success) {
      $0.alert = AlertState {
        TextState("Command Line Tool Installed")
      } actions: {
        ButtonState(action: .dismiss) { TextState("OK") }
      } message: {
        TextState("The prowl command is now available at /usr/local/bin/prowl.")
      }
    }
    await store.receive(\.settings.refreshCLIInstallStatus) {
      $0.settings.cliInstallStatus = .installed(path: "/usr/local/bin/prowl")
    }

    #expect(installed.value == true)
  }

  @Test(.dependencies) func settingsUninstallCLIDelegateForwardsToUninstallCLI() async {
    let uninstalled = LockIsolated(false)
    let store = TestStore(
      initialState: AppFeature.State(settings: SettingsFeature.State())
    ) {
      AppFeature()
    } withDependencies: {
      $0.cliInstallClient.uninstall = { _ in
        uninstalled.setValue(true)
      }
      $0.cliInstallClient.installationStatus = { _ in .notInstalled }
    }

    await store.send(.settings(.delegate(.uninstallCLIRequested)))
    await store.receive(\.uninstallCLI)
    await store.receive(\.cliInstallCompleted.success) {
      $0.alert = AlertState {
        TextState("Command Line Tool Uninstalled")
      } actions: {
        ButtonState(action: .dismiss) { TextState("OK") }
      } message: {
        TextState("The prowl command line tool has been removed.")
      }
    }
    await store.receive(\.settings.refreshCLIInstallStatus)

    #expect(uninstalled.value == true)
  }
}
